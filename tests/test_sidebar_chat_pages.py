"""Render the actual sidebar in an isolated shell, with synthetic conversation data."""
import os
from pathlib import Path
import unittest
from unittest.mock import patch
import test_connectivity_pages as pages

ARTIFACTS = pages.PROJECT / "cache/sidebar-chat"

DRIVER = r'''
import QtQuick
import QtQuick.Controls
import QtTest
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.ii.sidebarLeft
import qs.modules.ii.sidebars.parts

ShellRoot {
    id: root
    property int step: 0
    property bool grabbing: false
    property bool failed: false
    property int viewportWidth: 460
    property var afterCapture: null
    property string originalConversation: ""
    property real readingPosition: 0
    property string artifacts: "ARTIFACTS"
    TestCase { id: interaction; name: "SidebarInteractions"; when: false }
    function find(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children ?? []) { const result = find(child, name); if (result) return result; }
        return null;
    }
    function findAll(item, name) {
        let result = item.objectName === name ? [item] : [];
        for (const child of item.children ?? []) result = result.concat(findAll(child, name));
        return result;
    }
    function check(condition, name) { if (!condition) { root.failed = true; console.log("CHECK_FAIL " + name); } }
    function snapshot(name) {
        const expectedWidth = Number(name.split("-").pop());
        if (expectedWidth) root.check(capture.width === expectedWidth,"actual screenshot width " + name);
        root.grabbing = true;
        capture.grabToImage(result => { result.saveToFile(root.artifacts + "/" + name + "-SCALE.png"); root.grabbing = false; if (root.afterCapture) { const action = root.afterCapture; root.afterCapture = null; action(); } });
    }
    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 900
        implicitHeight: 850
        Rectangle {
            id: capture
            width: root.viewportWidth
            height: parent.height
            color: Appearance.colors.colLayer0Base
            AiChat { id: chat; anchors.fill: parent }
            ClipboardPart { id: clipboard; anchors.fill: parent; visible: false }
        }
    }
    Timer {
        interval: 500; repeat: true; running: true
        onTriggered: {
            if (root.grabbing) return;
            const timeline = root.find(chat, "sidebarChatTimeline");
            if (root.step === 0) {
                Config.options.language.ui = "ru_RU";
                Config.options.assistant.enabled = false;
                Config.options.appearance.transparency.enable = false;
                Ai.addModel("preview", {name:"Qwen 3.5", model:"qwen3.5", local:true, requires_key:false, endpoint:"http://localhost:11434/v1/chat/completions", api_format:"openai"});
                Ai.setModel("preview", false);
                SidebarChat.newConversation();
                root.check(!!timeline, "timeline loaded");
            } else if (root.step === 1) {
                root.snapshot("empty-dark-460"); root.afterCapture = () => {
                SidebarChat.append({role:"user", text:"Помоги организовать проект. Нужны краткий план, таблица и пример кода."});
                SidebarChat.append({role:"assistant", model:"preview", text:"## Начнём с простого\n\nРаздели проект на три части: **интерфейс**, данные и тесты. Так изменения будет проще проверять.\n\n1. Собери основные сценарии.\n2. Подготовь небольшие компоненты.\n3. Проверь длинные ответы и узкое окно.\n\n> Сначала добейся удобного чтения, затем добавляй детали.\n\n| Задача | Результат |\n| --- | --- |\n| Интерфейс | Читаемая переписка |\n| История | Сохранённые разговоры |\n\n```python\ndef greet(name):\n    return f'Привет, {name}!'\n```\n\nМожно начать с интерфейса и постепенно добавить остальные части."});
                };
            } else if (root.step === 2) {
                timeline.followTail = false; timeline.positionViewAtBeginning();
            } else if (root.step === 3) {
                root.snapshot("conversation-dark-460"); root.afterCapture = () => {
                root.check(root.find(chat,"sidebarChatInput").height > 0,"composer visible");
                const prose = root.find(chat,"chatProse");
                prose.select(0,5); root.check(prose.selectedText.length === 5,"message text can be selected"); prose.deselect();
                root.viewportWidth = 360;
                };
            } else if (root.step === 4) {
                root.snapshot("conversation-dark-360"); root.afterCapture = () => { root.viewportWidth = 760;
                };
            } else if (root.step === 5) {
                root.snapshot("conversation-dark-760"); root.afterCapture = () => {
                MaterialThemeLoader.applyColors(JSON.stringify({background:"#f7f7fc",on_background:"#20212a",surface_container_low:"#f3f3f8",surface_container:"#eaeaf2",surface_container_high:"#e3e3ed",surface_container_highest:"#dddde8",on_surface:"#20212a",on_surface_variant:"#484957",primary:"#5650a2",on_primary:"#ffffff",secondary_container:"#e6e0ff",on_secondary_container:"#262044",outline:"#747482",outline_variant:"#c8c6d4"}));
                };
            } else if (root.step === 6) {
                root.snapshot("conversation-light-760"); root.afterCapture = () => { root.viewportWidth = 460;
                };
            } else if (root.step === 7) {
                root.snapshot("conversation-light-460"); root.afterCapture = () => { root.viewportWidth = 360;
                };
            } else if (root.step === 8) {
                root.snapshot("conversation-light-360"); root.afterCapture = () => {
                root.viewportWidth = 460;
                SidebarChat.draft = "Это черновик следующего сообщения.\nЕго можно продолжать писать, пока приходит ответ.";
                SidebarChat.append({role:"assistant", text:"```javascript\nconst longLine = '" + "long ".repeat(80) + "';\n```", status:"streaming"});
                timeline.followTail = true; timeline.positionViewAtEnd();
                };
            } else if (root.step === 9) {
                root.snapshot("code-light-460"); root.afterCapture = () => {
                root.check(root.find(chat,"chatCodeScroll") !== null,"code block loaded");
                const code = root.find(chat,"chatCodeText"); code.select(0,5);
                root.check(code.selectedText.length === 5,"code text can be selected"); code.deselect();
                root.check(root.findAll(chat,"chatCodeScroll").some(item => item.contentWidth > item.width),"long code scrolls inside its block");
                SidebarChat.save(); chat.showHistory = true;
                root.originalConversation = SidebarChat.conversationId;
                };
            } else if (root.step === 10) {
                root.snapshot("history-light-460"); root.afterCapture = () => { chat.showHistory = false; chat.showModelPicker = true;
                };
            } else if (root.step === 11) {
                root.snapshot("models-light-460"); root.afterCapture = () => { chat.showModelPicker = false;
                Config.options.assistant.enabled = true;
                };
            } else if (root.step === 12) {
                Assistant.submitted("Создай архив с отчётами", "sidebar");
                Assistant.task = 123; Assistant.busy = true;
                Assistant.handle(JSON.stringify({type:"step",task:123,tool:"files_read",state:"done",result:{path:"/example/report.txt"}}));
                Assistant.handle(JSON.stringify({type:"approval",task:123,tool:"terminal_run",approval:"test",details:{command:"zip reports.zip report.txt",cwd:"/example",network:false}}));
            } else if (root.step === 13) {
                root.snapshot("approval-light-460"); root.afterCapture = () => {
                root.check(SidebarChat.messages.length === 2,"assistant shares sidebar presentation");
                root.check(SidebarChat.currentReply.hasActions,"task steps attached to response");
                SidebarChat.stop();
                };
            } else if (root.step === 14) {
                Config.options.assistant.enabled = false;
                interaction.mouseClick(root.find(chat, "sidebarChatMenu"));
                if (capture.Overlay.overlay) capture.Overlay.overlay.parent = capture;
            } else if (root.step === 15) {
                root.check(chat.optionsOpen, "options open after first click");
                root.snapshot("settings-light-460"); root.afterCapture = () => interaction.mouseClick(root.find(chat,"sidebarChatMenu"));
            } else if (root.step === 16) {
                root.check(!chat.optionsOpen, "second options click closes it");
                SidebarChat.openConversation(root.originalConversation);
            } else if (root.step === 17) {
                root.check(SidebarChat.messages.length === 3, "history restored all messages");
                root.check(!Ai.generating && !Assistant.ready, "opening history does not start a model");
                SidebarChat.branch(0);
            } else if (root.step === 18) {
                root.check(SidebarChat.conversationId !== root.originalConversation, "edit creates a separate conversation");
                root.check(SidebarChat.draft.startsWith("Помоги организовать"), "edit restores user text into composer");
                SidebarChat.openConversation(root.originalConversation);
            } else if (root.step === 19) {
                root.check(SidebarChat.messages.length === 3, "original conversation preserved after branching");
                SidebarChat.append({role:"assistant",text:"<think>Сначала сопоставлю ограничения: небольшая панель, длинные ответы и потоковый вывод. Затем выберу оформление, которое сохраняет читаемость.</think>\n\n## Спокойная типографика\n\nОсновной текст остаётся **читаемым**, а заголовки помогают ориентироваться в ответе."});
                timeline.followTail = true; timeline.positionViewAtEnd();
            } else if (root.step === 20) {
                const body = root.find(chat,"sidebarChatReasoningBody");
                root.check(body && body.implicitHeight === 0,"reasoning starts collapsed");
                root.find(chat,"sidebarChatReasoning").clicked();
                interaction.wait(100);
                root.check(body.progress > 0 && body.progress < 1,"reasoning opens gradually");
            } else if (root.step === 21) {
                root.snapshot("reasoning-open-light-460"); root.afterCapture = () => {
                    root.find(chat,"sidebarChatReasoning").clicked();
                    interaction.wait(80);
                    const body = root.find(chat,"sidebarChatReasoningBody");
                    root.check(body.progress > 0 && body.progress < 1,"reasoning closes gradually");
                };
            } else if (root.step === 22) {
                root.check(root.find(chat,"sidebarChatReasoningBody").implicitHeight === 0,"closed reasoning leaves no blank space");
                chat.visible = false; clipboard.visible = true;
                Cliphist.entries = ["1\tКороткая заметка: проверить интерфейс и сохранить результат.", "2\thttps://example.org/design", "3\tДлинная запись из буфера обмена. В ней достаточно текста, чтобы проверить переносы и аккуратное ограничение высоты строки."];
            } else if (root.step === 23) {
                root.snapshot("clipboard-light-460"); root.afterCapture = () => root.viewportWidth = 360;
            } else if (root.step === 24) {
                root.snapshot("clipboard-light-360"); root.afterCapture = () => clipboard.focusTarget.text = "example";
            } else if (root.step === 25) {
                root.check(root.find(clipboard,"clipboardList").count === 1, "clipboard filtering");
                clipboard.visible = false; chat.visible = true;
                SidebarChat.attach([root.artifacts + "/attachment.txt"]);
                root.check(SidebarChat.attachments.length === 0 && SidebarChat.problem.length > 0,"unsupported attachments explain the limitation");
                Ai.addModel("attachment-test", {name:"Attachment fixture",model:"fixture",local:true,requires_key:false,endpoint:"http://localhost/unused",api_format:"gemini"});
                Ai.setModel("attachment-test",false);
                SidebarChat.attach([root.artifacts + "/attachment.txt",root.artifacts + "/second.txt"]);
                root.check(SidebarChat.attachments.length === 0,"attachment count is limited by the adapter");
                SidebarChat.attach([root.artifacts + "/attachment.txt"]);
            } else if (root.step === 26) {
                root.check(SidebarChat.attachments.length === 1,"supported existing attachment accepted");
                SidebarChat.attachments = []; Ai.setModel("preview",false);
                SidebarChat.draft = "Черновик";
                const input = root.find(chat,"sidebarChatInput"); input.forceActiveFocus(); input.cursorPosition = input.length;
                interaction.keyClick(Qt.Key_Return,Qt.ShiftModifier);
                root.check(SidebarChat.draft.includes("\n"),"Shift Enter adds a line");
                SidebarChat.draft = "Длинный черновик\n".repeat(30);
                SidebarChat.append({role:"assistant",text:"Длинный ответ для проверки прокрутки.\n\n".repeat(30)});
                timeline.followTail = true; timeline.positionViewAtEnd();
            } else if (root.step === 27) {
                root.check(root.find(chat,"sidebarChatInputScroll").height <= 160,"composer stops growing at 160 px");
                if (!timeline.atYEnd) console.log("SCROLL_DIAGNOSTIC " + JSON.stringify({follow:timeline.followTail,y:timeline.contentY,height:timeline.height,content:timeline.contentHeight,origin:timeline.originY,margin:timeline.bottomMargin}));
                root.check(timeline.atYEnd,"timeline follows the response at the bottom");
                timeline.followTail = false; timeline.positionViewAtBeginning();
                root.readingPosition = timeline.contentY;
                SidebarChat.messages[SidebarChat.messages.length-1].text += "Новый фрагмент\n\n".repeat(10);
            } else if (root.step === 28) {
                root.check(Math.abs(timeline.contentY - root.readingPosition) < 1,"new fragments preserve the reading position");
                chat.visible = false;
            } else if (root.step === 29) {
                chat.visible = true;
                root.check(SidebarChat.draft.startsWith("Длинный черновик"),"closing the panel preserves its draft");
            } else {
                console.log(root.failed ? "DRIVER_FAIL" : "DRIVER_PASS"); Qt.quit();
            }
            root.step++;
        }
    }
}
'''


