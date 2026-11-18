import QtQuick
import QtQuick.Controls
import QtTest
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: test
    required property var host
    required property Item navigation
    required property Item viewport
    property int step: 0
    property var editor
    property var picker
    property var choices
    property string toolsUid
    property Item tipTarget
    TestCase { id: input; when: false }
    StyledToolTip {
        id: tip
        parent: test.tipTarget
        text: "A longer translated widget description ".repeat(8)
        extraVisibleCondition: false
        alternativeVisibleCondition: !!test.tipTarget
    }

    function check(ok, reason) {
        if (!ok) { console.log("CHECK_FAIL", step, reason); Qt.quit(); }
        return ok;
    }
    function findItem(item, matches) {
        if (matches(item)) return item;
        for (const child of item.children) {
            const result = findItem(child, matches);
            if (result) return result;
        }
        return null;
    }
    function clickPage(key) {
        const row = findItem(navigation, item => item.modelData?.key === key && item.buttonY !== undefined);
        input.mouseClick(row, row.width / 2, row.buttonY + navigation.itemHeight / 2);
    }
    function insidePage(popup) {
        const card = popup.background;
        const rect = card.mapToItem(viewport, 0, 0, card.width, card.height);
        return check(rect.x >= -1 && rect.y >= -1 && rect.x + rect.width <= viewport.width + 1
            && rect.y + rect.height <= viewport.height + 1, "card outside the page " + rect);
    }
    function scoped(popup) {
        if (!popup?.opened || !insidePage(popup)) return false;
        const shade = input.findChild(host.Overlay.overlay, "settingsPopupShade");
        if (!check(!!shade, "missing popup shade")) return false;
        const pane = host.currentPageItem.popupPane;
        const rect = shade.mapToItem(pane, 0, 0, shade.width, shade.height);
        if (!check(Math.abs(rect.x) < 1 && Math.abs(rect.y) < 1 &&
            Math.abs(rect.width - pane.width) < 1 && Math.abs(rect.height - pane.height) < 1, "shade outside the editor area " + rect)) return false;
        const mask = shade.parent;
        return check(!mask.contains(mask.mapFromItem(navigation, navigation.width / 2, 22))
            && mask.contains(mask.mapFromItem(pane, pane.width / 2, pane.height / 2)), "navigation intercepted");
    }
    Timer {
        interval: 310
        running: true
        repeat: true
        onTriggered: {
            const page = host.currentPageItem;
            if (!page || !Config.ready) return;
            switch (test.step) {
            case 0:
                Config.options.appearance.animationSpeed = 1;
                Config.options.bar.vertical = true;
                page.activateCatalogType("workspaces");
                test.editor = input.findChild(page, "barWidgetPopup");
                break;
            case 1:
                if (!test.scoped(test.editor)) return;
                host.width = 760;
                break;
            case 2:
                if (!test.scoped(test.editor)) return;
                if (!test.choices) {
                    const option = test.findItem(test.editor.contentItem, item => item.objectName === "bar-option-numberMap");
                    if (!test.check(!!option?.item?.dropdown, "missing number-style dropdown")) return;
                    const field = option.item.dropdown;
                    test.choices = input.findChild(field, "choicePopup");
                    input.mouseClick(field, field.width / 2, field.height / 2);
                    return;
                }
                if (!test.choices.opened) return;
                if (!test.insidePage(test.choices) || !test.check(!!test.choices.paneBounds, "unbounded choice list")) return;
                test.clickPage("sidebars");
                break;
            case 3:
                if (!test.check(host.currentPageData.key === "sidebars" && !test.editor.visible && !test.choices?.visible, "first click in the rail did not navigate")) return;
                host.width = 1100;
                break;
            case 4:
                test.toolsUid = SidebarLayout.insert(page.side, "tools", 0);
                input.findChild(page, "sidebarSettingsButton").clicked();
                test.editor = input.findChild(page, "sidebarSettingsPopup");
                break;
            case 5: {
                if (!test.scoped(test.editor)) return;
                const tile = test.findItem(page, item => item.uid === test.toolsUid && item.picked !== undefined);
                if (!test.check(!!tile, "missing sidebar preview tile")) return;
                input.mouseClick(tile, tile.width / 2, tile.height / 2);
                test.editor = input.findChild(page, "sidebarPartPopup");
                break;
            }
            case 6:
                if (!test.scoped(test.editor)) return;
                test.picker = input.findChild(test.editor, "sidebarAppPicker");
                if (!test.check(!!test.picker, "missing nested picker")) return;
                test.picker.open();
                break;
            case 7:
                if (!test.scoped(test.picker)) return;
                input.keyClick(Qt.Key_Escape);
                break;
            case 8:
                if (!test.check(!test.picker.visible && test.editor.opened, "Escape closed the wrong editor")) return;
                test.picker.open();
                break;
            case 9:
                test.clickPage("bar");
                break;
            case 10:
                if (!test.check(host.currentPageData.key === "bar" && !test.picker?.visible && !test.editor.visible,
                    "nested editor blocked a click in the expanded menu or survived navigation")) return;
                Config.options.bar.bottom = true;
                host.width = 760;
                navigation.expandOverride = true;
                page.activateCatalogType("workspaces");
                test.editor = input.findChild(page, "barWidgetPopup");
                break;
            case 11: {
                if (!test.scoped(test.editor)) return;
                const area = page.popupPane;
                if (!test.check(area.width >= Math.min(400, viewport.width) && test.editor.width >= Math.min(368, viewport.width - 32),
                    "right-edge widget editor squeezed by the expanded navigation")) return;
                if (!test.tipTarget) {
                    test.tipTarget = test.findItem(test.editor.contentItem, item => item.symbol === "close" && item.tip !== undefined);
                    return;
                }
                if (!tip.opened) return;
                const tipRect = tip.contentItem.mapToItem(area, 0, 0, tip.contentItem.width, tip.contentItem.height);
                if (!test.check(!!tip.paneBounds && tipRect.x >= 0 && tipRect.x + tipRect.width <= area.width + 1, "tooltip spilled out of the editor")) return;
                test.tipTarget = null;
                Config.options.bar.vertical = false;
                break;
            }
            case 12:
                page.activateCatalogType("workspaces");
                break;
            case 13:
                if (!test.scoped(test.editor)) return;
                input.mouseClick(navigation, 36, 22);
                input.keyClick(Qt.Key_B);
                break;
            case 14:
                if (!test.check(host.searching, "search lost the first keystroke " + [navigation.expanded, navigation.searchText, host.activeFocusItem])) return;
                if (test.editor.visible) return;
                console.log("DRIVER_PASS"); Qt.quit(); return;
            }
            test.step++;
        }
    }
    Timer { interval: 16000; running: true; onTriggered: test.check(false, "timeout"); }
}
