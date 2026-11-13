"""Real AI settings and model catalogue; credentials use a private in-memory keyring."""
import os
from pathlib import Path
import unittest
from unittest.mock import patch
import test_connectivity_pages as pages

ARTIFACTS = pages.PROJECT / "cache/ai-settings"
KEYRING = '''pragma Singleton
import QtQuick
import Quickshell
Singleton {
    property bool loaded: true
    property bool saving: false
    property bool fetching: false
    property bool failNextSave: false
    property var keyringData: ({apiKeys:{}})
    signal saveFinished(bool ok)
    function fetchKeyringData() {}
    function setNestedField(path, value) {
        saving = true;
        if (!failNextSave) keyringData = {apiKeys:Object.assign({}, keyringData.apiKeys, {[path[1]]:value})};
        Qt.callLater(() => { saving = false; const success = !failNextSave; failNextSave = false; saveFinished(success); });
    }
}
'''

DRIVER = r'''
import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.settings
import qs.modules.ii.sidebarLeft.aiChat
ShellRoot {
    id: root
    property int step: 0
    property bool failed: false
    property bool capturing: false
    property string firstId: ""
    function check(value, message) { if (!value) { failed = true; console.log("CHECK_FAIL " + message); } }
    function find(item, name) { if (item.objectName === name) return item; for (const child of item.children ?? []) { const found = find(child,name); if (found) return found; } return null; }
    function snapshot(name) { capturing = true; capture.grabToImage(result => { result.saveToFile("ARTIFACTS/"+name+".png"); capturing = false; }); }
    FloatingWindow {
        implicitWidth: 960; implicitHeight: 960; visible: true
        Rectangle {
            id: capture; anchors.fill: parent; color: Appearance.colors.colLayer0Base
            AiConfig { id: page; anchors.fill: parent }
            ModelPicker { id: picker; anchors.centerIn: parent; width: 400; height: 800; visible: false }
        }
    }
    Timer {
        interval: 700; running: true; repeat: true
        onTriggered: {
            if (root.capturing) return;
            if (step === 0) {
                Config.options.language.ui = "ru_RU";
                Config.options.policies.ai = 2;
                Config.options.ai.extraModels = [];
                root.find(page,"settingsAddAiConnection").clicked();
            } else if (step === 1) {
                root.check(root.find(page,"aiConnectionEditor").visible,"add opens the editor");
                root.find(page,"aiConnectionModel").value = "fixture-model";
                root.find(page,"aiConnectionName").value = "Мой OpenAI";
                root.find(page,"aiConnectionKey").text = "private-fixture-token";
                root.find(page,"saveAiConnection").clicked();
            } else if (step === 2) {
                root.check(AiConnections.records.length === 1,"connection saved after key storage");
                root.firstId = AiConnections.records[0].connectionId;
                root.check(!!Ai.models[root.firstId],"model catalogue refreshes without restart");
                root.check(!JSON.stringify(Config.options.ai.extraModels).includes("private-fixture-token"),"key does not enter the config");
                root.check(root.find(page,"aiConnectionKey").text === "","secret field cleared");
                root.check(!Ai.modelAllowed(Ai.models[root.firstId]),"local-only policy still blocks cloud models");
                root.check(!Assistant.ready && !Ai.generating,"saving does not start a model");
                AiConnections.saveConnection("groq","Мой Groq","fixture-model","","second-fixture-token","");
            } else if (step === 3) {
                root.check(AiConnections.records.length === 2,"same model on different providers does not collide");
                root.check(AiConnections.records[0].connectionId !== AiConnections.records[1].connectionId,"connection IDs differ");
                root.check(!AiConnections.saveConnection("custom","","x","https://example.com/$(touch-test)","fake", ""),"unsafe URL rejected");
                KeyringStorage.failNextSave = true;
                AiConnections.saveConnection("deepseek","","fixture","","failed-key","");
            } else if (step === 4) {
                root.check(AiConnections.records.length === 2,"keyring failure leaves config unchanged");
                Config.options.policies.ai = 1;
                root.find(page,"aiConnectionMenu").pick({kind:"option",option:{value:"chat"}});
                root.check(Ai.currentModelId === root.firstId,"overflow assigns a connection to chat");
                root.find(page,"aiConnectionMenu").pick({kind:"option",option:{value:"actions"}});
                root.check(Config.options.assistant.keyId === "openai","assistant uses the provider key");
                root.check(Assistant.profile.key === "private-fixture-token","assistant resolves the same saved key");
                root.find(page,"settingsAddAiConnection").clicked();
                root.find(page,"aiConnectionModel").value = "Идентификатор из каталога";
                root.snapshot("connections-dark");
            } else if (step === 5) {
                MaterialThemeLoader.applyColors(JSON.stringify({background:"#f7f7fc",on_background:"#20212a",surface_container_low:"#f3f3f8",surface_container:"#eaeaf2",surface_container_high:"#e3e3ed",surface_container_highest:"#dddde8",on_surface:"#20212a",on_surface_variant:"#484957",primary:"#5650a2",on_primary:"#ffffff",secondary_container:"#e6e0ff",on_secondary_container:"#262044",outline:"#747482",outline_variant:"#c8c6d4"}));
                page.revealItem(root.find(page,"aiConnectionEditor"), false);
            } else if (step === 6) root.snapshot("connection-editor-light");
            else if (step === 7) {
                page.tab = "models";
                root.find(page,"aiConnectionMenu").pick({kind:"option",option:{value:"remove"}});
                root.check(AiConnections.records.length === 2,"removal waits for confirmation");
                root.find(page,"confirmRemoveAiConnection").clicked();
                root.check(!Ai.models[root.firstId],"removing a connection updates the catalogue");
                root.check(KeyringStorage.keyringData.apiKeys.openai === "private-fixture-token","removing a model preserves shared credentials");
                page.visible = false; picker.visible = true;
                Ai.addModel("local-fixture",{name:"Qwen 3.5",model:"qwen3.5",local:true,requires_key:false,endpoint:"http://localhost:11434/v1/chat/completions"});
                Ai.setModel("local-fixture",false);
            } else if (step === 8) {
                root.check(root.find(picker,"addAiConnection").visible,"model picker has Add");
                root.check(root.find(picker,"unloadLocalModel").visible,"local model offers memory release");
                root.snapshot("model-picker-light");
            } else { console.log(root.failed ? "DRIVER_FAIL" : "DRIVER_PASS"); Qt.quit(); }
            step++;
        }
    }
}
'''

class AiConnectionsPagesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if os.environ.get("VELORA_TEST_PREBUILT"):
            pages.SettingsPagesTests.daemon = pages.TOOLS / "target/debug/velora-connectivityd"
            pages.SettingsPagesTests.fakes = pages.TOOLS / "target/debug/velora-connectivity-fakes"
        else:
            pages.SettingsPagesTests.setUpClass()
        ARTIFACTS.mkdir(parents=True, exist_ok=True)

    def test_provider_editor_and_catalogue(self):
        case = pages.SettingsPagesTests()
        output = case.run_driver(DRIVER.replace("ARTIFACTS",str(ARTIFACTS)),service_overrides={"KeyringStorage.qml":KEYRING})
        (ARTIFACTS / "render.log").write_text(output)
        self.assertIn("DRIVER_PASS",output,output[-9000:])
        case.assert_clean(output)

    def test_breadcrumb_animation_and_hover_bounds(self):
        driver = r'''
import QtQuick
import QtTest
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
ShellRoot {
    id: root
    property bool failed: false
    property int clicks: 0
    TestCase { id: input; name: "BreadcrumbHover"; when: false }
    function check(value,message) { if (!value) { failed = true; console.log("CHECK_FAIL " + message); } }
    function find(item,name) { if (item.objectName === name) return item; for (const child of item.children ?? []) { const found = find(child,name); if (found) return found; } return null; }
    FloatingWindow {
        implicitWidth: 800; implicitHeight: 100; visible: true
        Rectangle {
            id: surface; anchors.fill: parent; color: Appearance.colors.colLayer1
            SettingsBreadcrumbs {
                id: path; x: 16; y: 20; width: surface.width - 32
                entries: [{title:"Поиск",key:"search"}]
                onActivated: entry => { root.clicks++; path.entries = [{title:"Поиск",key:"search"}]; }
            }
        }
    }
    Timer {
        interval: 500; running: true
        onTriggered: {
            path.entries = [{title:"Поиск",key:"search"},{title:"Индексация",key:"indexing"}];
            if (Appearance.animationSpeed > 0) root.check(path.opacity < 1,"new path animates in");
            input.wait(400);
            root.check(path.opacity === 1,"path finishes its entrance");
            const last = root.find(path,"settingsBreadcrumb-1");
            root.check(last.width <= last.contentItem.implicitWidth + last.leftPadding + last.rightPadding + 1,"hover target fits the title");
            input.mouseMove(last,last.width / 2,last.height / 2); input.wait(50);
            root.check(last.hovered,"title responds to hover");
            surface.grabToImage(result => result.saveToFile("ARTIFACTS/settings-indexing-hover.png"));
            input.wait(100);
            input.mouseMove(surface,760,38); input.wait(50);
            root.check(!last.hovered,"empty header space does not highlight title");
            input.mouseClick(surface,760,38);
            root.check(root.clicks === 0,"empty header space does not activate navigation");
            input.mouseClick(root.find(path,"settingsBreadcrumb-0"));
            if (Appearance.animationSpeed > 0) root.check(path.opacity < 1,"return path animates too");
            input.wait(400);
            root.check(root.clicks === 1 && path.entries.length === 1 && path.opacity === 1,"parent click returns and animation settles");
            path.entries = [{title:"ИИ"},{title:"Модели и подключения"},{title:"Добавить подключение"}];
            path.entries = [{title:"Поиск"},{title:"Индексация"}];
            input.wait(400);
            root.check(path.opacity === 1 && root.find(path,"settingsBreadcrumb-1").contentItem.text === "Индексация","rapid navigation keeps the latest path");
            console.log(root.failed ? "DRIVER_FAIL" : "DRIVER_PASS"); Qt.quit();
        }
    }
}
'''.replace("ARTIFACTS",str(ARTIFACTS))
        case = pages.SettingsPagesTests()
        output = case.run_driver(driver)
        (ARTIFACTS / "breadcrumbs.log").write_text(output)
        self.assertIn("DRIVER_PASS",output,output[-6000:])
        self.assertNotIn("CHECK_FAIL",output)
        case.assert_clean(output)

    def test_back_when_search_is_the_initial_page(self):
        probe = r'''
    property bool probeFailed: false
    TestCase { id: probeInput; name: "InitialSearchBack"; when: false }
    function probeCheck(value,message) { if (!value) { probeFailed = true; console.log("CHECK_FAIL " + message); } }
    function probeFind(item,name) { if (item.objectName === name) return item; for (const child of item.children ?? []) { const found = probeFind(child,name); if (found) return found; } return null; }
    Timer {
        interval: 1000; running: true
        onTriggered: {
            const page = root.pageItemAt(root.pageIndex("search"));
            const back = root.probeFind(sidebar.parent,"settingsBackButton");
            root.probeCheck(root.historyIndex === 0 && page?.tab === "search","starts on Search without outer history");
            for (const row of ["searchFoldersSummary","searchIndexingSummary","searchBehaviorSummary","searchMoreSummary"]) {
                probeInput.mouseClick(root.probeFind(page,row)); probeInput.wait(200);
                root.probeCheck(back.enabled,"Back enabled after opening " + row);
                root.probeCheck(root.breadcrumbs.length === 2,"path follows initial page's details");
                probeInput.mouseClick(back); probeInput.wait(200);
                root.probeCheck(page.tab === "search" && root.currentPageData.key === "search","Back returns from " + row);
                page.tab = "search";
            }
            root.openPage("storage"); probeInput.wait(300);
            root.history = [root.currentPage]; root.historyIndex = 0;
            root.probeCheck(back.enabled,"direct subpage has a parent to return to");
            probeInput.mouseClick(back); probeInput.wait(200);
            root.probeCheck(root.currentPageData.key === "general" && !back.enabled,"return to parent does not create a Back loop");
            root.goForward();
            root.probeCheck(root.currentPageData.key === "storage","Forward can reopen the direct subpage");
            console.log(root.probeFailed ? "DRIVER_FAIL" : "DRIVER_PASS"); Qt.quit();
        }
    }
'''
        driver = (pages.SHELL / "settings.qml").read_text().replace("import QtQuick\n","import QtQuick\nimport QtTest\n",1).replace("    id: root\n","    id: root\n" + probe,1)
        driver = driver.replace('Math.max(0, root.pageIndex(pageStateFile.text().trim()))','root.pageIndex("search")',1)
        case = pages.SettingsPagesTests()
        output = case.run_driver(driver,settings_page="search",service_overrides={"KeyringStorage.qml":KEYRING})
        (ARTIFACTS / "initial-search-back.log").write_text(output)
        self.assertIn("DRIVER_PASS",output,output[-6000:])
        self.assertNotIn("CHECK_FAIL",output)

    def test_settings_ai_deep_link_and_separate_search_page(self):
        probe = r'''
    property int probeStage: 0
    property bool probeFailed: false
    TestCase { id: probeInput; name: "SettingsBreadcrumbNavigation"; when: false }
    function probeCheck(value, message) { if (!value) { root.probeFailed = true; console.log("DRIVER_FAIL " + message); } }
    function probeFind(item, name) { if (item.objectName === name) return item; for (const child of item.children ?? []) { const found = probeFind(child,name); if (found) return found; } return null; }
    function probeCrumb(index) {
        probeInput.wait(50); // Let the previous path's Repeater delegates and layout settle.
        const button = root.probeFind(sidebar.parent,"settingsBreadcrumb-" + index);
        root.probeCheck(!!button && button.width > 0,"breadcrumb is visible and laid out");
        if (button) probeInput.mouseClick(button);
    }
    function probeBack() {
        const button = root.probeFind(sidebar.parent,"settingsBackButton");
        root.probeCheck(!!button && button.enabled,"Back button is enabled for the current level");
        if (button) probeInput.mouseClick(button);
    }
    Timer {
        interval: 1000; repeat: true; running: true
        onTriggered: {
            if (root.probeStage === 0) {
                const page = root.pageItemAt(root.pageIndex("ai"));
                if (!page) return;
                const editor = root.probeFind(page,"aiConnectionEditor");
                if (root.currentPageData.key !== "ai" || (!editor?.visible || page.tab !== "connection") || root.pageIndex("ai") === root.pageIndex("search")) {
                    console.log("DRIVER_FAIL AI deep link"); Qt.quit(); return;
                }
                root.probeCheck(root.breadcrumbs.length === 3 && root.breadcrumbs[1].sectionKey === "models", "direct editor has full ancestor path");
                root.probeBack();
                if (page.tab !== "overview" || root.currentPageData.key !== "ai") {
                    console.log("DRIVER_FAIL Back left AI instead of editor"); Qt.quit(); return;
                }
                Config.options.language.ui = "ru_RU";
                root.openPage("ai","aiConnectionEditor");
                root.probeStage = 1;
            } else if (root.probeStage === 1) {
                root.width = 760;
                sidebar.expandOverride = false;
                const page = root.pageItemAt(root.pageIndex("ai"));
                root.probeFind(page,"aiConnectionKey").text = "unsaved-breadcrumb-secret";
                root.probeStage = 2;
            } else if (root.probeStage === 2) {
                sidebar.parent.grabToImage(result => {
                    result.saveToFile("ARTIFACTS/settings-ai-navigation.png");
                    root.probeCrumb(1);
                    const page = root.pageItemAt(root.pageIndex("ai"));
                    root.probeCheck(page.tab === "models", "breadcrumb opens canonical model list after settings search");
                    root.probeCheck(root.probeFind(page,"aiConnectionKey").text === "", "breadcrumb clears unsaved key");
                    root.probeCrumb(0);
                    root.probeCheck(page.tab === "overview" && !page.canNavigateBack, "root breadcrumb resets inner history");
                    root.openPage("search");
                    root.probeStage = 3;
                });
            } else if (root.probeStage === 3) {
                const page = root.pageItemAt(root.pageIndex("search"));
                if (!page) return;
                root.probeFind(page,"searchBehaviorSummary").clicked();
                root.probeCheck(root.breadcrumbs.length === 2 && root.breadcrumbs[1].sectionKey === "behavior", "search details appear in title");
                root.probeBack();
                const detailsBack = page.tab === "search" && root.currentPageData.key === "search";
                root.probeBack();
                root.probeCheck(!root.probeFind(page,"aiConnectionEditor") && detailsBack && root.currentPageData.key === "ai", "nested Back navigation");
                root.openPage("storage");
                root.probeStage = 4;
            } else if (root.probeStage === 4) {
                root.probeCheck(root.breadcrumbs.length === 2 && root.pages[root.breadcrumbs[0].pageIndex].key === "general", "registered subpage has General ancestor");
                root.probeCrumb(0);
                root.probeCheck(root.currentPageData.key === "general", "parent breadcrumb opens General");
                root.openPage("bluetooth-options");
                root.probeStage = 5;
            } else if (root.probeStage === 5) {
                root.probeCheck(root.breadcrumbs.length === 2 && root.pages[root.breadcrumbs[0].pageIndex].key === "bluetooth", "Bluetooth options have parent path");
                root.probeCrumb(0);
                root.probeCheck(root.currentPageData.key === "bluetooth", "parent breadcrumb opens Bluetooth");
                root.openPage("bar");
                root.probeStage = 6;
            } else if (root.probeStage === 6) {
                const page = root.pageItemAt(root.pageIndex("bar"));
                if (!page) return;
                const item = page.layout.zones.start[0] ?? page.layout.zones.center[0] ?? page.layout.zones.end[0];
                page.selectedUid = item.uid;
                root.probeStage = 7;
            } else if (root.probeStage === 7) {
                const page = root.pageItemAt(root.pageIndex("bar"));
                root.probeCheck(root.breadcrumbs.length === 3, "bar widget appears in navigation path");
                root.probeBack();
                root.probeCheck(page.selectedUid === "" && page.tab === "widgets", "widget parent clears selection");
                page.tab = "look";
                root.probeStage = 8;
            } else if (root.probeStage === 8) {
                root.probeCheck(root.breadcrumbs[1].sectionKey === "look", "bar path follows selected area");
                root.probeBack();
                root.probeCheck(root.pageItemAt(root.pageIndex("bar")).tab === "widgets", "bar root breadcrumb returns to widgets");
                root.openPage("sidebars");
                root.probeStage = 9;
            } else if (root.probeStage === 9) {
                const page = root.pageItemAt(root.pageIndex("sidebars"));
                if (!page) return;
                page.select(page.everyPart[0].part.uid);
                root.probeStage = 10;
            } else {
                const page = root.pageItemAt(root.pageIndex("sidebars"));
                root.probeCheck(root.breadcrumbs.length === 3 && root.breadcrumbs[2].title.length > 0, "sidebar part has named path");
                root.probeBack();
                root.probeCheck(page.selectedUid === "", "sidebar parent clears selected part");
                console.log(root.probeFailed ? "DRIVER_FAIL breadcrumbs" : "DRIVER_PASS");
                Qt.quit();
            }
        }
    }
'''.replace("ARTIFACTS",str(ARTIFACTS))
        driver = (pages.SHELL / "settings.qml").read_text().replace("import QtQuick\n", "import QtQuick\nimport QtTest\n", 1).replace("    id: root\n", "    id: root\n" + probe, 1)
        case = pages.SettingsPagesTests()
        with patch.dict(os.environ,{"QS_AI_ADD_CONNECTION":"1"}):
            output = case.run_driver(driver,settings_page="ai",service_overrides={"KeyringStorage.qml":KEYRING})
        (ARTIFACTS / "navigation.log").write_text(output)
        self.assertIn("DRIVER_PASS",output,output[-6000:])
        self.assertNotIn("DRIVER_FAIL",output)
