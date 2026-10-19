import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.bar.edit
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * The bar's content built from a layout object: background, then the start and end zones at the
 * screen edges and the three center zones in a centered row. With `balanceCenter`, the zones on
 * both sides of the center get the same width, so the center stays in the middle of the screen.
 */
Item {
    id: root

    property bool vertical: false
    property var layoutData: vertical ? BarLayout.vertical : BarLayout.horizontal
    readonly property string orientation: vertical ? "vertical" : "horizontal"
    property bool editing: false
    property var controller: null // BarEditController of this bar window, for edit mode

    property var screen: root.QsWindow.window?.screen
    readonly property int tier: (Appearance.sizes.barHellaShortenScreenWidthThreshold >= screen?.width) ? 2
        : (Appearance.sizes.barShortenScreenWidthThreshold >= screen?.width) ? 1 : 0
    readonly property int centerSideModuleWidth: (tier == 2) ? Appearance.sizes.barCenterSideModuleWidthHellaShortened
        : (tier == 1) ? Appearance.sizes.barCenterSideModuleWidthShortened : Appearance.sizes.barCenterSideModuleWidth
    readonly property bool balanceCenter: layoutData?.balanceCenter ?? false
    // Both sides of the center grow together when either needs more room
    readonly property real centerSideWidth: Math.max(centerSideModuleWidth, centerStartZone.rigidWidth + 12, centerEndZone.rigidWidth + 12)

    readonly property var zones: layoutData?.zones ?? ({})
    readonly property var actions: layoutData?.actions ?? ({})
    readonly property var zoneItems: [startZone, centerStartZone, centerZone, centerEndZone, endZone]

    // The widget under a point of this view, or null
    function hostAt(x, y) {
        for (const zone of root.zoneItems) {
            for (const host of zone.orderedHosts()) {
                const p = host.mapFromItem(root, x, y);
                if (p.x >= 0 && p.y >= 0 && p.x <= host.width && p.y <= host.height) return host;
            }
        }
        return null;
    }

    // Where a widget dropped at x (view coordinates) goes: nearest zone, then between its widgets.
    // The index doesn't count the widget being moved; `x` is where to draw the marker.
    function dropTargetAt(x, y, excludeUid) {
        let best = null;
        let bestDistance = Infinity;
        for (const zone of root.zoneItems) {
            if (!zone.visible) continue;
            const left = zone.mapToItem(root, 0, 0).x;
            const distance = x < left ? left - x : (x > left + zone.width ? x - left - zone.width : 0);
            if (distance < bestDistance) {
                best = zone;
                bestDistance = distance;
            }
        }
        if (!best) return null;
        const hosts = best.orderedHosts().filter(host => host.uid !== excludeUid);
        let index = hosts.length;
        for (let i = 0; i < hosts.length; i++) {
            if (x < hosts[i].mapToItem(root, hosts[i].width / 2, 0).x) {
                index = i;
                break;
            }
        }
        let markerX;
        if (hosts.length === 0) markerX = best.mapToItem(root, best.width / 2, 0).x;
        else if (index < hosts.length) markerX = hosts[index].mapToItem(root, 0, 0).x - 3;
        else markerX = hosts[hosts.length - 1].mapToItem(root, hosts[hosts.length - 1].width, 0).x + 3;
        return { "zone": best.zoneName, "index": index, "x": markerX };
    }

    function startEditing() {
        GlobalStates.barEditScreen = root.screen?.name ?? "";
        GlobalStates.barEditing = true;
    }

    function openSettings(page) {
        Quickshell.execDetached(["bash", "-c", `QS_SETTINGS_PAGE=${page} qs -p '${Quickshell.shellPath("settings.qml")}'`]);
    }

    function openMenu(zone, x, y) {
        const point = zone.mapToItem(null, x, y);
        barMenu.openAt(root.QsWindow.window, point.x, point.y, [
            { "text": Translation.tr("Edit the bar"), "icon": "edit", "action": () => root.startEditing() },
            { "type": "separator" },
            { "text": Translation.tr("Bar layout settings"), "icon": "view_column", "action": () => root.openSettings("barLayout") },
            { "text": Translation.tr("Bar settings"), "icon": "settings", "action": () => root.openSettings("bar") },
        ]);
    }

    function openEditMenu(host, x, y) {
        const point = root.mapToItem(null, x, y);
        let entries = [];
        if (host) {
            const item = host.itemData;
            entries = [
                { "text": Translation.tr("In a pill"), "checked": !!item.pill, "icon": "pill",
                  "action": () => BarLayout.setItem(root.orientation, item.uid, { "pill": item.pill ? null : true, "pillBreak": null }) },
                { "text": Translation.tr("Hide when narrow"), "checked": (item.hideAt ?? 0) > 0, "icon": "compress",
                  "action": () => BarLayout.setItem(root.orientation, item.uid, { "hideAt": (item.hideAt ?? 0) > 0 ? null : 1 }) },
                { "text": Translation.tr("Remove"), "icon": "delete",
                  "action": () => {
                      BarLayout.remove(root.orientation, item.uid);
                      GlobalStates.barEditSelection = "";
                  } },
                { "type": "separator" },
            ];
        } else {
            entries = [
                { "text": Translation.tr("Undo"), "icon": "undo", "enabled": BarLayout.canUndo, "action": () => BarLayout.undo() },
                { "text": Translation.tr("Reset to default"), "icon": "restart_alt", "action": () => BarLayout.reset(root.orientation) },
                { "type": "separator" },
            ];
        }
        entries.push({ "text": Translation.tr("Done"), "icon": "check", "action": () => GlobalStates.barEditing = false });
        barMenu.openAt(root.QsWindow.window, point.x, point.y, entries);
    }

    ContextMenuPopup {
        id: barMenu
        openEdge: Config.options.bar.bottom ? Edges.Top : Edges.Bottom
    }

    MouseArea { // Shift + right click anywhere opens the bar menu, even over widgets
        anchors.fill: parent
        z: 50
        visible: !root.editing
        acceptedButtons: Qt.RightButton
        onPressed: mouse => {
            if (!(mouse.modifiers & Qt.ShiftModifier)) {
                mouse.accepted = false;
                return;
            }
            const zone = root.zoneItems.find(zone => {
                const p = zone.mapFromItem(root, mouse.x, mouse.y);
                return zone.visible && p.x >= 0 && p.x <= zone.width;
            }) ?? startZone;
            const p = zone.mapFromItem(root, mouse.x, mouse.y);
            root.openMenu(zone, p.x, p.y);
        }
    }

    Loader {
        anchors.fill: parent
        z: 100
        active: root.editing && root.controller !== null
        sourceComponent: BarEditOverlay {
            view: root
            controller: root.controller
        }
    }

    BarWidgetFactory {
        id: factory
    }

    component CenterSeparator: Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: 1
        implicitHeight: Appearance.sizes.baseBarHeight / 3
        color: Appearance.colors.colOutlineVariant
    }

    // Background shadow
    Loader {
        active: Config.options.bar.showBackground && Config.options.bar.cornerStyle === 1 && Config.options.bar.floatStyleShadow
        anchors.fill: barBackground
        sourceComponent: StyledRectangularShadow {
            anchors.fill: undefined // The loader's anchors act on this, and this should not have any anchor
            target: barBackground
        }
    }
    // Background
    Rectangle {
        id: barBackground
        anchors {
            fill: parent
            margins: Config.options.bar.cornerStyle === 1 ? (Appearance.sizes.hyprlandGapsOut) : 0 // idk why but +1 is needed
        }
        color: Config.options.bar.showBackground ? Appearance.colors.colLayer0 : "transparent"
        radius: Config.options.bar.cornerStyle === 1 ? Appearance.rounding.windowRounding : 0
        border.width: Config.options.bar.cornerStyle === 1 ? 1 : 0
        border.color: Appearance.colors.colLayer0Border
    }

    BarZone {
        id: startZone
        editing: root.editing
        onMenuRequested: (x, y) => root.openMenu(startZone, x, y)
        zoneName: "start"
        items: root.zones.start ?? []
        actions: root.actions.start ?? ({})
        factory: factory
        tier: root.tier
        anchors {
            top: parent.top
            bottom: parent.bottom
            left: parent.left
            right: middleRow.left
        }
        outerSide: "left"
        outerPadding: Appearance.rounding.screenRounding
        innerPadding: Appearance.rounding.screenRounding
        spacing: 10
    }

    Row {
        id: middleRow
        anchors {
            top: parent.top
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
        }
        spacing: 4

        BarZone {
            id: centerStartZone
            editing: root.editing
            onMenuRequested: (x, y) => root.openMenu(centerStartZone, x, y)
            zoneName: "centerStart"
            items: root.zones.centerStart ?? []
            actions: root.actions.centerStart ?? ({})
            factory: factory
            tier: root.tier
            height: parent.height
            fixedLength: root.balanceCenter ? root.centerSideWidth : -1
            visible: hasContent || root.balanceCenter || root.editing
            align: "end"
        }

        CenterSeparator {
            visible: Config.options.bar.borderless && centerStartZone.hasContent && centerZone.hasContent
        }

        BarZone {
            id: centerZone
            editing: root.editing
            onMenuRequested: (x, y) => root.openMenu(centerZone, x, y)
            zoneName: "center"
            items: root.zones.center ?? []
            actions: root.actions.center ?? ({})
            factory: factory
            tier: root.tier
            height: parent.height
            visible: hasContent || root.editing
        }

        CenterSeparator {
            visible: Config.options.bar.borderless && centerZone.hasContent && centerEndZone.hasContent
        }

        BarZone {
            id: centerEndZone
            editing: root.editing
            onMenuRequested: (x, y) => root.openMenu(centerEndZone, x, y)
            zoneName: "centerEnd"
            items: root.zones.centerEnd ?? []
            actions: root.actions.centerEnd ?? ({})
            factory: factory
            tier: root.tier
            height: parent.height
            fixedLength: root.balanceCenter ? root.centerSideWidth : -1
            visible: hasContent || root.balanceCenter || root.editing
        }
    }

    BarZone {
        id: endZone
        editing: root.editing
        onMenuRequested: (x, y) => root.openMenu(endZone, x, y)
        zoneName: "end"
        items: root.zones.end ?? []
        actions: root.actions.end ?? ({})
        factory: factory
        tier: root.tier
        anchors {
            top: parent.top
            bottom: parent.bottom
            left: middleRow.right
            right: parent.right
        }
        outerSide: "right"
        outerPadding: Appearance.rounding.screenRounding
        innerPadding: 4
        spacing: 5
        align: "end"
    }
}
