"""Exercise local model preloading through the sidebar composer without model weights."""
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import test_connectivity_pages as pages


DRIVER = r'''
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.ii.sidebarLeft.aiChat

ShellRoot {
    id: root
    property int step: 0
    property int ticks: 0
    property bool released: false
    property bool sawRemoteInfo: false
    property bool sawPreload: false
    FileView {
        path: Quickshell.env("TEST_MODEL_CALLS")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.sawRemoteInfo = text().includes("remote-alias");
            root.sawPreload = text().includes("/api/generate");
        }
    }
    FloatingWindow {
        visible: true; implicitWidth: 400; implicitHeight: 150
        ChatComposer { id: editor; anchors.fill: parent }
    }
    Connections {
        target: LocalAiRuntime
        function onUnloaded(success) { root.released = success; }
    }
    Timer {
        interval: 75; running: true; repeat: true
        onTriggered: {
            if (++root.ticks > 130) { console.log("PRELOAD_TIMEOUT", root.step, SidebarChat.problem); Qt.quit(); return; }
            if (!Config.ready) return;
            const base = "http://127.0.0.1:11435";
            const options = {num_ctx:8192, num_gpu:0};
            if (root.step === 0) {
                Config.options.policies.ai = 2; Config.options.assistant.enabled = false;
                Config.options.assistant.contextTokens = 8192; Config.options.ai.localGpu = false;
                Config.options.ai.localTool = "none"; Config.options.ai.modelIdleSeconds = 0;
                LocalAiRuntime.preload("skip-idle", base, false, options);
                root.step++;
            } else if (root.step === 1 && root.ticks >= 10) {
                Config.options.ai.modelIdleSeconds = 90;
                LocalAiRuntime.preload("skip-cloud:cloud", base, false, options);
                LocalAiRuntime.preload("skip-custom", "http://127.0.0.1:23456", false, options);
                LocalAiRuntime.preload("remote-alias", base, false, options);
                root.step++;
            } else if (root.step === 2 && root.sawRemoteInfo && !LocalAiRuntime.users.length) {
                Ai.installLocalModels([{name:"tiny:latency", size:1024}]);
                Ai.setModel(Ai.defaultLocalModelId, false);
                SidebarChat.newConversation();
                editor.inputField.forceActiveFocus();
                editor.inputField.insert(0, "private draft");
                editor.inputField.insert(editor.inputField.length, " for submission");
                root.step++;
            } else if (root.step === 3 && root.sawPreload && LocalAiRuntime.users.includes("preload")) {
                if (SidebarChat.busy || !SidebarChat.send()) { console.log("PRELOAD_BLOCKED_SEND"); Qt.quit(); return; }
                root.step++;
            } else if (root.step === 4 && !SidebarChat.busy && SidebarChat.messages.some(m => m.text === "streamed answer")) {
                SidebarChat.releaseMemory();
                root.step++;
            } else if (root.step === 5 && root.released) {
                SidebarChat.newConversation();
                editor.inputField.forceActiveFocus();
                editor.inputField.insert(0, "paste and submit immediately");
                if (!SidebarChat.send()) { console.log("PRELOAD_BLOCKED_PASTE"); Qt.quit(); return; }
                root.step++;
            } else if (root.step === 6 && !SidebarChat.busy && !LocalAiRuntime.preparing && !LocalAiRuntime.users.length
                       && SidebarChat.messages.some(m => m.text === "streamed answer")) {
                console.log("PRELOAD_PASS");
                Qt.quit();
            }
        }
    }
}
'''

CURL = '''#!/usr/bin/python3
import json, os, sys, time
args = sys.argv[1:]
url = next(arg for arg in args if arg.startswith("http://"))
body = json.loads(args[args.index("--data-binary") + 1]) if "--data-binary" in args and args[args.index("--data-binary") + 1].startswith("{") else {}
with open(os.environ["TEST_MODEL_CALLS"], "a") as log:
    print(json.dumps([url, body]), file=log)
if url.endswith("/api/show"):
    result = {"capabilities":["completion"], "remote_host":"remote.invalid" if body["model"]=="remote-alias" else ""}
elif url.endswith("/api/chat"):
    time.sleep(0.4)
    result = {"message":{"role":"assistant","content":"streamed answer"}, "done":True}
elif url.endswith("/api/ps"):
    result = {"models":[]}
else:
    if url.endswith("/api/generate") and body.get("keep_alive"):
        time.sleep(1.25)
    result = {"done":True}
print(json.dumps(result))
'''


