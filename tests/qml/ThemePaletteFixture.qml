import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.settings.preview
import qs.services

FloatingWindow {
    id: window
    visible: true
    implicitWidth: 660
    implicitHeight: 450
    color: Appearance.colors.colLayer2Base
    property int step: 0
    property string suggestion: ""
    TestCase { id: input; when: false }
    FileView { id: savedConfig; path: Config.filePath; watchChanges: true; onFileChanged: reload() }
    FileView {
        id: terminalPalette
        path: Directories.state + "/user/generated/terminal/kitty-theme.conf"
        blockLoading: true
        printErrors: false
    }
    FileView { id: wallpaperColors; path: Directories.generatedMaterialThemePath; blockWrites: true; printErrors: false }
    function terminalHas(line) {
        terminalPalette.reload();
        return terminalPalette.text().split("\n").includes(line);
    }
    ThemePaletteEditor {
        id: editor
        anchors { left: parent.left; top: parent.top; margins: 16 }
        width: parent.width - 32
        pageShown: true
    }
    function find(name) { return input.findChild(editor, name); }
    function click(item) { input.mouseClick(item, item.width / 2, item.height / 2); }
    function expect(ok, message) {
        if (!ok) { console.log("CHECK_FAIL", step, message); Qt.quit(); }
        return ok;
    }
    Timer {
        interval: 120; repeat: true; running: true
        onTriggered: {
            if (!Config.ready) return;
            const field = window.find("paletteHex");
            const apply = window.find("paletteApply");
            const reset = window.find("paletteReset");
            const colors = Appearance.m3colors;
            switch (window.step) {
            case 0:
                MaterialThemeLoader.syncTerminals = true;
                Config.options.background.wallpaperPath = Quickshell.shellPath("assets/images/autumn.jpg");
                MaterialThemeLoader.applyColors(JSON.stringify({background: "#302020", primary: "#cc7766", secondary: "#808090"}));
                if (!window.expect(!window.find("palettePicker"), "picker loaded before interaction")) return;
                window.click(window.find("paletteRole_primary"));
                break;
            case 1: {
                if (!field || field.height < 10 || editor.height < 160) return;
                const row = window.find("paletteSuggestion").parent;
                const choices = row.children.filter(item => item.objectName === "paletteSuggestion");
                if (choices.length < 2) return;
                const plane = window.find("paletteColorPlane");
                input.mouseClick(plane, plane.width * 0.65, plane.height * 0.3);
                const draggedColor = field.text;
                plane.forceActiveFocus(); input.keyClick(Qt.Key_Down);
                if (!window.expect(draggedColor !== field.text && apply.enabled, "pointer and keyboard color picking")) return;
                window.suggestion = choices[1].modelData;
                window.click(choices[1]);
                if (!window.expect(field.text === window.suggestion && colors.m3primary.toString() === "#cc7766", "wallpaper suggestion preview")) return;
                window.click(apply);
                break;
            }
            case 2:
                if (!window.expect(colors.m3primary.toString().toUpperCase() === window.suggestion, "selected wallpaper color")) return;
                window.click(window.find("paletteRole_secondary"));
                if (!window.expect(field.text.toLowerCase() === "#808090", "switched role")) return;
                field.forceActiveFocus();
                field.selectAll();
                for (const key of "147ade") input.keyClick(key);
                if (!window.expect(apply.enabled, "manual HEX accepted")) return;
                input.keyClick(Qt.Key_Return);
                break;
            case 3: {
                const disk = JSON.parse(savedConfig.text() || "{}");
                if (disk.appearance?.palette?.roleOverrides?.secondary !== "#147ADE") return;
                if (!window.terminalHas("selection_background #147ade")) return;
                if (!window.expect(colors.m3secondary.toString() === "#147ade", "manual color reached shell palette")) return;
                const nextPalette = JSON.stringify({background: "#eeeeee", primary: "#112233", secondary: "#667788"});
                wallpaperColors.setText(nextPalette);
                MaterialThemeLoader.applyColors(nextPalette);
                if (!window.expect(colors.m3primary.toString().toUpperCase() === window.suggestion
                    && colors.m3secondary.toString() === "#147ade", "new wallpaper replaced manual colors")) return;
                window.click(reset);
                break;
            }
            case 4:
                if (!window.terminalHas("selection_background #667788")) return;
                if (!window.expect(colors.m3secondary.toString() === "#667788" && !reset.enabled, "restored latest generated color")) return;
                for (const [role, property] of [["tertiary", "m3tertiary"], ["surface_container", "m3surfaceContainer"], ["on_surface", "m3onSurface"]]) {
                    window.click(window.find("paletteRole_" + role));
                    field.text = "#123456"; field.textEdited();
                    window.click(window.find("paletteCopy"));
                    if (!window.expect(Quickshell.clipboardText === "#123456", "copied HEX")) return;
                    window.click(apply);
                    if (!window.expect(colors[property].toString() === "#123456", role + " applied")) return;
                    window.click(reset);
                    if (!window.expect(colors[property].toString() === colors.generatedRoles[role], role + " reset")) return;
                }
                window.click(window.find("paletteRole_secondary"));
                editor.width = 280;
                break;
            case 5:
                if (!window.expect(window.find("palettePicker").columns === 1, "narrow layout")) return;
                field.forceActiveFocus();
                field.selectAll(); input.keyClick("a");
                if (!window.expect(!apply.enabled, "incomplete HEX cannot replace a role")) return;
                window.click(window.find("paletteRole_secondary"));
                break;
            case 6:
                if (window.find("palettePicker")) return;
                if (!window.expect(colors.m3secondary.toString() === "#667788", "closing discarded draft")) return;
                console.log("DRIVER_PASS"); Qt.quit(); return;
            }
            window.step++;
        }
    }
    Timer { interval: 14000; running: true; onTriggered: { console.log("CHECK_FAIL timeout", window.step); Qt.quit(); } }
}
