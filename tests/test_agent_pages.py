"""Real assistant widgets in a private shell session, without accessing the desktop."""
import os
from pathlib import Path
import unittest
from unittest.mock import patch
import test_connectivity_pages as pages

class AgentPagesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if os.environ.get('VELORA_TEST_PREBUILT'):
            pages.SettingsPagesTests.daemon=pages.TOOLS/'target/debug/velora-connectivityd'
            pages.SettingsPagesTests.fakes=pages.TOOLS/'target/debug/velora-connectivity-fakes'
        else:
            pages.SettingsPagesTests.setUpClass()
    def test_settings_launchers_and_chat(self):
        driver='''
import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.settings
import qs.modules.ii.overview
import qs.modules.waffle.startMenu
import qs.modules.waffle.startMenu.searchPage as Waffle
import qs.modules.ii.sidebarLeft
ShellRoot {
    id: root
    property int phase: 0
    property bool failed: false
    property int firstCalls: 0
    property int secondCalls: 0
    property var first: null
    property var second: null
    property var reusedRow: null
    function check(condition, label) { if (!condition) { failed = true; console.log("CHECK_FAIL " + label); } }
    function findItem(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children ?? []) {
            const found = findItem(child, name);
            if (found) return found;
        }
        return null;
    }
    Component { id: result; LauncherSearchResult {} }
    StartMenuContext { id: menuContext }
    FloatingWindow {
        implicitWidth: 1000; implicitHeight: 900
        Loader { id: settings; width: 900; source: "modules/settings/SearchConfig.qml" }
        Loader { id: panel; width: 600; source: "modules/common/widgets/AssistantPanel.qml" }
        Loader { id: classic; width: 700; source: "modules/ii/overview/SearchWidget.qml" }
        Loader { id: waffle; width: 900; sourceComponent: Waffle.SearchResults { context: menuContext } }
        Loader { id: chat; width: 700; source: "modules/ii/sidebarLeft/AiChat.qml" }
    }
    Timer {
        interval: 2000; running: true
        onTriggered: {
            Config.options.assistant.enabled = true;
            Assistant.panelOpen = false;
            if (![settings,panel,classic,waffle,chat].every(l=>l.status===Loader.Ready) || Assistant.busy || Assistant.ready) {
                console.log("DRIVER_FAIL load or eager start"); Qt.quit(); return;
            }
            root.first = result.createObject(root, {id:"a",name:"Same name",type:"File",keepOpen:true,execute:() => { root.firstCalls++; }});
            root.second = result.createObject(root, {id:"b",name:"Same name",type:"File",keepOpen:true,execute:() => { root.secondCalls++; }});
            LauncherSearch.results = [];
            classic.item.setSearchingText("selection fixture one");
            LauncherSearch.results = [root.first, root.second];
            selectionChecks.start();
        }
    }
    Timer {
        id: selectionChecks
        interval: 120; repeat: true
        onTriggered: {
            const classicList = root.findItem(classic.item,"launcherResults");
            const waffleList = root.findItem(waffle.item,"launcherResults");
            const input = root.findItem(classic.item,"launcherSearchInput");
            if (root.phase === 0) {
                root.check(classicList.currentIndex === 0 && classic.item.selectedResultKey === "a", "classic default selected");
                root.check(menuContext.currentIndex === 0 && waffle.item.selectedResultKey === "a", "waffle default selected");
                LauncherSearch.results = [root.second, root.first];
            } else if (root.phase === 1) {
                root.check(classicList.currentIndex === 1 && classic.item.selectedResultKey === "a", "classic automatic default pinned during rerank");
                root.check(menuContext.currentIndex === 1 && waffle.item.selectedResultKey === "a", "waffle automatic default pinned during rerank");
                root.check(!!input,"real launcher input available");
                if (input) input.accepted();
                root.check(root.firstCalls === 1 && root.secondCalls === 0,"Enter activates selected index, not first ranked row");
                classicList.currentIndex = 0; waffle.item.forceCurrentIndex(0);
                root.reusedRow = waffleList.model[0];
                LauncherSearch.results = [root.first, root.second];
            } else if (root.phase === 2) {
                root.check(classicList.currentIndex === 1 && classic.item.selectedResultKey === "b", "classic explicit selection preserved");
                root.check(menuContext.currentIndex === 1 && waffle.item.selectedResultKey === "b" && waffleList.model[1] === root.reusedRow, "waffle explicit selection and row retained");
                if (input) input.accepted();
                root.check(root.firstCalls === 1 && root.secondCalls === 1,"Enter follows explicit navigation");
                LauncherSearch.results = [root.first];
            } else if (root.phase === 3) {
                root.check(classicList.currentIndex === -1 && menuContext.currentIndex === -1,"disappeared result leaves no replacement selected");
                if (input) input.accepted();
                root.check(root.firstCalls === 1 && root.secondCalls === 1,"Enter cannot activate a replacement");
                classic.item.setSearchingText("selection fixture two");
                LauncherSearch.results = [root.first];
            } else {
                root.check(classicList.currentIndex === 0 && classic.item.selectedResultKey === "a", "classic new query resets selection");
                root.check(menuContext.currentIndex === 0 && waffle.item.selectedResultKey === "a", "waffle new query resets selection");
                console.log(root.failed ? "DRIVER_FAIL selection interaction" : "DRIVER_PASS"); Qt.quit();
            }
            root.phase++;
        }
    }
}
'''
        case=pages.SettingsPagesTests()
        with patch.object(pages,'SHELL',Path(os.environ.get('VELORA_QML_SOURCE',pages.SHELL))):
            output=case.run_driver(driver)
        self.assertIn('DRIVER_PASS',output,output[-7000:])
        case.assert_clean(output)

    def test_legacy_consent_and_shared_command_handoff(self):
        driver = '''
import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.ii.sidebarLeft
ShellRoot {
    id: root
    property int phase: 0
    property bool failed: false
    function check(condition, label) { if (!condition) { failed = true; console.log("CHECK_FAIL " + label); } }
    function consent() { return Ai.messageIDs.map(id => Ai.messageByID[id]).find(m => m?.functionPending && m.functionCall?.name === "remote_context"); }
    FloatingWindow { implicitWidth: 500; implicitHeight: 700; AiChat { anchors.fill: parent } }
    Timer {
        interval: 2000; running: true
        onTriggered: {
            Config.options.policies.ai = 1;
            Config.options.assistant.enabled = false;
            Ai.addModel("consent-fixture", {name:"Consent fixture",model:"fixture",local:false,requires_key:false,endpoint:"https://invalid.test/v1/chat/completions",api_format:"openai"});
            Ai.setModel("consent-fixture",false);
            SidebarChat.newConversation();
            SidebarChat.draft = "private context";
            root.check(SidebarChat.send(),"remote question accepted");
            SidebarChat.syncAi();
            root.check(!!root.consent() && !Ai.nativeGenerating,"remote context waits before any request");
            root.check(SidebarChat.active,"confirmation keeps conversation active");
            root.check(Ai.contextMessages().length === 1,"consent row excluded from provider context");
            root.check(SidebarChat.contextEntries().length === 1,"consent row excluded from saved-context restoration");
            interactions.start();
        }
    }
    Timer {
        id: interactions
        interval: 150; repeat: true
        onTriggered: {
            if (root.phase === 0) {
                const approval = root.consent();
                if (approval) Ai.rejectCommand(approval);
                SidebarChat.syncAi();
                root.check(!SidebarChat.active && !Ai.nativeGenerating,"denial finishes without a network request");
                root.check(SidebarChat.messages.some(m => m.text.includes("cancelled")),"denial text synchronized into saved conversation");
                SidebarChat.draft = "second private request";
                SidebarChat.send(); SidebarChat.syncAi();
            } else if (root.phase === 1) {
                const approval = root.consent();
                root.check(!!approval,"second request has fresh consent");
                Ai.temperature = Ai.temperature === 0.5 ? 0.6 : 0.5;
                if (approval) Ai.approveCommand(approval);
                SidebarChat.syncAi();
                root.check(!Ai.nativeGenerating && !root.consent(),"changed context cannot reuse earlier consent");
                root.check(!SidebarChat.active,"stale consent finishes visibly");
                SidebarChat.draft = "third private request";
                SidebarChat.send(); SidebarChat.syncAi();
            } else if (root.phase === 2) {
                const approval = root.consent();
                root.check(!!approval,"policy test has pending remote consent");
                Config.options.policies.ai = 2;
                SidebarChat.syncAi();
                root.check(!approval?.functionPending && !root.consent(),"local-only policy revokes remote consent");
                root.check(!SidebarChat.active && !Ai.nativeGenerating,"policy revocation finishes without a request");
                if (approval) Ai.approveCommand(approval);
                root.check(!Ai.nativeGenerating,"revoked remote approval cannot restart generation");
                Config.options.policies.ai = 1;
                SidebarChat.draft = "fourth private request";
                SidebarChat.send(); SidebarChat.syncAi();
            } else if (root.phase === 3) {
                const approval = root.consent();
                root.check(!!approval,"lock test has pending remote consent");
                GlobalStates.screenLocked = true;
                root.check(!approval?.functionPending && !SidebarChat.active,"screen lock invalidates approval and ends the chat task");
                if (approval) Ai.approveCommand(approval);
                root.check(!Ai.nativeGenerating && !Assistant.preparingSubmission,"stale approval on locked screen cannot start a request");
                GlobalStates.screenLocked = false;
            } else if (root.phase === 4) {
                Ai.addMessage("Proposed command", "assistant");
                const source = Ai.messageByID[Ai.messageIDs[Ai.messageIDs.length - 1]];
                source.functionCall = {name:"run_shell_command",args:{command:"pwd"}};
                source.functionName = "run_shell_command";
                Ai.handleFunctionCall("run_shell_command",{command:"pwd"},source);
                SidebarChat.active = true; SidebarChat.syncAi();
                Ai.approveCommand(source);
                root.check(Assistant.preparingSubmission,"native chat hands off to durable agent preparation");
                root.check(!!SidebarChat.currentReply?.submissionId,"shared task has stable identity");
                root.check(SidebarChat.mode === "chat","command handoff preserves ordinary chat mode");
                SidebarChat.stop();
            } else {
                root.check(!Assistant.preparingSubmission && !Assistant.busy && !Assistant.ready,"cancel before storage acknowledgement never starts the agent");
                console.log(root.failed ? "DRIVER_FAIL consent integration" : "DRIVER_PASS"); Qt.quit();
            }
            root.phase++;
        }
    }
}
'''
        case=pages.SettingsPagesTests()
        with patch.object(pages,'SHELL',Path(os.environ.get('VELORA_QML_SOURCE',pages.SHELL))):
            output=case.run_driver(driver)
        self.assertIn('DRIVER_PASS',output,output[-7000:])
        case.assert_clean(output)

    def test_prepared_file_diff_is_visible_and_scrollable(self):
        driver = '''
import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarLeft.aiChat
ShellRoot {
    id: root
    property int phase: 0
    function find(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children ?? []) { const found = find(child,name); if(found) return found; }
        return null;
    }
    FloatingWindow {
        implicitWidth: 1000; implicitHeight: 800
        AssistantPanel { id: launcher; width: 450; embedded: true }
        ChatActionCard { id: card; x: 500; width: 450; entry: SidebarChat.currentReply; live: true }
    }
    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: {
            if (root.phase === 0) {
                Config.options.assistant.enabled = true;
                Assistant.submitted("Review file changes","sidebar");
                Assistant.task = 717; Assistant.busy = true;
                const diff = "--- before\\n+++ after\\n-old\\n+new\\n" + "+extra line\\n".repeat(3000);
                Assistant.handle(JSON.stringify({type:"approval",task:717,approval:"fixture",tool:"files_copy",details:{diff:[{path:"/example/report.txt",change:"modified",before_bytes:4,after_bytes:30000,diff}]}}));
            } else {
                const chatScroll=root.find(card,"chatApprovalScroll");
                const text=root.find(card,"chatApprovalText");
                const launcherScroll=root.find(launcher,"launcherApprovalScroll");
                const valid=chatScroll && launcherScroll && text && text.text.includes("-old") && text.text.includes("+new")
                    && text.text.includes("/example/report.txt") && chatScroll.height <= 320 && launcherScroll.height <= 320
                    && chatScroll.contentHeight > chatScroll.height && launcherScroll.contentHeight > launcherScroll.height;
                console.log(valid ? "DRIVER_PASS" : "DRIVER_FAIL bounded diff presentation"); Qt.quit();
            }
            root.phase++;
        }
    }
}
'''
        case=pages.SettingsPagesTests()
        with patch.object(pages,'SHELL',Path(os.environ.get('VELORA_QML_SOURCE',pages.SHELL))):
            output=case.run_driver(driver)
        self.assertIn('DRIVER_PASS',output,output[-7000:])
        case.assert_clean(output)

    def test_background_reranking_does_not_scroll_search(self):
        driver = '''
import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.ii.overview
ShellRoot {
    id: root
    property int phase: 0
    property bool failed: false
    property var rows: []
    property real classicY: 0
    property real inputY: 0
    property real scrolledOffset: 0
    property int executions: 0
    function check(condition, label) { if (!condition) { failed=true; console.log("CHECK_FAIL " + label); } }
    function find(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children ?? []) { const found=find(child,name); if(found)return found; }
        return null;
    }
    Component { id: result; LauncherSearchResult {} }
    FloatingWindow {
        implicitWidth: 800; implicitHeight: 900
        SearchWidget { id: classic; width: 700 }
    }
    Timer {
        interval: 1000; running: true
        onTriggered: {
            Assistant.panelOpen=false;
            LauncherSearch.results=[]; classic.setSearchingText("stable viewport fixture");
            for(let i=0;i<36;i++) root.rows=root.rows.concat([result.createObject(root,{id:"row"+i,name:"Result "+i,type:"File",execute:() => { root.executions++; }})]);
            LauncherSearch.results=root.rows;
            checks.start();
        }
    }
    Timer {
        id: checks
        interval: 400; repeat: true
        onTriggered: {
            const list=root.find(classic,"launcherResults");
            const input=root.find(classic,"launcherSearchInput");
            if(root.phase===0) {
                root.classicY=list.contentY; root.inputY=input.mapToItem(null,0,0).y;
                root.check(list.currentIndex===0,"initial result selected");
                LauncherSearch.results=root.rows.slice(1,26).concat([root.rows[0]],root.rows.slice(26));
            } else if(root.phase===1) {
                console.log("VIEWPORT classic="+root.classicY+"→"+list.contentY);
                root.check(Math.abs(list.contentY-root.classicY)<1,"classic background rerank preserves viewport");
                root.check(classic.selectedResultKey==="row0","rerank preserves Enter identity");
                root.check(list.currentIndex===-1,"offscreen selection is not implicitly activated");
                input.accepted(); root.check(root.executions===0,"Enter cannot execute an offscreen result");
                root.check(Math.abs(input.mapToItem(null,0,0).y-root.inputY)<1,"search field stays vertically anchored");
                list.moveSelection(1);
                root.check(list.currentIndex===0 && Math.abs(list.contentY-root.classicY)<1,"next arrow resumes from the visible results");
                list.currentIndex=26;
            } else if(root.phase===2) {
                root.check(list.contentY>root.classicY+1,"classic keyboard navigation scrolls intentionally");
                root.scrolledOffset=list.contentY-list.originY;
                LauncherSearch.results=root.rows.slice();
            } else if(root.phase===3) {
                root.check(Math.abs((list.contentY-list.originY)-root.scrolledOffset)<1,"expanded results stay at the user's scroll position across the debounce");
                classic.setSearchingText("new viewport fixture"); LauncherSearch.results=root.rows;
            } else {
                root.check(list.currentIndex===0,"new query resets default selection");
                const firstOffset=list.itemAtIndex(0).y-list.contentY;
                root.check(firstOffset>=-1 && firstOffset<=list.topMargin+1,"new query starts at the first result");
                console.log(root.failed ? "DRIVER_FAIL viewport stability" : "DRIVER_PASS"); Qt.quit();
            }
            root.phase++;
        }
    }
}
'''
        case=pages.SettingsPagesTests()
        with patch.object(pages,'SHELL',Path(os.environ.get('VELORA_QML_SOURCE',pages.SHELL))):
            output=case.run_driver(driver)
        self.assertIn('DRIVER_PASS',output,output[-7000:])
        case.assert_clean(output)

    def test_ai_panel_keyboard_focus_and_launcher_bounds(self):
        artifacts = pages.PROJECT / 'cache/launcher-ai'
        artifacts.mkdir(parents=True, exist_ok=True)
        driver = r'''
import QtQuick
import QtTest
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.ii.overview
import qs.modules.waffle.startMenu
ShellRoot {
    id: root
    property int phase: 0
    property bool failed: false
    TestCase { id: interaction; name: "LauncherAiInteractions"; when: false }
    function find(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children ?? []) { const found = find(child, name); if (found) return found; }
        return null;
    }
    function check(ok, label) { if (!ok) { failed = true; console.log("CHECK_FAIL " + label); } }
    // OpacityMask uses a GPU shader that Qt's software snapshot backend omits.
    // Keep the real layout and controls; bypass only these offscreen effects.
    function flattenLayers(item) {
        if (item.layer) item.layer.enabled = false;
        for (const child of item.children ?? []) flattenLayers(child);
    }
    function verifyPanel(item, name) {
        const input = find(item, "launcherAssistantInput");
        const search = find(item, "launcherSearchInput");
        const transcript = find(item, "launcherAssistantTranscript");
        const close = find(item, "launcherAssistantClose");
        check(input && search && transcript && close, name + " widgets loaded");
        if (!input || !search || !transcript || !close) return;
        check(input.activeFocus, name + " focuses conversation input on open");
        const query = LauncherSearch.query;
        SidebarChat.draft = "draft";
        input.cursorPosition = input.length;
        interaction.keyClick(Qt.Key_Backspace);
        interaction.keyClick(Qt.Key_Return, Qt.ShiftModifier);
        interaction.keyClick(Qt.Key_A);
        check(SidebarChat.draft === "draf\na", name + " composer handles text and newlines");
        check(LauncherSearch.query === query && Assistant.panelOpen, name + " composer does not edit search");
        check(transcript.height <= 350 && transcript.contentHeight > transcript.height, name + " long response scrolls within bounds");
        const bottom = input.mapToItem(capture, 0, input.height).y;
        check(bottom > 0 && bottom < capture.height, name + " composer remains inside window");
        search.accepted();
        check(!Assistant.busy && !Assistant.preparingSubmission, name + " Enter in search does not activate hidden result");
        flattenLayers(item);
        capture.grabToImage(result => {
            result.saveToFile("ARTIFACTS/" + name + ".png");
            close.clicked();
            check(!Assistant.panelOpen && search.activeFocus, name + " closing restores search focus");
        });
    }
    FloatingWindow {
        visible: true
        implicitWidth: 1000; implicitHeight: 1100
        Rectangle {
            id: capture; anchors.fill: parent; color: Appearance.colors.colLayer0
            SearchWidget { id: classic; x: 32; y: 20; visible: root.phase < 3 }
            Loader { id: waffle; x: 32; y: 20; active: root.phase >= 3; sourceComponent: StartMenuContent { searching: true } }
        }
    }
    Timer {
        interval: 700; running: true; repeat: true
        onTriggered: {
            if (root.phase === 0) {
                Config.options.language.ui = "ru_RU";
                Config.options.assistant.enabled = true;
                Config.options.assistant.model = "fixture";
                LauncherSearch.query = "launcher fixture";
                Assistant.messages = [{role:"user",text:"Покажи длинный ответ"},{role:"assistant",text:"Проверка длинного ответа с переносами строк.\n\n".repeat(80)}];
                Assistant.panelOpen = true;
            } else if (root.phase === 1) {
                root.verifyPanel(classic, "classic-launcher");
            } else if (root.phase === 2) {
                Assistant.panelOpen = true;
                const search = root.find(classic,"launcherSearchInput");
                search.forceActiveFocus();
                interaction.keyClick(Qt.Key_A);
                root.check(!Assistant.panelOpen, "editing classic search returns to results");
            } else if (root.phase === 3) {
                Assistant.panelOpen = true;
            } else if (root.phase === 4) {
                root.verifyPanel(waffle.item, "waffle-launcher");
            } else if (root.phase === 5) {
                Assistant.panelOpen = true;
                const search = root.find(waffle.item,"launcherSearchInput");
                search.forceActiveFocus();
                interaction.keyClick(Qt.Key_A);
                root.check(!Assistant.panelOpen, "editing waffle search returns to results");
            } else {
                console.log(root.failed ? "DRIVER_FAIL launcher interactions" : "DRIVER_PASS"); Qt.quit();
            }
            root.phase++;
        }
    }
}
'''.replace('ARTIFACTS', str(artifacts))
        case = pages.SettingsPagesTests()
        with patch.object(pages, 'SHELL', Path(os.environ.get('VELORA_QML_SOURCE', pages.SHELL))):
            output = case.run_driver(driver, service_overrides={'AppSearch.qml': '''pragma Singleton
import Quickshell
Singleton {
    property var list: []
    function fuzzyQuery(query) { return []; }
    function guessIcon(name) { return "application-x-executable"; }
}
'''})
        (artifacts / 'launcher-interaction.log').write_text(output)
        self.assertIn('DRIVER_PASS', output, output[-7000:])
        case.assert_clean(output)
