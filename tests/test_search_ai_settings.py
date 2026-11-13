"""Exercise the interactive Search and AI pages in the isolated real QML runtime."""
import os
import unittest
import test_connectivity_pages as pages
from test_ai_connections_pages import KEYRING

ARTIFACTS = pages.PROJECT / "cache/search-ai-settings"
DRIVER = r'''
import QtQuick
import QtTest
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.settings
ShellRoot {
    id: root
    property int step: 0
    property bool failed: false
    property bool capturing: false
    property real savedScroll: 0
    TestCase { id: input; name: "SettingsInteractions"; when: false }
    function check(value, message) { if (!value) { failed = true; console.log("CHECK_FAIL " + message); } }
    function find(item, name) { if (item.objectName === name) return item; for (const child of item.children ?? []) { const found = find(child,name); if (found) return found; } return null; }
    function capturePage(name, after) { capturing = true; capture.grabToImage(result => { result.saveToFile("ARTIFACTS/" + name + ".png"); if (after) after(); capturing = false; }); }
    function click(page, name) {
        const button = find(page, name);
        check(!!button && button.enabled, "button available: " + name);
        if (button) input.mouseClick(button);
    }
    function choose(page, name, value) {
        const row = find(page, name);
        const dropdown = row.dropdown ?? row;
        dropdown.pick({kind:"option",option:dropdown.options.find(option => option.value === value)});
    }
    FloatingWindow {
        implicitWidth: 960; implicitHeight: 850; visible: true
        Rectangle {
            id: capture; width: parent.width; height: parent.height; color: Appearance.colors.colLayer0Base
            SearchConfig { id: search; anchors.fill: parent; pageShown: visible }
            AiConfig { id: ai; anchors.fill: parent; visible: false; pageShown: visible }
        }
    }
    Timer {
        interval: 500; repeat: true; running: true
        onTriggered: {
            if (root.capturing) return;
            if (step === 0) {
                Config.options.language.ui = "ru_RU";
                Config.options.search.lens.enabled = false;
                Config.options.policies.ai = 2;
                Config.options.search.prefix.math = "==";
                root.check(search.tab === "search" && !search.canNavigateBack, "search opens on overview");
            } else if (step === 1) {
                root.capturePage("search-dark-wide", () => {
                    root.click(search,"searchExampleMath");
                });
            } else if (step === 2) {
                root.check(root.find(search,"settingsSearchPreviewInput").text === "==24 * 7", "example uses custom two-character prefix");
                root.check(LauncherSearch.query === "==24 * 7", "preview reaches launcher service");
                root.check(!root.find(search,"searchPrefixes").expanded, "trying search does not expand forms");
                root.capturePage("search-calculation");
            } else if (step === 3) {
                root.click(search,"searchFoldersSummary");
            } else if (step === 4) {
                root.check(search.tab === "files" && search.canNavigateBack, "real click opens folders");
                root.check(LauncherSearch.query === "", "leaving preview cancels query");
                root.capturePage("search-folders", () => {
                    search.navigateBack();
                });
            } else if (step === 5) {
                root.check(search.tab === "search" && !search.canNavigateBack, "Back returns to overview");
                root.check(root.find(search,"searchFoldersSummary").activeFocus, "Back restores navigation focus");
                root.click(search,"searchIndexingSummary");
            } else if (step === 6) {
                root.check(search.tab === "indexing", "indexing details open");
                search.revealItem(root.find(search,"lensEnable"), false);
            } else if (step === 7) {
                root.check(search.tab === "files", "settings search opens folder details");
                search.tab = "search";
            } else if (step === 8) {
                root.click(search,"searchBehaviorSummary");
            } else if (step === 9) {
                root.check(search.tab === "behavior", "behavior has its own details");
                search.revealItem(root.find(search,"searchPrefixes"), false);
                search.navigateBack();
                capture.width = 540;
            } else if (step === 10) {
                root.check(root.find(search,"settingsSearchPreviewInput").width > 200, "input fits narrow width");
                root.capturePage("search-dark-narrow", () => {
                    search.visible = false; ai.visible = true;
                    Ai.addModel("local-settings", {name:"Qwen · local",model:"qwen-fixture",local:true,requires_key:false,endpoint:"http://localhost:11434/v1/chat/completions",api_format:"openai"});
                    Ai.setModel("local-settings",false);
                });
            } else if (step === 11) {
                root.check(ai.tab === "overview" && !Ai.generating && !Assistant.ready && !Assistant.busy, "AI overview keeps models idle");
                root.capturePage("ai-dark-narrow");
            } else if (step === 12) {
                root.click(ai,"aiPreviewChat");
            } else if (step === 13) {
                root.check(ai.tab === "chat", "preview opens chat details");
                root.check(root.find(ai,"aiChatModel").currentValue === "local-settings", "saved chat model displayed");
                root.capturePage("ai-chat-dark-narrow", () => {
                    ai.navigateBack();
                });
            } else if (step === 14) {
                root.click(ai,"aiPreviewAction");
            } else if (step === 15) {
                root.check(ai.tab === "assistant", "preview opens actions");
                root.click(ai,"desktopAssistantEnable");
                root.check(Config.options.assistant.enabled, "enable assistant");
                root.check(ai.effectiveModel === Config.options.assistant.model, "overview reflects effective assistant model");
                root.capturePage("ai-actions-dark-narrow", () => {
                    root.click(ai,"assistantModelDetails");
                });
            } else if (step === 16) {
                root.check(ai.tab === "assistant-model", "model has separate details");
                root.choose(ai,"assistantModelSource","saved");
                root.check(root.find(ai,"assistantModelSource").currentValue === "saved", "source selection works");
                ai.navigateBack();
            } else if (step === 17) {
                root.check(ai.tab === "assistant", "model Back returns to assistant");
                root.click(ai,"desktopAssistantEnable");
                ai.tab = "overview";
            } else if (step === 18) {
                root.click(ai,"aiModelsSummary");
            } else if (step === 19) {
                root.check(ai.tab === "models", "models list opens");
                root.click(ai,"settingsAddAiConnection");
            } else if (step === 20) {
                root.check(ai.tab === "connection", "add opens dedicated editor");
                root.find(ai,"aiConnectionKey").text = "test-unsaved-secret";
                root.capturePage("ai-editor-dark-narrow", () => {
                    ai.navigateBack();
                });
            } else if (step === 21) {
                root.check(ai.tab === "models", "editor Back returns to list");
                root.check(root.find(ai,"aiConnectionKey").text === "", "Back clears unsaved secret");
                ai.revealItem(root.find(ai,"aiConnectionName"), false);
            } else if (step === 22) {
                root.check(ai.tab === "connection", "settings search opens editor and folded field");
                root.check(root.find(ai,"aiConnectionName").height > 0, "hidden name field has layout");
                ai.tab = "overview";
                capture.width = 960;
            } else if (step === 23) {
                root.capturePage("ai-dark-wide", () => {
                    MaterialThemeLoader.applyColors(JSON.stringify({background:"#f7f7fc",on_background:"#20212a",surface_container_low:"#f3f3f8",surface_container:"#eaeaf2",surface_container_high:"#e3e3ed",surface_container_highest:"#dddde8",on_surface:"#20212a",on_surface_variant:"#484957",primary:"#5650a2",on_primary:"#ffffff",primary_container:"#e6e0ff",on_primary_container:"#262044",secondary_container:"#e6e0ff",on_secondary_container:"#262044",outline:"#747482",outline_variant:"#c8c6d4"}));
                });
            } else if (step === 24) {
                root.capturePage("ai-light-wide", () => {
                    capture.width = 540;
                });
            } else if (step === 25) {
                root.capturePage("ai-light-narrow", () => {
                    ai.tab = "chat";
                });
            } else if (step === 26) {
                root.capturePage("ai-chat-light-narrow", () => {
                    capture.width = 960;
                });
            } else if (step === 27) {
                root.capturePage("ai-chat-light-wide", () => {
                    ai.tab = "assistant";
                });
            } else if (step === 28) {
                root.capturePage("ai-actions-light-wide", () => {
                    capture.width = 540;
                });
            } else if (step === 29) {
                root.capturePage("ai-actions-light-narrow", () => {
                    search.visible = true; ai.visible = false;
                });
            } else if (step === 30) {
                root.capturePage("search-light-narrow", () => {
                    capture.width = 960;
                });
            } else if (step === 31) {
                root.capturePage("search-light-wide", () => {
                    root.choose(search,"settingsSearchModes","webSearch");
                });
            } else if (step === 32) {
                root.check(LauncherSearch.query === Config.options.search.prefix.webSearch + "Velora", "mode menu updates real query");
                search.tab = "music";
            } else if (step === 33) {
                root.check(LauncherSearch.query === "", "query cleared after leaving overview");
                search.visible = false; ai.visible = true;
                capture.height = 540; capture.width = 540;
                ai.tab = "overview";
            } else if (step === 34) {
                const pane = root.find(ai,"aiOverviewScroll");
                pane.contentY = Math.max(0,pane.contentHeight-pane.height);
            } else if (step === 35) {
                root.savedScroll = root.find(ai,"aiOverviewScroll").contentY;
                root.check(root.savedScroll > 0,"overview scrolls together with preview");
                root.click(ai,"aiModelsSummary");
            } else if (step === 36) {
                ai.navigateBack();
            } else if (step === 37) {
                root.check(ai.tab === "overview" && Math.abs(root.find(ai,"aiOverviewScroll").contentY-root.savedScroll)<1,"Back preserves overview scroll position");
                root.check(root.find(ai,"aiModelsSummary").activeFocus,"Back restores focus to models row");
                Config.options.assistant.enabled = true;
                Config.options.assistant.provider = "ollama";
                Config.options.assistant.model = "test-download:local";
                ai.tab = "assistant-model";
                root.find(ai,"assistantSettings").installedModels = [];
            } else if (step === 38) {
                root.check(root.find(ai,"assistantDownloadModel").visible && !root.find(ai,"assistantCheckModel").visible,"missing local model offers download");
                root.find(ai,"assistantSettings").installedModels = [{name:Config.options.assistant.model,size:1024}];
            } else if (step === 39) {
                root.check(!root.find(ai,"assistantDownloadModel").visible && root.find(ai,"assistantCheckModel").visible,"installed model offers explicit check");
                Assistant.busy = true;
            } else if (step === 40) {
                root.check(root.find(ai,"assistantStopModel").visible && !root.find(ai,"assistantCheckModel").visible,"busy model offers stop");
                Assistant.busy = false;
                root.find(ai,"assistantSettings").installedModels = [];
                Assistant.problem = "Fixture download failed";
            } else if (step === 41) {
                root.check(root.find(ai,"assistantDownloadModel").mainText === Translation.tr("Retry download"),"failed download offers retry");
                Assistant.problem = "";
                Config.options.assistant.enabled = false;
                root.choose(ai,"aiAccessPolicy",0);
                root.check(Config.options.policies.ai === 0,"AI policy selection persists");
                root.check(!root.find(ai,"desktopAssistantEnable").enabled,"AI off disables assistant enable");
                root.choose(ai,"aiAccessPolicy",2);
            } else {
                root.check(!Ai.generating && !Assistant.ready && !Assistant.busy, "UI interaction never starts models");
                root.check(LauncherSearch.query === "", "query cleared after leaving overview");
                console.log(root.failed ? "DRIVER_FAIL" : "DRIVER_PASS"); Qt.quit();
            }
            step++;
        }
    }
}
'''

class SearchAiSettingsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if os.environ.get("VELORA_TEST_PREBUILT"):
            pages.SettingsPagesTests.daemon = pages.TOOLS / "target/debug/velora-connectivityd"
            pages.SettingsPagesTests.fakes = pages.TOOLS / "target/debug/velora-connectivity-fakes"
        else:
            pages.SettingsPagesTests.setUpClass()
        ARTIFACTS.mkdir(parents=True, exist_ok=True)

    def test_interactive_settings(self):
        case = pages.SettingsPagesTests()
        output = case.run_driver(DRIVER.replace("ARTIFACTS", str(ARTIFACTS)), service_overrides={"KeyringStorage.qml":KEYRING})
        (ARTIFACTS / "render.log").write_text(output)
        self.assertIn("DRIVER_PASS", output, output[-9000:])
        self.assertNotIn("CHECK_FAIL", output)
        case.assert_clean(output)

    def test_dropdown_dismissal(self):
        driver = r'''
import QtQuick
import QtTest
import Quickshell
import qs.modules.common.widgets
ShellRoot {
    id: root
    property bool failed: false
    TestCase { id: input; name: "DropdownDismissal"; when: false }
    function check(value, message) { if (!value) { failed = true; console.log("CHECK_FAIL " + message); } }
    function popupFor(control) {
        if (control.popup) return control.popup;
        for (const child of control.data ?? [])
            if (typeof child.open === "function" && child.opened !== undefined) return child;
        return null;
    }
    function findText(item, text) {
        if (item.text === text) return item;
        for (const child of item.children ?? []) { const found = findText(child,text); if (found) return found; }
        return null;
    }
    function exercise(control, label) {
        const popup = popupFor(control);
        check(!!popup,label + ": popup exists");
        if (!popup) return;
        input.mouseClick(control); input.wait(250);
        check(popup.visible,label + ": first click opens");
        input.mouseClick(control); input.wait(250);
        check(!popup.visible,label + ": second click closes without reopening");
        popup.close(); input.wait(250);
        input.mouseClick(control); input.wait(250);
        input.mouseClick(surface,760,560); input.wait(250);
        check(!popup.visible,label + ": outside click closes");
        input.mouseClick(control); input.wait(250);
        input.keyClick(Qt.Key_Escape); input.wait(250);
        check(!popup.visible,label + ": Escape closes");
        input.mouseClick(control); input.wait(250);
        const option = findText(popup.contentItem,"Second");
        check(!!option,label + ": selectable option is rendered");
        if (option) input.mouseClick(option);
        input.wait(250);
        check(!popup.visible,label + ": selection closes");
        check((control.options !== undefined ? control.currentValue : control.currentIndex) === 1,label + ": selection is saved");
        popup.close(); input.wait(250);
        input.mouseClick(control); input.wait(30);
        input.mouseClick(control); input.wait(250);
        check(!popup.visible,label + ": repeat click during opening closes");
        popup.close(); input.wait(250);
    }
    FloatingWindow {
        implicitWidth: 800; implicitHeight: 600; visible: true
        Item {
            id: surface; anchors.fill: parent
            ChoiceDropdown {
                id: choice; x: 50; y: 40; width: 200
                options: [{displayName:"First",value:0},{displayName:"Second",value:1}]
                currentValue: 0
                onSelected: value => currentValue = value
            }
            StyledComboBox {
                id: combo; x: 450; y: 40; width: 200
                textRole: "name"
                model: [{name:"First"},{name:"Second"}]
            }
            ConfigComboRow {
                id: row; x: 50; y: 300; width: 500
                text: "Settings selection"
                options: choice.options
                currentValue: 0
                onSelected: value => currentValue = value
            }
        }
    }
    Timer {
        interval: 500; running: true
        onTriggered: {
            root.exercise(choice,"ChoiceDropdown");
            root.exercise(combo,"StyledComboBox");
            root.exercise(row.dropdown,"ConfigComboRow");
            // Opening a different menu must dismiss the first, without swallowing the click.
            input.mouseClick(choice); input.wait(250);
            input.mouseClick(combo); input.wait(250);
            root.check(!root.popupFor(choice).visible && combo.popup.visible,"switching menus keeps only the second open");
            combo.popup.close();
            console.log(root.failed ? "DRIVER_FAIL" : "DRIVER_PASS"); Qt.quit();
        }
    }
}
'''
        case = pages.SettingsPagesTests()
        output = case.run_driver(driver)
        (ARTIFACTS / "dropdowns.log").write_text(output)
        self.assertIn("DRIVER_PASS", output, output[-9000:])
        self.assertNotIn("CHECK_FAIL", output)
        case.assert_clean(output)

    def test_index_summary_spacing(self):
        driver = r'''
import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.settings
ShellRoot {
    id: root
    property int step: 0
    property bool capturing: false
    property bool failed: false
    property var cases: [{width:960,download:false},{width:540,download:false},{width:960,download:true},{width:540,download:true}]
    function check(value,message) { if (!value) { failed = true; console.log("CHECK_FAIL " + message); } }
    function find(item,predicate) { if (predicate(item)) return item; for (const child of item.children ?? []) { const found = find(child,predicate); if (found) return found; } return null; }
    FloatingWindow {
        implicitWidth: 960; implicitHeight: 850; visible: true
        Rectangle {
            id: capture; width: 960; height: parent.height; color: Appearance.colors.colLayer1
            SearchConfig { id: page; anchors.fill: parent }
        }
    }
    Timer {
        interval: 300; running: true; repeat: true
        onTriggered: {
            if (root.capturing) return;
            const index = Math.floor(root.step / 2);
            if (index >= root.cases.length) { console.log(root.failed ? "DRIVER_FAIL" : "DRIVER_PASS"); Qt.quit(); return; }
            const item = root.cases[index];
            if (root.step % 2 === 0) {
                capture.width = item.width;
                Lens.ready = true;
                Lens.status = {locked:false,models:true,files:17624,pending:0,failed:0,folder_stats:{total:17624,pending:0,failed:0},idle:true,config:{roots:["/home/example/Documents"],excludes:[]}};
                Lens.setupInfo = item.download ? {installed:true,running:true,stage:"models",progress:{done:1342177280,total:2684354560,unit:"bytes"}} : {installed:true,running:false,stage:"done"};
                root.step++;
                return;
            }
            const group = root.find(page,item => item.objectName === "searchIndexingGroup");
            const nav = root.find(group,item => item.objectName === "searchIndexingSummary");
            const progress = root.find(group,item => item.objectName === "searchIndexSummaryProgress");
            const count = root.find(group,item => item.objectName === "searchIndexSummaryCount");
            const title = root.find(nav.contentItem,item => item.text === nav.title);
            root.check(progress.visible,"progress is shown");
            root.check(Math.abs(title.mapToItem(group,0,0).x-count.mapToItem(group,0,0).x)<1,"progress aligns with Indexing text");
            root.check(group.width-progress.x-progress.width >= 12,"progress has a right inset");
            root.check(group.height-progress.y-progress.height >= 12,"progress has bottom padding");
            root.check(progress.y >= nav.y+nav.height,"progress does not overlap the navigation row");
            root.capturing = true;
            capture.grabToImage(result => {
                root.check(result.saveToFile("ARTIFACTS/search-index-summary-"+(item.download ? "download" : "ready")+"-"+item.width+".png"),"snapshot saved");
                root.capturing = false; root.step++;
            });
        }
    }
}
'''.replace("ARTIFACTS",str(ARTIFACTS))
        case = pages.SettingsPagesTests()
        output = case.run_driver(driver,service_overrides={"Lens.qml":pages.LENS_SETTINGS_FIXTURE})
        (ARTIFACTS / "index-summary.log").write_text(output)
        self.assertIn("DRIVER_PASS",output,output[-6000:])
        self.assertNotIn("CHECK_FAIL",output)
        case.assert_clean(output)

    def test_details_visual_matrix(self):
        driver = r'''
import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.settings
ShellRoot {
    id: root
    property int cursor: -1
    property bool preparing: false
    property bool capturing: false
    property var cases: []
    function find(item,name) { if (item.objectName === name) return item; for (const child of item.children ?? []) { const result = find(child,name); if (result) return result; } return null; }
    FloatingWindow {
        implicitWidth: 960; implicitHeight: 850; visible: true
        Rectangle {
            id: capture; width: 960; height: 850; color: Appearance.colors.colLayer0Base
            AiConfig { id: ai; anchors.fill: parent; pageShown: visible }
            SearchConfig { id: search; anchors.fill: parent; visible: false; pageShown: visible }
        }
    }
    Timer {
        interval: 250; running: true; repeat: true
        onTriggered: {
            if (root.capturing) return;
            if (root.cursor < 0) {
                Config.options.language.ui = "ru_RU";
                Config.options.policies.ai = 1;
                Config.options.assistant.enabled = true;
                Lens.ready = true;
                Lens.setupInfo = {installed:true,models:true,running:false,stage:"done"};
                Lens.status = {locked:false,models:true,files:1093,pending:330,failed:20,applications:93,folder_stats:{total:1000,pending:300,failed:20},idle:true,on_battery:false,config:{roots:["/home/example/Документы/Проекты/Исследование длинных имён и путей к файлам","/home/example/Изображения"],excludes:["/home/example/Документы/Личное"],activity:true,media:true,paused:false}};
                AiConnections.saveConnection("openai","Рабочая модель","fixture-model","","fixture-secret","");
                const routes = [{page:"ai",tab:"models"},{page:"ai",tab:"connection"},{page:"ai",tab:"assistant-model"},{page:"search",tab:"files"},{page:"search",tab:"indexing"},{page:"search",tab:"behavior"},{page:"search",tab:"music"}];
                const scenarios = [];
                for (const theme of ["dark","light"]) for (const width of [960,540]) for (const route of routes) scenarios.push(Object.assign({theme,width},route));
                root.cases = scenarios;
                root.cursor = 0;
                return;
            }
            if (root.cursor >= root.cases.length) { console.log("DRIVER_PASS"); Qt.quit(); return; }
            const item = root.cases[root.cursor];
            if (!root.preparing) {
                capture.width = item.width;
                ai.visible = item.page === "ai"; search.visible = !ai.visible;
                if (ai.visible) ai.tab = item.tab; else search.tab = item.tab;
                if (item.theme === "light") MaterialThemeLoader.applyColors(JSON.stringify({background:"#f7f7fc",on_background:"#20212a",surface_container_low:"#f3f3f8",surface_container:"#eaeaf2",surface_container_high:"#e3e3ed",surface_container_highest:"#dddde8",on_surface:"#20212a",on_surface_variant:"#484957",primary:"#5650a2",on_primary:"#ffffff",primary_container:"#e6e0ff",on_primary_container:"#262044",secondary_container:"#e6e0ff",on_secondary_container:"#262044",outline:"#747482",outline_variant:"#c8c6d4"}));
                root.preparing = true;
                return;
            }
            root.capturing = true;
            capture.grabToImage(result => {
                const path = "ARTIFACTS/details-"+item.page+"-"+item.tab+"-"+item.theme+"-"+item.width+".png";
                if (!result.saveToFile(path)) { console.log("DRIVER_FAIL screenshot"); Qt.quit(); return; }
                root.cursor++; root.preparing = false; root.capturing = false;
            });
        }
    }
}
'''
        case = pages.SettingsPagesTests()
        output = case.run_driver(driver.replace("ARTIFACTS", str(ARTIFACTS)), service_overrides={"KeyringStorage.qml": KEYRING, "Lens.qml": pages.LENS_SETTINGS_FIXTURE})
        (ARTIFACTS / "details-render.log").write_text(output)
        self.assertIn("DRIVER_PASS", output, output[-9000:])
        case.assert_clean(output)
