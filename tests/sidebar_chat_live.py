"""Opt-in real Qwen smoke test. Run through run_isolated.py --gpu.
Uses copied manifests, read-only model blobs and a private Ollama server.
"""
import json
import os
from pathlib import Path
import shutil
import tempfile
from unittest.mock import patch
import test_connectivity_pages as pages


def main():
    source = Path(os.environ["OLLAMA_MODELS"])
    artifacts = pages.PROJECT / "cache/sidebar-chat"
    artifacts.mkdir(parents=True, exist_ok=True)
    pages.SettingsPagesTests.daemon = pages.TOOLS / "target/debug/velora-connectivityd"
    pages.SettingsPagesTests.fakes = pages.TOOLS / "target/debug/velora-connectivity-fakes"
    driver = r'''
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.ii.sidebarLeft
ShellRoot {
    id: root
    property bool sent: false
    property int ticks: 0
    property string lastStatus: ""
    property bool sawBusy: false
    property bool sawReasoning: false
    property bool finished: false
    property int stopStarted: 0
    property int stopped: 0
    property bool capturingAnswer: false
    property bool unloadRequested: false
    property int savedMessageCount: 0
    function find(item, name) { if (item.objectName === name) return item; for (const child of item.children ?? []) { const value = find(child, name); if (value) return value; } return null; }
    FloatingWindow {
        implicitWidth: 460; implicitHeight: 850; visible: true
        Rectangle { id: capture; anchors.fill: parent; color: Appearance.colors.colLayer0Base; AiChat { anchors.fill: parent } }
    }
    function screenshot(name) { capture.grabToImage(result => result.saveToFile("ARTIFACTS/" + name + ".png")); }
    Connections {
        target: LocalAiRuntime
        function onUnloaded(success) {
            console.log("LIVE_UNLOADED " + success);
            console.log("LIVE_CHAT_PRESERVED " + (SidebarChat.messages.length === root.savedMessageCount));
            loadedModels.running = true;
        }
    }
    Process {
        id: loadedModels
        command: ["curl","--noproxy","*","--silent","--fail","http://127.0.0.1:11434/api/ps"]
        stdout: StdioCollector { id: loadedOutput }
        onExited: (code, status) => {
            let empty = false;
            try { empty = JSON.parse(loadedOutput.text).models.length === 0; } catch (_) {}
            console.log("LIVE_MODELS_EMPTY " + empty);
            console.log(code === 0 && empty && SidebarChat.messages.length === root.savedMessageCount ? "DRIVER_PASS" : "DRIVER_FAIL");
            LocalAiRuntime.stop(); Qt.quit();
        }
    }
    Timer {
        interval: 500; repeat: true; running: true
        onTriggered: {
            root.ticks++;
            if (!root.sent && root.ticks === 4) {
                Config.options.language.ui = "ru_RU";
                Config.options.assistant.enabled = false;
                Config.options.ai.localGpu = true;
                Config.options.sidebar.ai.showThoughts = true;
                Config.options.ai.localTool = "none";
                Ai.addModel("smoke-qwen", {name:"Qwen 3.5", model:"qwen3.5:latest", local:true, requires_key:false,
                    api_format:"openai", endpoint:"http://localhost:11434/v1/chat/completions",
                    extraParams:{think:true,options:{num_gpu:-1,num_ctx:4096,num_predict:1024,temperature:0.6}}});
                Ai.setModel("smoke-qwen", false);
                SidebarChat.newConversation();
                SidebarChat.draft = "Ответь ровно одним словом: Привет";
                root.sent = SidebarChat.send();
                console.log("LIVE_SENT " + root.sent + " model=" + Ai.currentModelId);
            }
            if (root.sent && SidebarChat.busy) root.sawBusy = true;
            if (SidebarChat.statusText !== root.lastStatus) {
                root.lastStatus = SidebarChat.statusText;
                console.log("LIVE_STATUS " + root.lastStatus);
                if (root.sent) root.screenshot("live-status");
            }
            if (SidebarChat.messages.some(m => m.text.includes("<think>"))) root.sawReasoning = true;
            if (root.sent && root.sawBusy && !SidebarChat.busy && !root.finished) {
                root.finished = true;
                const answer = SidebarChat.messages.filter(m => m.role === "assistant").slice(-1)[0];
                console.log("LIVE_RESULT " + JSON.stringify({text:answer?.text,error:answer?.error,reasoning:root.sawReasoning,seconds:root.ticks/2}));
                root.capturingAnswer = true;
                capture.grabToImage(result => { result.saveToFile("ARTIFACTS/live-qwen-answer.png"); root.capturingAnswer = false; });
            }
            if (root.finished && !root.capturingAnswer && !root.stopStarted) {
                SidebarChat.draft = "Напиши длинную историю о путешествии по космосу";
                SidebarChat.send(); root.stopStarted = root.ticks;
            }
            if (root.stopStarted && !root.stopped && root.ticks > root.stopStarted + 4) {
                const button = root.find(capture, "sidebarChatStop");
                console.log("LIVE_STOP_VISIBLE " + (button && button.visible));
                if (button) button.clicked();
                root.stopped = root.ticks;
            }
            if (root.stopped && !root.unloadRequested && root.ticks > root.stopped + 2) {
                console.log("LIVE_CANCELLED " + (!SidebarChat.busy && !Ai.generating));
                root.unloadRequested = true;
                root.savedMessageCount = SidebarChat.messages.length;
                SidebarChat.releaseMemory();
            }
            if (root.ticks >= 80) { console.log("LIVE_TIMEOUT " + SidebarChat.statusText); SidebarChat.stop(); LocalAiRuntime.stop(); Qt.quit(); }
        }
    }
}
'''.replace("ARTIFACTS", str(artifacts))
    if os.environ.get("VELORA_TEST_UNLOAD_ONLY"):
        driver = driver.replace("think:true", "think:false").replace("num_predict:1024", "num_predict:128")
    with tempfile.TemporaryDirectory(prefix="velora-chat-models-") as directory:
        models = Path(directory)
        shutil.copytree(source / "manifests", models / "manifests")
        (models / "blobs").symlink_to(source / "blobs")
        with patch.dict(os.environ, {"OLLAMA_MODELS":str(models)}):
            case = pages.SettingsPagesTests()
            output = case.run_driver(driver)
        (artifacts / "live-qwen.log").write_text(output)
        print("\n".join(line for line in output.splitlines() if "LIVE_" in line or "DRIVER_" in line or "TypeError" in line or "ReferenceError" in line))
        case.assert_clean(output)
        if "DRIVER_PASS" not in output:
            raise AssertionError("Qwen did not finish; see cache/sidebar-chat/live-qwen.log")
        result = next(line.split("LIVE_RESULT ", 1)[1] for line in output.splitlines() if "LIVE_RESULT " in line)
        result = json.loads(result)
        if result.get("error") or not result.get("text", "").split("</think>")[-1].strip():
            raise AssertionError(result)


if __name__ == "__main__":
    main()
