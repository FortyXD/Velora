"""Launcher bridge lifecycle in a private Qt test process."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import test_connectivity_qml as support

@unittest.skipUnless(support.QT_TEST_RUNNER,'Qt Quick Test unavailable')
class AgentQmlTests(unittest.TestCase):
    def test_lifecycle(self):
        with tempfile.TemporaryDirectory(prefix='agent-qml-') as directory:
            root=Path(directory);support.write_common(root)
            support.write_singletons(root,{
                'Config':'property bool ready: true; property var options: ({assistant:{enabled:true},policies:{ai:2}})',
                'GlobalStates':'property bool screenLocked: false; property bool searchOpen: false; property bool overviewOpen: false; property bool sidebarLeftOpen: false',
                'PowerSaving':'property bool onBattery: true',
                'Lens':'property bool assistantBusy: false',
                'AppSearch':'property var list: []',
                'Presets':'property var presets: []; signal applied(string id); function apply(id) { applied(id); }',
                'KeyringStorage':'property var keyringData: ({})',
                'LocalAiRuntime':'property string memoryStatus: ""; property bool unloading: false; function stop() {}',
                'Ai':'property bool localModelsLoaded: false; property var installedModelIds: []; property string defaultLocalModelId: ""; property var models: ({}); '
                    'property bool nativeGenerating: false; readonly property bool generating: nativeGenerating || Assistant.busy || Assistant.preparingSubmission; property bool requestAfterKeyring: false; property string currentModelId: "test"; '
                    'property string effectiveTool: "none"; property bool currentModelIsLocal: true; property var messageIDs: []; property var messageByID: ({}); '
                    'property var restored: []; property string sent: ""; '
                    'function getModel() { return {name:"test"}; } function clearMessages() {} function restoreConversation(entries) { restored=entries; } '
                    'function attachFile(path) {} function sendUserMessage(text) { sent=text; }',
                'ChatStore':'''property var chats: []; property string query: ""; property var saved: ({}); property var waiting: []; property bool deferred: false; property string failure: "";
                    function refresh() {} function save(chat, done) {
                        const value=JSON.parse(JSON.stringify(chat));
                        if (deferred) { waiting=waiting.concat([{value,done}]); return; }
                        if (failure) { if(done) done(false,failure); return; }
                        saved=Object.assign({},saved,{[value.id]:value}); if(done) done(true, "");
                    }
                    function acknowledge() { const calls=waiting; waiting=[]; calls.forEach(c=>{saved=Object.assign({},saved,{[c.value.id]:c.value}); if(c.done)c.done(true, "");}); }
                    function call(method, params, done) { if(method==="load")done(saved[params.id]); }
                ''',
            })
            (root/'IpcHandler.qml').write_text('import QtQuick\nQtObject { property string target }')
            with patch.object(support,'SHELL',Path(os.environ.get('VELORA_QML_SOURCE',support.SHELL))):
                (root/'Assistant.qml').write_text(support.production('services/Assistant.qml', [('id: root\n','id: root\n readonly property var backend: process\n readonly property var ipcHandler: assistantIpc\n')]))
                (root/'SidebarChat.qml').write_text(support.production('services/SidebarChat.qml'))
                (root/'SidebarMessage.qml').write_text(support.production('services/ai/SidebarMessage.qml'))
                shutil.copy2(support.SHELL/'services/IntentRouter.js',root/'IntentRouter.js')
            with (root/'qmldir').open('a') as f:f.write('singleton Assistant 1.0 Assistant.qml\nsingleton SidebarChat 1.0 SidebarChat.qml\n')
            shutil.copy2(support.PROJECT/'tests/qml/tst_assistant.qml',root)
            result=subprocess.run([support.QT_TEST_RUNNER,'-input',str(root/'tst_assistant.qml'),'-o','-,txt'],env={**os.environ,'QT_QPA_PLATFORM':'offscreen','QT_QUICK_BACKEND':'software','QT_QPA_PLATFORMTHEME':'generic'},capture_output=True,text=True,timeout=30)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertNotIn('ReferenceError',result.stdout+result.stderr)
            self.assertNotIn('TypeError',result.stdout+result.stderr)