@unittest.skipUnless((pages.QS and pages.CARGO and pages.DBUS) or pages.REQUIRED, "needs qs, cargo and dbus-daemon")
class SidebarChatPagesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if os.environ.get('VELORA_TEST_PREBUILT'):
            pages.SettingsPagesTests.daemon = pages.TOOLS / 'target/debug/velora-connectivityd'
            pages.SettingsPagesTests.fakes = pages.TOOLS / 'target/debug/velora-connectivity-fakes'
        else:
            pages.SettingsPagesTests.setUpClass()
        ARTIFACTS.mkdir(parents=True, exist_ok=True)
        (ARTIFACTS / "attachment.txt").write_text("Synthetic test attachment")

    def test_real_sidebar_rendering(self):
        scales = os.environ.get("VELORA_CHAT_TEST_SCALES", "1,1.5,2").split(",")
        for scale in scales:
            with self.subTest(scale=scale), patch.dict(os.environ, {"QT_SCALE_FACTOR":scale}):
                driver = DRIVER.replace("ARTIFACTS", str(ARTIFACTS)).replace("SCALE", scale)
                case = pages.SettingsPagesTests()
                output = case.run_driver(driver)
                (ARTIFACTS / f"render-{scale}.log").write_text(output)
                self.assertIn("DRIVER_PASS", output, output[-9000:])
                case.assert_clean(output)
