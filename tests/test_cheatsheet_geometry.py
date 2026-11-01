"""Render the real cheatsheet layout at several logical screen sizes, without a compositor."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "dots/.config/quickshell/ii/modules/ii/cheatsheet"
RUNNER = shutil.which("qmltestrunner6") or next((str(path) for path in (
    Path("/usr/lib/qt6/bin/qmltestrunner"), Path("/usr/lib64/qt6/bin/qmltestrunner")) if path.is_file()), None)


class CheatsheetGeometryTests(unittest.TestCase):
    @unittest.skipUnless(RUNNER, "Qt 6 Quick Test is not installed")
    def test_both_pages_fit_small_landscape_and_portrait_screens(self):
        with tempfile.TemporaryDirectory(prefix="velora-cheatsheet-") as directory:
            target = Path(directory)
            source = (SOURCE / "Cheatsheet.qml").read_text()
            start = source.index("Rectangle {\n                id: cheatsheetBackground")
            # This block contains the actual sizing, layouts and both SwipeView pages.
            end = source.index("\n        }\n    }\n\n    IpcHandler", start)
            background = source[start:end].strip()
            background = background.replace("CheatsheetKeybinds {", "CheatsheetKeybinds { id: keybindPage", 1)
            background = background.replace("CheatsheetPeriodicTable {}", "CheatsheetPeriodicTable { id: periodicPage }", 1)
            (target / "CheatsheetGeometry.qml").write_text("""
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.synchronizer
import Qt5Compat.GraphicalEffects
Item {
 id: root
 property var tabButtonList: []
 property alias panel: cheatsheetBackground
 property alias pages: swipeView
 property alias periodic: periodicPage
 property alias keybinds: keybindPage
 Item { id: cheatsheetRoot; anchors.fill: parent; function hide() {}
""" + background + "\n}\n}\n")
            for name in ("CheatsheetKeybinds.qml", "CheatsheetPeriodicTable.qml", "ElementTile.qml"):
                text = "\n".join(line for line in (SOURCE / name).read_text().splitlines()
                                 if not line.startswith(("import qs", "import Quickshell")))
                if name == "CheatsheetPeriodicTable.qml":
                    text = text.replace("id: root", "id: root\nproperty alias tableLayout: mainLayout", 1)
                if name == "CheatsheetKeybinds.qml":
                    text = text.replace("id: root", "id: root\nproperty alias scrollArea: flickable", 1)
                (target / name).write_text(text)
            shutil.copy2(SOURCE / "periodic_table.js", target)
            singletons = {
                "Appearance": 'property var sizes:({elevationMargin:10}); property var rounding:({small:6,normal:12,full:99,windowRounding:20}); property var colors:({colLayer0:"black",colLayer0Border:"gray",colLayer1:"gray",colLayer2:"gray",colOnLayer1:"white",colOnLayer2:"white",colPrimary:"orange",colSubtext:"white",colSecondaryContainer:"gray",colSecondaryContainerHover:"gray",colSecondaryContainerActive:"gray",colOnSecondaryContainer:"white",colPrimaryContainer:"gray",colOnPrimaryContainer:"white",colSecondary:"orange"}); property var font:({family:{main:"sans"},pixelSize:{title:22,small:12,smaller:11,smallest:10,normal:14,huge:26},variableAxes:{main:{}}})',
                "Persistent": 'property var states:({cheatsheet:{tabIndex:0}})',
                "Translation": 'function tr(text) { return text }',
                "Config": 'property var options:({cheatsheet:{fontSize:{comment:11}}})',
                "ColorUtils": 'function transparentize(color) { return color }',
                "KeyUtils": 'function comboText(mods,key) { return key } function comboLabels(mods,key) { return [key] }',
                "HyprlandKeybinds": 'property bool ready:true; property var groups:Array.from({length:7},(_,i)=>({id:"g"+i,name:"Group "+i,icon:"keyboard"})); property var binds:Array.from({length:140},(_,i)=>({group:"g"+(i%7),description:"Action "+i,mods:[],key:"A",disabled:false}))',
            }
            for name, body in singletons.items():
                (target / (name + ".qml")).write_text("pragma Singleton\nimport QtQuick\nQtObject { " + body + " }")
            (target / "qmldir").write_text("\n".join(f"singleton {name} 1.0 {name}.qml" for name in singletons))
            widgets = {
                "Toolbar": 'Item { property bool enableShadow; implicitWidth:220; implicitHeight:42 }',
                "ToolbarTabBar": 'Item { property var tabButtonList; property int currentIndex:0; function incrementCurrentIndex(){currentIndex++} function decrementCurrentIndex(){currentIndex--} function setCurrentIndex(value){currentIndex=value} }',
                "RippleButton": 'Button { property real buttonRadius; property color colBackground; property color colBackgroundHover; property color colRipple }',
                "MaterialSymbol": 'Text { property real iconSize; property real fill }',
                "StyledText": 'Text {}',
                "StyledFlickable": 'Flickable {}',
                "KeyCombo": 'Item { property var mods; property string key; property color keyColor; property color textColor; implicitWidth:35; implicitHeight:20 }',
            }
            for name, body in widgets.items():
                (target / (name + ".qml")).write_text("import QtQuick\nimport QtQuick.Controls\n" + body)
            (target / "tst_cheatsheet.qml").write_text("""
import QtQuick
import QtTest
TestCase {
 name:"CheatsheetGeometry"; when:windowShown; width:1920; height:1280
 CheatsheetGeometry { id: sheet }
 function test_screen_data() { return [
  {tag:"small-landscape",w:1280,h:800}, {tag:"compact",w:1024,h:600},
  {tag:"desktop",w:1920,h:1080}, {tag:"portrait",w:800,h:1280}]; }
 function test_screen(data) {
  sheet.width=data.w; sheet.height=data.h;
  for(let page=0;page<2;page++) {
   sheet.pages.currentIndex=page; wait(80);
   verify(sheet.panel.x>=0, "panel starts outside screen: "+sheet.panel.x);
   verify(sheet.panel.y>=0, "panel starts above screen: "+sheet.panel.y);
   verify(sheet.panel.x+sheet.panel.width<=data.w+.1,"panel exceeds screen width");
   verify(sheet.panel.y+sheet.panel.height<=data.h+.1,"panel exceeds screen height");
   verify(sheet.pages.width>0 && sheet.pages.height>0);
  }
  const table=sheet.periodic.tableLayout;
  const top=table.mapToItem(sheet.periodic,0,0);
  const bottom=table.mapToItem(sheet.periodic,table.width,table.height);
  verify(top.x>=-.1 && top.y>=-.1,"elements start outside their page");
  verify(bottom.x<=sheet.periodic.width+.1 && bottom.y<=sheet.periodic.height+.1,"elements clipped by page");
  verify(table.scale<=1 && table.scale>0,"invalid table scale");
  sheet.pages.currentIndex=0; wait(30);
  const scroll=sheet.keybinds.scrollArea;
  verify(scroll.contentHeight>scroll.height,"fixture should need vertical scrolling");
  scroll.contentY=scroll.contentHeight-scroll.height;
  verify(scroll.contentY>0,"long shortcut list must remain scrollable");
 }
}
""")
            result = subprocess.run([RUNNER, "-input", str(target), "-o", "-,txt"],
                                    env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "QT_QPA_PLATFORMTHEME": "generic",
                                         "QT_QUICK_BACKEND": "software"}, capture_output=True, text=True, timeout=25)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotRegex(result.stdout + result.stderr, "ReferenceError|TypeError")


if __name__ == "__main__":
    unittest.main()
