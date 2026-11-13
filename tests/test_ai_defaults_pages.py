"""Installed-model defaults in a private shell, using synthetic model metadata."""
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import test_connectivity_pages as pages


DRIVER = r'''
import QtQuick
import Quickshell
import qs.services
import qs.modules.common

ShellRoot {
    id: root
    property int step: 0
    property int ticks: 0
    property bool failed: false
    readonly property var initialModels: [
        {name:"large:latest", size:8000000000},
        {name:"small:latest", size:2000000000}
    ]
    readonly property var moreModels: [{name:"tiny:latest", size:1000000000}].concat(initialModels)
    function check(ok, message) {
        if (!ok) { failed = true; console.log("CHECK_FAIL " + message); }
    }
    function checkIdle() {
        check(!Assistant.ready && !Assistant.busy && Assistant.queued === null,
              "choosing defaults never starts the assistant");
        check(!Ai.generating && !LocalAiRuntime.preparing,
              "choosing defaults never loads a model");
    }
    Timer {
        interval: 200; repeat: true; running: true
        onTriggered: {
            if (++root.ticks > 80) { console.log("DRIVER_TIMEOUT"); Qt.quit(); return; }
            if (!Config.ready) return;
            if (root.step === 0) {
                root.check(Config.options.assistant.model === "", "new assistant has no hard-coded model");
                root.check(Persistent.states.ai.model === "", "new chat has no hard-coded cloud model");
                Config.options.policies.ai = 2;
                Ai.refreshLocalModels();
            } else if (root.step === 1) {
                if (!Ai.localModelsLoaded) return;
                root.check(Ai.installedModelIds.length === 0, "empty active store has no installed models");
                Assistant.chooseInstalledDefault();
                root.check(Config.options.assistant.model === "", "empty store leaves assistant unselected");
                root.check(!Ai.currentModelId, "empty store does not default to a cloud model");
                Ai.localModelsLoaded = false;
                Ai.addModel("unscanned", {name:"Unscanned", model:"unscanned", local:true, size:1,
                    requires_key:false, endpoint:"http://localhost:11434/v1/chat/completions"});
                Assistant.chooseInstalledDefault();
                root.check(Config.options.assistant.model === "", "default waits for completed installed-model scan");
                root.checkIdle();
            } else if (root.step === 2) {
                Ai.installLocalModels(root.initialModels);
                Assistant.chooseInstalledDefault();
                root.check(Ai.localModelsLoaded, "successful snapshot marks discovery complete");
                root.check(Ai.currentModelId === "small_latest", "chat chooses smallest installed model");
                root.check(Ai.defaultLocalModelId === "small_latest", "default uses installed snapshot only");
                root.check(Config.options.assistant.model === "small:latest", "assistant chooses installed model while disabled");
                root.checkIdle();
                Ai.setModel("large_latest", false);
                Config.options.assistant.model = "large:latest";
            } else if (root.step === 3) {
                Ai.installLocalModels(root.moreModels);
                Assistant.chooseInstalledDefault();
                root.check(Ai.currentModelId === "large_latest", "new smaller model preserves explicit chat selection");
                root.check(Config.options.assistant.model === "large:latest", "new smaller model preserves assistant selection");
                Ai.selectedModelId = "";
                root.check(Ai.currentModelId === "large_latest", "saved chat selection survives initialization");
                Ai.installLocalModels([{name:"tiny:latest",size:1000000000}]);
                root.check(!Ai.models.large_latest && !Ai.models.small_latest, "rescan removes uninstalled catalogue entries");
                root.check(Ai.currentModelId === "tiny_latest", "missing saved chat model falls back to installed model");
                root.check(Config.options.assistant.model === "large:latest", "explicit download profile remains selected");
                root.checkIdle();
            } else if (root.step === 4) {
                Config.options.policies.ai = 1;
                Ai.addModel("cloud-fixture", {name:"Cloud",model:"cloud-fixture",local:false,requires_key:false,
                    endpoint:"https://example.invalid/v1/chat/completions"});
                Ai.setModel("cloud-fixture", false);
                Config.options.assistant.provider = "openai";
                Config.options.assistant.endpoint = "https://example.invalid/v1/chat/completions";
                Config.options.assistant.model = "cloud-fixture";
                Assistant.chooseInstalledDefault();
                root.check(Ai.currentModelId === "cloud-fixture", "explicit cloud chat choice is preserved");
                root.check(Config.options.assistant.model === "cloud-fixture", "explicit remote assistant choice is preserved");
                Config.options.assistant.model = "";
                Assistant.chooseInstalledDefault();
                root.check(Config.options.assistant.model === "", "local discovery cannot configure a remote provider");
                Config.options.assistant.provider = "ollama";
                Config.options.assistant.endpoint = "http://127.0.0.1:22345";
                Assistant.chooseInstalledDefault();
                root.check(Config.options.assistant.model === "", "custom local server has its own model catalogue");
                root.checkIdle();
            } else if (root.step === 5) {
                Config.options.assistant.endpoint = "http://localhost:11434/";
                Assistant.chooseInstalledDefault();
                root.check(Config.options.assistant.model === "tiny:latest", "standard loopback endpoint gets installed default");
                root.checkIdle();
                console.log(root.failed ? "DRIVER_FAIL" : "DRIVER_PASS");
                Qt.quit();
            }
            root.step++;
        }
    }
}
'''


@unittest.skipUnless((pages.QS and pages.CARGO and pages.DBUS) or pages.REQUIRED, "needs qs, cargo and dbus-daemon")
class AiDefaultsPagesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        pages.SettingsPagesTests.setUpClass()

    def test_defaults_follow_installed_models_without_starting_inference(self):
        with tempfile.TemporaryDirectory(prefix='velora-empty-models-') as directory:
            (Path(directory) / 'manifests').mkdir()
            with patch.dict(os.environ, {'OLLAMA_MODELS':directory}):
                case = pages.SettingsPagesTests()
                output = case.run_driver(DRIVER)
        self.assertIn('DRIVER_PASS', output, output[-9000:])
        case.assert_clean(output)
