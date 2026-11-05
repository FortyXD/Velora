import QtQuick
import QtQuick.Layouts
import QtTest

Item {
    id: scene
    width: 800; height: 600

    Component { id: toolbar; IconAndTextToolbarButton { iconText: "settings"; text: "Settings" } }
    Component { id: tab; ToolbarTabButton { materialSymbol: "settings"; text: "Settings"; current: true } }
    Component { id: fab; FloatingActionButton { buttonText: "Create" } }
    Component { id: selection; SelectionGroupButton { buttonIcon: "add" } }
    Component { id: ripple; RippleButtonWithIcon { materialIcon: "settings" } }
    Component { id: optional; OptionalMaterialSymbol { icon: "settings"; property bool toggled: false } }
    Component { id: nav; NavigationRailButton { buttonIcon: "settings"; buttonText: "Settings"; toggled: false } }
    Component { id: rail; NavigationRailTabArray {
        width:160
        NavigationRailButton { objectName:"firstNav"; buttonIcon:"settings"; buttonText:"Settings"; toggled:true; showToggledHighlight:false; expanded:parent.parent.expanded }
        NavigationRailButton { objectName:"secondNav"; buttonIcon:"add"; buttonText:"Create"; toggled:false; showToggledHighlight:false; expanded:parent.parent.expanded }
    } }
    Component { id: host; Item { width:26; height:26 } }
    Component { id: baselineRow; Item {
        Text { id: caption; objectName: "caption"; text:"Label"; font.pixelSize:16; y:10 }
        MaterialSymbol { objectName:"glyph"; text:"add"; iconSize:22; anchors.baseline:caption.baseline }
    } }
    Component { id: symbol; MaterialSymbol { text: "add"; iconSize: 22; anchors.centerIn: parent } }

    TestCase {
        name: "UiAlignment"
        when: windowShown

        function labels(node, result) {
            for (let child of node.children) {
                if (!child.visible) continue;
                if (typeof child.text === "string" && child.text.length > 0)
                    result.push(child);
                else labels(child, result);
            }
            return result;
        }
        function bounds(button) {
            const items = labels(button.contentItem, []);
            verify(items.length > 0);
            let left = Infinity, right = -Infinity, top = Infinity, bottom = -Infinity;
            for (let item of items) {
                const p = item.mapToItem(button, 0, 0);
                left = Math.min(left, p.x); right = Math.max(right, p.x + item.width);
                top = Math.min(top, p.y); bottom = Math.max(bottom, p.y + item.height);
            }
            return {left, right, top, bottom};
        }
        function centered(button) {
            const b = bounds(button);
            fuzzyCompare((b.left + b.right) / 2, button.width / 2, 0.6);
            fuzzyCompare((b.top + b.bottom) / 2, button.height / 2, 0.6);
        }
        function test_toolbar_data() {
            return [{tag:"toolbar", component:toolbar}, {tag:"tab", component:tab}];
        }
        function test_toolbar(data) {
            const button = createTemporaryObject(data.component, scene, {width:240, height:48});
            verify(button);
            wait(20);
            centered(button);
            button.text = "";
            wait(20);
            centered(button);
            button.text = "A longer label";
            button.width = 360;
            wait(20);
            centered(button);
            button.toggled = true;
            button.enabled = false;
            wait(20);
            centered(button);
        }
        function test_fab() {
            const button = createTemporaryObject(fab, scene);
            verify(button);
            wait(20);
            compare(button.width, button.baseSize);
            const icon = labels(button.contentItem, []).filter(item => item.iconSize !== undefined)[0];
            fuzzyCompare(icon.mapToItem(button, icon.width / 2, 0).x, button.width / 2, 0.1);
            button.expanded = true;
            wait(220);
            centered(button);
            const b = bounds(button);
            const padding = (button.baseSize - icon.implicitWidth) / 2;
            fuzzyCompare(b.left, padding, 0.6);
            fuzzyCompare(button.width - b.right, padding, 0.6);
            button.width += 70;
            wait(20);
            centered(button);
            button.width = Qt.binding(() => button.implicitWidth);
            button.expanded = false;
            for (let i=0; i<12; i++) {
                wait(20);
                const iconLeft = icon.mapToItem(button, 0, 0).x;
                verify(iconLeft >= 0, "icon stays inside shrinking hitbox");
                verify(iconLeft + icon.width <= button.width);
            }
            compare(button.width, button.baseSize);
        }
        function test_icon_slots_have_height() {
            const item = createTemporaryObject(optional, scene);
            verify(item);
            wait(20);
            verify(item.implicitHeight > 0);
            verify(item.item.implicitHeight > 0);
            for (let component of [ripple, selection]) {
                const button = createTemporaryObject(component, scene);
                verify(button);
                wait(20);
                const slot = button.contentItem.children[0];
                verify(slot.implicitHeight > 0);
                centered(button);
            }
        }
        function test_selection_states_and_labels() {
            const button = createTemporaryObject(selection, scene, {width:240});
            verify(button);
            for (let label of ["", "Enabled", "Длинная подпись"]) {
                button.buttonText = label;
                button.toggled = !button.toggled;
                wait(20);
                centered(button);
            }
            const heightWithIcon = button.height;
            button.buttonIcon = "";
            wait(20);
            centered(button);
            compare(button.height, heightWithIcon);
            scene.LayoutMirroring.enabled = true;
            scene.LayoutMirroring.childrenInherit = true;
            wait(20);
            centered(button);
            scene.LayoutMirroring.enabled = false;
        }
        function test_navigation_caption_inside_hitbox() {
            const button = createTemporaryObject(nav, scene, {width:120});
            verify(button);
            wait(20);
            const b = bounds(button);
            verify(b.top >= 0, "caption group must not overflow the top");
            verify(b.bottom <= button.height, "caption group must not overflow the bottom");
            const glyph = labels(button.contentItem, []).filter(item => item.iconSize !== undefined)[0];
            const highlight = glyph.parent;
            const top = highlight.mapToItem(button, 0, 0).y;
            fuzzyCompare((top + b.bottom) / 2, button.height / 2, 0.6);
            button.expanded = true;
            wait(20);
            const expanded = bounds(button);
            fuzzyCompare((expanded.top + expanded.bottom) / 2, button.height / 2, 0.6);
        }
        function test_navigation_shared_highlight() {
            const array = createTemporaryObject(rail, scene);
            verify(array);
            for (let expanded of [false, true, false]) {
                array.expanded = expanded;
                for (let index of [0, 1]) {
                    array.currentIndex = index;
                    wait(220);
                    const button = findChild(array, index === 0 ? "firstNav" : "secondNav");
                    const glyph = labels(button.contentItem, []).filter(item => item.iconSize !== undefined)[0];
                    const highlight = findChild(array, "navigationSelectionHighlight");
                    const center = glyph.mapToItem(array, 0, glyph.height / 2).y;
                    fuzzyCompare(highlight.y + highlight.height / 2, center, 0.6);
                }
            }
        }
        function test_fractional_anchor_and_baseline() {
            const box = createTemporaryObject(host, scene);
            const glyph = createTemporaryObject(symbol, box);
            verify(glyph);
            wait(20);
            fuzzyCompare(glyph.x + glyph.width / 2, box.width / 2, 0.001);
            fuzzyCompare(glyph.y + glyph.height / 2, box.height / 2, 0.001);
            const row = createTemporaryObject(baselineRow, scene);
            verify(row);
            wait(20);
            const caption = findChild(row, "caption");
            const baselineGlyph = findChild(row, "glyph");
            fuzzyCompare(baselineGlyph.y + baselineGlyph.baselineOffset,
                caption.y + caption.baselineOffset, 0.001);
        }
    }
}
