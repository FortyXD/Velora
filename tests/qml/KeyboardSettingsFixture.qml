import QtQuick
import QtTest
import qs.modules.common
import qs.services

Item {
    id: root
    required property var host
    readonly property var page: host.currentPageItem
    property int step: 0
    property var observedBoard: null
    readonly property bool mapSettled: !!observedBoard && observedBoard.displayedKeys === observedBoard.keys && !observedBoard.switchingLayout
    property int transitions: 0
    Connections {
        target: root.observedBoard
        function onSwitchingLayoutChanged() { if (root.observedBoard?.switchingLayout) root.transitions++; }
    }
    TestCase { id: input; when: false }

    function check(condition, message) {
        if (!condition) { console.log("CHECK_FAIL " + message); Qt.quit(); }
        return condition;
    }
    function find(name) { return input.findChild(page, name); }
    function clickKey(name) {
        const key = find("keyboardKey-" + name);
        input.mouseClick(key, key.width / 2, key.height / 2);
    }
    function textItem(parent, text) {
        if (parent.text === text) return parent;
        for (const child of parent.children ?? []) {
            const found = textItem(child, text);
            if (found) return found;
        }
        return null;
    }
    function rowsAligned(board) {
        for (const row of board.rows) {
            let nextX = 0;
            for (const [name] of row) {
                const key = input.findChild(board, "keyboardKey-" + name);
                if (key.x !== nextX || key.width <= 0 || key.width !== Math.round(key.width)) return false;
                nextX += key.width + board.gap;
            }
            if (nextX - board.gap !== board.rowWidth) return false;
        }
        return true;
    }

    Timer {
        interval: 120; running: true
        onTriggered: {
            advance();
            restart();
        }
        function advance() {
            const page = root.page;
            if (!page || !Config.ready) return;
            const preview = root.find("keyboardPreview");
            const catalog = root.find("shortcutCatalog");
            const field = root.find("keyboardTypingField");
            if (!preview || !catalog) return;
            switch (root.step) {
            case 0: {
                if (!catalog.shown || !HyprlandXkb.keyboardName) return;
                if (!root.check(root.host.currentPageData.key === "keyboard" && root.host.pages.every(p => p.key !== "shortcuts"),
                                "old shortcuts link did not open the editor under Keyboard")) return;
                HyprlandSettings.values = Object.assign({}, HyprlandSettings.values, {"input:kb_layout": "us,ru", "input:kb_variant": "intl,"});
                HyprlandKeybinds.groups = [{id: "windows", name: "Windows", icon: "apps"}, {id: "pointer", name: "Mouse", icon: "mouse"},
                    {id: "shell", name: "Shell", icon: "dashboard"}];
                const binds = [["q", "code:24"], ["w", "W"], ["b", "B"], ["arrow", "Right"], ["mouse", "mouse:273"]].map(([id, key]) => ({
                    id, key, mods: ["Super"], group: id === "mouse" ? "pointer" : "windows", description: "Action " + id,
                    default_key: key, default_mods: ["Super"], remappable: id !== "arrow"
                }));
                binds.push({id: "shell.clipboard", group: "shell", description: "Clipboard history", mods: ["Super"], key: "V",
                    default_mods: ["Super"], default_key: "V", remappable: true});
                const byId = {};
                for (const bind of binds) byId[bind.id] = bind;
                HyprlandKeybinds.bindMap = byId;
                HyprlandKeybinds.binds = binds;
                HyprlandKeybinds.ready = true;
                root.host.goBack();
                break;
            }
            case 1: {
                if (!preview.keymap.AD01) return;
                if (!root.check(page.tab === "overview" && preview.variant === "dvorak" && preview.index === 2
                                && preview.keymap.AD01.levels[0] === "'" && preview.configuredIndex === -1,
                                "map did not start on the physical keyboard's active group")) return;
                if (!root.check(!root.find("keyboardMapMode") && !root.textItem(preview, "Other keys") && field.visible && field.enabled && field.activeFocus
                                && preview.keyBindings.AD01[0].id === "q", "typing and shortcuts unavailable together")) return;
                const board = root.find("keyboardMap");
                root.observedBoard = board;
                if (!root.check(root.rowsAligned(board), "keyboard rows have different edges or uneven gaps")) return;
                board.forceActiveFocus(Qt.TabFocusReason);
                input.keyClick(Qt.Key_Right);
                if (!root.check(board.focusedKey === "AD02", "arrow navigation on the map")) return;
                input.keyPress(Qt.Key_A);
                if (!root.check(preview.pressedCodes.length === 1 && field.text === "a" && field.activeFocus,
                                "typing while browsing the map lost its first key")) return;
                input.keyRelease(Qt.Key_A);
                if (!root.check(preview.pressedCodes.length === 0, "released key stayed pressed")) return;
                HyprlandXkb.layoutChanged("fixture-keyboard,Russian");
                break;
            }
            case 2: {
                if (preview.keymap.AD01?.levels[0] !== "й" || !root.mapSettled) return;
                if (!root.check(preview.keymap.AD01.levels[0] === "й" && root.find("keyboardKey-AD01").upper === "Й"
                                && field.text === "a" && field.activeFocus && preview.keyBindings.AD01[0].id === "q"
                                && root.transitions > 0, "layout change lost its animation, input or physical shortcut")) return;
                const key = root.find("keyboardKey-AB05");
                const legend = root.textItem(key, "И");
                if (!root.check(legend && legend.horizontalAlignment === Text.AlignHCenter && legend.verticalAlignment === Text.AlignVCenter
                                && legend.width === key.width && legend.height === key.height, "Cyrillic legend not centered in its key")) return;
                preview.pressedCodes = [preview.keymap.LFSH.code];
                if (!root.check(root.find("keyboardKey-AE03").label === preview.keymap.AE03.levels[1], "Shift did not show its printed symbol")) return;
                preview.pressedCodes = [];
                root.host.width = root.host.minimumWidth;
                preview.pickedKey = "AB05";
                break;
            }
            case 3: {
                const chord = root.find("keyboardShortcutChord");
                const levels = root.find("keyboardLevels");
                const shift = root.textItem(levels, "Shift");
                const upper = root.textItem(levels, "И");
                if (!root.check(root.rowsAligned(root.find("keyboardMap")) && chord?.key === "B" && chord.mods.includes("Super")
                                && shift && upper && Math.abs(shift.mapToItem(levels, 0, shift.baselineOffset).y
                                    - upper.mapToItem(levels, 0, upper.baselineOffset).y) < 0.6,
                                "compact shortcut or character baselines for Super+B on И")) return;
                HyprlandXkb.layoutChanged("fixture-keyboard,English (Dvorak)");
                HyprlandXkb.layoutChanged("fixture-keyboard,Russian");
                HyprlandXkb.layoutChanged("fixture-keyboard,English (US, intl., with dead keys)");
                break;
            }
            case 4: {
                if (preview.sourceMap.displayedId !== "us/intl" || !root.mapSettled) return;
                if (!root.check(preview.index === 0 && preview.variant === "intl" && root.find("keyboardKey-AD01").upper === "Q",
                                "rapid layout changes lost the final XKB variant")) return;
                root.find("keyboardPreviewLayout").selected(1);
                break;
            }
            case 5: {
                // The offscreen compositor stub reports Russian only after the selector switches the right device and group.
                if (preview.layout !== "ru") { HyprlandXkb.refreshDevices(); return; }
                if (preview.sourceMap.displayedId !== "ru/" || !root.mapSettled) return;
                if (!root.check(preview.index === 1 && root.find("keyboardKey-AD01").upper === "Й" && field.text === "a",
                                "selecting the input layout lost the key labels or typed text")) return;
                root.clickKey("LCTL");
                if (!root.check(preview.modifiers.includes("Ctrl") && !preview.keyBindings.AD01, "modifier did not change the map")) return;
                input.keyClick(Qt.Key_W);
                if (!root.check(field.text === "aw", "choosing a modifier interrupted typing")) return;
                root.clickKey("LCTL");
                root.clickKey("AD01");
                if (!root.check(catalog.shown && catalog.filter === "Super + Q" && catalog.matches("q") && !catalog.matches("w"),
                                "key did not open its exact combination")) return;
                break;
            }
            case 6: {
                const map = root.find("shortcutKeyboardMap");
                if (!map?.displayedKeys.AD01) return;
                root.observedBoard = map;
                if (!root.check(catalog.displayedUid === "q" && map.activeKeys.join() === "LWIN,AD01"
                                && input.findChild(map, "keyboardKey-AD01").label === "Й", "map click did not select the physical shortcut in the catalog")) return;
                const changed = Object.assign({}, HyprlandKeybinds.bindMap.q, { mods: ["Ctrl", "Shift"], key: "code:56" });
                HyprlandKeybinds.bindMap = Object.assign({}, HyprlandKeybinds.bindMap, { q: changed });
                HyprlandKeybinds.binds = HyprlandKeybinds.binds.map(bind => bind.id === "q" ? changed : bind);
                const updated = root.find("shortcutKeyboardMap");
                if (!root.check(catalog.displayedUid === "q" && updated?.activeKeys.join() === "LCTL,LFSH,AB05", "remapped chord lost its preview")) return;
                catalog.clearFilters();
                input.findChild(root.find("shortcutRow-arrow"), "shortcutAction").click();
                if (!root.check(updated.activeKeys.includes("RGHT") && !updated.extraLabel && !HyprlandKeybinds.activeRecorder,
                                "read-only arrow action did not preview its key")) return;
                const row = root.find("shortcutRow-b");
                const button = input.findChild(row, "shortcutAction");
                button.forceActiveFocus(Qt.TabFocusReason);
                root.observedBoard = root.find("shortcutKeyboardMap");
                if (!root.check(catalog.selectedUid === "b" && root.observedBoard.activeKeys.join() === "LWIN,AB05"
                                && !HyprlandKeybinds.activeRecorder, "tab focus did not preview the shortcut")) return;
                input.keyClick(Qt.Key_Return);
                const recorder = input.findChild(row, "shortcutRecorder");
                if (!root.check(recorder.recording && recorder.activeFocus, "Enter on the action did not start recording")) return;
                input.keyClick(Qt.Key_Escape);
                if (!root.check(!recorder.recording && !HyprlandKeybinds.captureWanted && HyprlandKeybinds.remap.b === undefined,
                                "Escape did not cancel the edit")) return;
                root.transitions = 0;
                HyprlandXkb.layoutChanged("fixture-keyboard,English (US, intl., with dead keys)");
                break;
            }
            case 7: {
                if (root.observedBoard.displayedKeys.AB05?.levels[0] !== "b" || root.observedBoard.switchingLayout) return;
                if (!root.check(root.transitions > 0 && root.observedBoard.activeKeys.includes("AB05"), "catalog layout transition lost the selected chord")) return;
                const row = root.find("shortcutRow-shell.clipboard");
                const pane = page.scrollerOf(row);
                pane.contentY = Math.max(pane.originY, Math.min(row.mapToItem(pane.contentItem, 0, 0).y - 10, pane.contentHeight - pane.height));
                const button = input.findChild(row, "shortcutAction");
                input.mouseMove(button, button.width / 2, button.height / 2);
                if (!root.check(catalog.displayedUid === row.uid && catalog.selectedUid === "b" && !HyprlandKeybinds.activeRecorder,
                                "hover did not preview Clipboard history")) return;
                input.mouseMove(root.find("shortcutSearch"), 5, 5);
                if (!root.check(catalog.displayedUid === "b", "leaving the row lost the selected shortcut")) return;
                input.mouseClick(button, button.width / 2, button.height / 2);
                const recorder = input.findChild(row, "shortcutRecorder");
                if (!root.check(recorder.recording && recorder.activeFocus && catalog.selectedUid === row.uid,
                                "clicking Clipboard history did not start recording")) return;
                input.keyPress(Qt.Key_Control);
                if (!root.check(root.observedBoard.activeKeys.join() === "LCTL", "held modifier missing from the map during editing")) return;
                input.keyClick(Qt.Key_K, Qt.ControlModifier);
                input.keyRelease(Qt.Key_Control);
                const saved = HyprlandKeybinds.remap[row.uid];
                if (!root.check(saved?.mods === "Ctrl" && saved.key === "K" && !HyprlandKeybinds.captureWanted,
                                "first shortcut entered after clicking Clipboard history was not saved")) return;
                Config.options.appearance.animationSpeed = 0;
                root.transitions = 0;
                HyprlandXkb.layoutChanged("fixture-keyboard,Russian");
                break;
            }
            case 8: {
                if (root.observedBoard.displayedKeys.AB05?.levels[0] !== "и") return;
                if (!root.check(!root.transitions && !root.observedBoard.switchingLayout, "reduced-motion layout switch ran an animation")) return;
                Config.options.appearance.animationSpeed = 1;
                root.find("shortcutGroupFilter").selected("pointer");
                const mouseKey = input.findChild(root.observedBoard, "keyboardKey-extra");
                if (!root.check(catalog.matches("mouse") && !catalog.matches("q") && catalog.displayedUid === "mouse"
                                && mouseKey.visible && mouseKey.highlighted && mouseKey.label === KeyUtils.keyLabel("mouse:273")
                                && root.find("catalogChord").labels.includes(KeyUtils.keyLabel("mouse:273")), "mouse shortcut missing from filtered preview")) return;
                const search = root.find("shortcutSearch");
                search.forceActiveFocus();
                input.keyClick(Qt.Key_X);
                if (!root.check(catalog.filter === "x" && !catalog.matches("mouse") && !catalog.displayedBind, "empty search kept an unrelated preview")) return;
                root.host.openPage("shortcuts", "shortcutRow-w");
                break;
            }
            case 9: {
                if (catalog.selectedUid !== "w") return;
                if (!root.check(!catalog.filter && !catalog.groupFilter && catalog.matches("w") && root.find("shortcutRow-w").visible,
                                "old deep link kept the previous key filter")) return;
                root.host.goBack();
                if (!root.check(page.tab === "overview" && preview.layout === "ru" && field.text === "aw", "back lost the preview state")) return;
                preview.defaultRequested(preview.configuredIndex);
                if (!root.check(page.layoutsValue === "ru,us" && page.variantCodes[1] === "intl" && preview.layout === "ru",
                                "making a layout the default separated it from its variant")) return;
                page.navigateToSection("cheatsheet");
                break;
            }
            case 10: {
                if (HyprlandSettings.applying) return;
                if (!root.check(HyprlandSettings.overrides["input:kb_layout"] === "ru,us"
                                && HyprlandSettings.overrides["input:kb_variant"] === ",intl", "saved layout and variant order")) return;
                if (!root.check(root.find("cheatSheetPreview")?.visible && KeyUtils.keyLabel("code:999") === "code:999",
                                "cheat sheet preview or unknown keycode label")) return;
                console.log("DRIVER_PASS"); Qt.quit(); return;
            }
            }
            root.step++;
        }
    }
    Timer { interval: 30000; running: true; onTriggered: { console.log("CHECK_FAIL keyboard stage " + root.step); Qt.quit(); } }
}
