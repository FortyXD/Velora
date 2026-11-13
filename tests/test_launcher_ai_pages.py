"""Render the launcher's AI panel in a private shell with synthetic dialogue."""
import os
from pathlib import Path
import unittest
from unittest.mock import patch
import test_connectivity_pages as pages


@unittest.skipUnless((pages.QS and pages.CARGO and pages.DBUS) or pages.REQUIRED, "needs qs, cargo and dbus-daemon")
class LauncherAiPagesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if os.environ.get('VELORA_TEST_PREBUILT'):
            pages.SettingsPagesTests.daemon = pages.TOOLS / 'target/debug/velora-connectivityd'
            pages.SettingsPagesTests.fakes = pages.TOOLS / 'target/debug/velora-connectivity-fakes'
        else:
            pages.SettingsPagesTests.setUpClass()

    def test_launcher_ai_states(self):
        artifacts = pages.PROJECT / 'cache/launcher-ai'
        artifacts.mkdir(parents=True, exist_ok=True)
        driver = r'''
import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
ShellRoot {
    id: root
    property int step: 0
    property bool capturing: false
    property bool failed: false
    property int panelWidth: 640
    function check(ok, label) { if (!ok) { failed = true; console.log("CHECK_FAIL " + label); } }
    function find(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children ?? []) { const result = find(child, name); if (result) return result; }
        return null;
    }
    function snapshot(name) {
        check(panel.height > 100 && panel.height < capture.height - 32, "panel fits " + name);
        capturing = true;
        capture.grabToImage(result => { result.saveToFile("ARTIFACTS/" + name + ".png"); capturing = false; });
    }
    FloatingWindow {
        visible: true
        implicitWidth: 720; implicitHeight: 900
        Rectangle {
            id: capture
            width: root.panelWidth + 32; height: 900
            color: Appearance.colors.colBackgroundSurfaceContainer
            AssistantPanel { id: panel; x: 16; y: 16; width: root.panelWidth }
        }
    }
    Timer {
        interval: 500; running: true; repeat: true
        onTriggered: {
            if (root.capturing) return;
            if (root.step === 0) {
                Config.options.language.ui = "ru_RU";
                Config.options.appearance.transparency.enable = false;
                Config.options.assistant.enabled = true;
                Config.options.assistant.model = "qwen3.5:latest";
                Config.options.assistant.gpu = false;
                Assistant.panelOpen = true;
                Assistant.messages = [
                    {role:"user", text:"Чем оперативная память отличается от диска?"},
                    {role:"assistant", text:"**Оперативная память** хранит то, с чем компьютер работает прямо сейчас. Она быстрая, но очищается при выключении.\n\n**Диск** хранит файлы надолго: документы, фотографии и приложения.\n\n- Оперативная память — рабочий стол.\n- Диск — шкаф для хранения."}
                ];
            } else if (root.step === 1) {
                root.snapshot("answer");
            } else if (root.step === 2) {
                Assistant.messages = [{role:"user",text:"Расскажи подробнее"}];
                Assistant.busy = true;
                Assistant.currentAction = "";
                Assistant.streaming = "Начнём с **памяти**. ";
            } else if (root.step === 3) {
                root.snapshot("cpu-generating");
            } else if (root.step === 4) {
                Assistant.busy = false;
                Assistant.streaming = "";
                Assistant.problem = "Не удалось подключиться к локальной модели. Попробуйте ещё раз.";
            } else if (root.step === 5) {
                root.snapshot("error");
            } else if (root.step === 6) {
                Assistant.problem = "";
                root.panelWidth = 400;
                Assistant.messages = [{role:"user",text:"Пример команды"},{role:"assistant",text:"Используй `pwd`, чтобы увидеть текущую папку.\n\n```sh\npwd\n```"}];
            } else if (root.step === 7) {
                root.snapshot("narrow");
            } else if (root.step === 8) {
                root.panelWidth = 640;
                Assistant.messages = [{role:"user",text:"Длинный ответ"},{role:"assistant",text:"Подробное объяснение.\n\n".repeat(100)}];
            } else if (root.step === 9) {
                root.snapshot("long-answer");
            } else {
                console.log(root.failed ? "DRIVER_FAIL launcher visuals" : "DRIVER_PASS");
                Qt.quit();
            }
            root.step++;
        }
    }
}
'''.replace('ARTIFACTS', str(artifacts))
        case = pages.SettingsPagesTests()
        with patch.object(pages, 'SHELL', Path(os.environ.get('VELORA_QML_SOURCE', pages.SHELL))):
            output = case.run_driver(driver)
        (artifacts / 'render.log').write_text(output)
        self.assertIn('DRIVER_PASS', output, output[-7000:])
        case.assert_clean(output)
