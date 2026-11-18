"""Exercise the real NotesContent editor and file watcher in an isolated offscreen window."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from test_workspace_preview_flick import isolated_env, write, QUICKSHELL, SHELL


@unittest.skipUnless(QUICKSHELL, "requires Quickshell")
class NotesEfficiencyTests(unittest.TestCase):
    def test_scroll_selection_autosave_and_hidden_editor(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            env = isolated_env(root)
            note = root / 'data/notes.txt'
            note.write_text(''.join(f'- Тест {i} 📝\n' for i in range(1000)))
            shutil.copyfile(SHELL / 'modules/ii/overlay/notes/NotesContent.qml', root / 'NotesContent.qml')
            def module(path, entries):
                directory = path.replace('.', '/')
                manifest = ['module qs.' + path]
                for component, (singleton, source) in entries.items():
                    write(root, f'{directory}/{component}.qml', ('pragma Singleton\n' if singleton else '') + source)
                    manifest.append(('singleton ' if singleton else '') + f'{component} 1.0 {component}.qml')
                write(root, directory + '/qmldir', '\n'.join(manifest))
            module('services', {'Translation': (True, 'import QtQuick\nQtObject { function tr(s) { return s } }')})
            module('modules.common', {
                'Appearance': (True, 'import QtQuick\nQtObject { property var font: ({pixelSize:{normal:14}}); property var colors: ({colSubtext:"gray",colOnLayer1:"black"}); }'),
                'Directories': (True, 'import QtQuick\nQtObject { property string notesPath: ' + json.dumps(str(note)) + ' }')})
            module('modules.common.widgets', {
                'StyledTextArea': (False, 'import QtQuick.Controls\nTextArea { objectName:"editor"; font.pixelSize:14 }'),
                'StyledText': (False, 'import QtQuick\nText {}'),
                'RippleButton': (False, 'import QtQuick.Controls\nButton { property real buttonRadius; objectName:"copy" }'),
                'MaterialSymbol': (False, 'import QtQuick\nText { property real iconSize }')})
            module('modules.ii.overlay', {'OverlayBackground': (False, 'import QtQuick\nRectangle {}')})
            write(root, 'shell.qml', '''import QtQuick
import Quickshell
ShellRoot {
    FloatingWindow { visible: true; implicitWidth: 350; implicitHeight: 240
        NotesContent { id: notes; anchors.fill: parent; property int updates: 0
            onCopyListEntriesChanged: ++updates
        }
    }
    function editor(item) {
        if (item.objectName === "editor") return item;
        for (const child of item.children) { const found=editor(child); if(found) return found; }
        return null;
    }
    function check(value, message) { if (!value) { console.error(message); Qt.exit(2); } }
    Timer { interval: 60; running: true; repeat: true; property int step: 0; property int baseline: 0
        onTriggered: {
            if (!notes.content || notes.copyListEntries.length===0 && step===0) return;
            const visible = notes.copyListEntries;
            const edit = editor(notes);
            if (step===0) {
                check(visible.length>0 && visible.length<30 && visible[0].content==="Тест 0 📝","initial visible bullets");
                baseline=notes.updates;
            }
            if (step<20) notes.content += "x";
            if (step===20) {
                check(notes.updates===baseline,"offscreen edits rebuilt visible buttons");
                notes.focusAtEnd();
            }
            if (step===23) {
                check(visible.length<30 && visible.some(e=>e.content==="Тест 999 📝"),"scroll to last bullet");
                edit.select(notes.content.indexOf("- Тест 999"),notes.content.lastIndexOf("\\n"));
            }
            if (step===24) {
                check(!visible.some(e=>e.content==="Тест 999 📝"),"selection must hide its button");
                notes.content += " saved";
                notes.pageActive=false;
            }
            if (step===25) {
                check(visible.length===0,"hidden buttons"); notes.pageActive=true;
            }
            if (step===28) {
                check(notes.content.endsWith(" saved"),"lost autosave on hide");
                console.log("NOTES_OK"); Qt.quit();
            }
            ++step;
        }
    }
    Timer { interval: 10000; running: true; onTriggered: Qt.exit(3) }
}''')
            proc = subprocess.run([QUICKSHELL, '-p', str(root / 'shell.qml')], env=env, text=True,
                                  capture_output=True, timeout=15)
            output = proc.stdout + proc.stderr
            self.assertEqual(proc.returncode, 0, output)
            self.assertIn('NOTES_OK', output)
            self.assertNotRegex(output, 'TypeError|ReferenceError')
            self.assertTrue(note.read_text().endswith('x' * 20 + ' saved'))