@unittest.skipUnless((pages.QS and pages.CARGO and pages.DBUS) or pages.REQUIRED, "needs Quickshell, cargo and D-Bus")
class ModelPreloadTests(unittest.TestCase):
    def test_login_warms_the_tool_prefix_once_without_opening_a_chat(self):
        pages.SettingsPagesTests.setUpClass()
        driver = '''import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
ShellRoot {
    property int ticks: 0
    FileView { id: pressureFile; path: Quickshell.env("TEST_MEMORY_PRESSURE") }
    Timer { interval: 100; repeat: true; running: true; onTriggered: {
        if (!Config.ready) return;
        ticks++;
        if (ticks === 2) {
            Config.options.assistant.preloadOnLogin = false;
            Config.options.assistant.enabled = true;
            Config.options.assistant.gpu = false;
            Config.options.assistant.model = "tiny:work";
            Config.options.ai.modelIdleSeconds = 120;
            Assistant.mainShell = true;
        }
        if (ticks === 24) {
            if (LocalAiRuntime.preloadKey) { console.log("UNEXPECTED_WARMUP"); Qt.quit(); }
            Config.options.assistant.preloadOnLogin = true;
        }
        if (ticks === 46) {
            if (LocalAiRuntime.preloadKey) { console.log("WARMUP_UNDER_PRESSURE"); Qt.quit(); }
            pressureFile.setText("some avg10=0.00 avg60=0.00 avg300=0.00 total=0");
        }
        if (ticks > 52 && LocalAiRuntime.preloadKey && !LocalAiRuntime.users.length) {
            console.log("STANDBY_READY", Assistant.ready, Assistant.busy, SidebarChat.active);
            Qt.quit();
        }
        if (ticks > 100) {
            console.log("STANDBY_TIMEOUT", Assistant.mainShell, Assistant.enabled, Assistant.profile.model,
                JSON.stringify(Ai.installedModelIds), PowerSaving.onBattery, PowerSaving.active, LocalAiRuntime.standbyModel,
                LocalAiRuntime.totalMemoryKiB, LocalAiRuntime.preloadKey);
            Qt.quit();
        }
    } }
}'''
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            manifest = folder/"manifests/registry.ollama.ai/library/tiny/work"
            manifest.parent.mkdir(parents=True)
            manifest.write_text(json.dumps({"layers":[{"size":1024}]}))
            curl = folder/"curl"
            curl.write_text(CURL.replace('["completion"]', '["completion","tools"]'))
            curl.chmod(0o755)
            agent = folder/"velora-agentd"
            agent.write_text("#!/bin/sh\ntest \"$1\" = --warmup-prefix || exit 1\nprintf '%s\\n' '{\"messages\":[{\"role\":\"system\",\"content\":\"fixture\"}],\"tools\":[]}'\n")
            agent.chmod(0o755)
            log = folder/"calls"
            log.touch()
            memory = folder/"meminfo"
            pressure = folder/"pressure"
            memory.write_text("MemTotal: 32768000 kB\nMemAvailable: 16000000 kB\n")
            pressure.write_text("some avg10=20.00 avg60=0.00 avg300=0.00 total=0\n")
            runtime = (pages.SHELL/"services"/"LocalAiRuntime.qml").read_text().replace(
                '"/proc/meminfo"', json.dumps(str(memory))).replace('"/proc/pressure/memory"', json.dumps(str(pressure))).replace(
                'id: standbyRetry\n        interval: 60000', 'id: standbyRetry\n        interval: 500')
            with patch.dict(os.environ, PATH=directory + os.pathsep + os.environ["PATH"],
                            TEST_MODEL_CALLS=str(log), TEST_MEMORY_PRESSURE=str(pressure), OLLAMA_MODELS=directory):
                output = pages.SettingsPagesTests().run_driver(driver, service_overrides={"LocalAiRuntime.qml":runtime})
            self.assertIn("STANDBY_READY false false false", output, output[-3000:])
            chats = [body for url, body in map(json.loads, log.read_text().splitlines()) if url.endswith("/api/chat")]
            self.assertEqual(len(chats), 1)
            self.assertEqual(chats[0]["options"]["num_predict"], 1)
    def test_editor_preloads_once_and_can_send_and_unload(self):
        pages.SettingsPagesTests.setUpClass()
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            curl = folder / "curl"
            curl.write_text(CURL)
            curl.chmod(0o755)
            log = folder / "calls"
            log.touch()
            (folder / "manifests").mkdir()
            with patch.dict(os.environ, PATH=directory + os.pathsep + os.environ["PATH"],
                            TEST_MODEL_CALLS=str(log), OLLAMA_MODELS=directory):
                case = pages.SettingsPagesTests()
                output = case.run_driver(DRIVER)
            self.assertIn("PRELOAD_PASS", output, output[-2500:])
            case.assert_clean(output)
            calls = [json.loads(line) for line in log.read_text().splitlines()]
            self.assertEqual([body["model"] for url, body in calls if url.endswith("/api/show")], ["remote-alias", "tiny:latency"])
            loads = [body for url, body in calls if url.endswith("/api/generate")]
            self.assertEqual([body["keep_alive"] for body in loads], [90, 0])
            self.assertEqual(loads[0], {"model":"tiny:latency", "options":{"num_ctx":8192, "num_gpu":0}, "keep_alive":90, "stream":False})
            self.assertTrue(all(url.startswith("http://127.0.0.1:11435/") for url, _ in calls))
