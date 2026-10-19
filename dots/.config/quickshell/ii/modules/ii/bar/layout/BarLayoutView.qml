import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.bar.edit
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell

/**
 * The bar's content built from a layout object: background, then the start and end zones at the
 * screen edges and the three center zones in a centered row (a column for a vertical bar). With
 * `balanceCenter`, the zones on both sides of the center get the same length, so the center stays
 * in the middle of the screen.
 */
Item {
    id: root

    property bool vertical: false
    property var layoutData: vertical ? BarLayout.vertical : BarLayout.horizontal
    readonly property string orientation: vertical ? "vertical" : "horizontal"
    property bool editing: false
    property var controller: null // BarEditController of this bar window, for edit mode

    property var screen: root.QsWindow.window?.screen
    readonly property int tier: vertical ? 0
        : (Appearance.sizes.barHellaShortenScreenWidthThreshold >= screen?.width) ? 2
        : (Appearance.sizes.barShortenScreenWidthThreshold >= screen?.width) ? 1 : 0
    readonly property int centerSideModuleWidth: (tier == 2) ? Appearance.sizes.barCenterSideModuleWidthHellaShortened
        : (tier == 1) ? Appearance.sizes.barCenterSideModuleWidthShortened : Appearance.sizes.barCenterSideModuleWidth
    readonly property bool balanceCenter: layoutData?.balanceCenter ?? false
    // Both sides of the center grow together when either needs more room
    readonly property real centerSideWidth: Math.max(vertical ? 0 : centerSideModuleWidth, centerStartZone.rigidLength + 12, centerEndZone.rigidLength + 12)
    // Balancing only while everything still fits; otherwise the center gives up its symmetry
    // so the outer zones keep their widgets on screen
    readonly property real barLength: vertical ? height : width
    readonly property real startNeeds: startZone.rigidLength + startZone.startPadding + startZone.endPadding
    readonly property real endNeeds: endZone.rigidLength + endZone.startPadding + endZone.endPadding
    // A centered block leaves the same room on both sides: each side of the center may be as wide as
    // the theme wants, minus what the fuller outer zone needs, but never narrower than its own widgets
    readonly property real sideRoom: Math.floor((barLength - (vertical ? centerZone.implicitHeight : centerZone.implicitWidth) - 8) / 2
        - Math.max(startNeeds, endNeeds))
    readonly property real sideMinimum: Math.max(centerStartZone.rigidLength, centerEndZone.rigidLength) + 12
    readonly property bool balanced: balanceCenter && sideRoom >= sideMinimum
    readonly property real balancedSide: Math.max(sideMinimum, Math.min(centerSideWidth, sideRoom))
    // The center stays in the middle when it can, and otherwise moves just enough for the outer zones
    function middlePosition(length) {
        const ideal = (barLength - length) / 2;
        const lowest = startNeeds;
        const highest = barLength - endNeeds - length;
        return highest < lowest ? ideal : Math.max(lowest, Math.min(ideal, highest));
    }

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

    // Position of an item's start, middle or end along the bar, in view coordinates
    function along(item, fraction) {
        const p = item.mapToItem(root, item.width * fraction, item.height * fraction);
        return root.vertical ? p.y : p.x;
    }

    // Where a widget dropped at a point (view coordinates) goes: nearest zone, then between its
    // widgets. The index doesn't count the widget being moved; `pos` is where to draw the marker.
    function dropTargetAt(x, y, excludeUid) {
        const pos = root.vertical ? y : x;
        let best = null;
        let bestDistance = Infinity;
        for (const zone of root.zoneItems) {
            if (!zone.visible) continue;
            const start = root.along(zone, 0);
            const end = root.along(zone, 1);
            const distance = pos < start ? start - pos : (pos > end ? pos - end : 0);
            if (distance < bestDistance) {
                best = zone;
                bestDistance = distance;
            }
        }
        if (!best) return null;
        const hosts = best.orderedHosts().filter(host => host.uid !== excludeUid);
        let index = hosts.length;
        for (let i = 0; i < hosts.length; i++) {
            if (pos < root.along(hosts[i], 0.5)) {
                index = i;
                break;
            }
        }
        let marker;
        if (hosts.length === 0) marker = root.along(best, 0.5);
        else if (index < hosts.length) marker = root.along(hosts[index], 0) - 3;
        else marker = root.along(hosts[hosts.length - 1], 1) + 3;
        return { "zone": best.zoneName, "index": index, "pos": marker };
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
        openEdge: root.vertical ? (Config.options.bar.bottom ? Edges.Left : Edges.Right)
            : (Config.options.bar.bottom ? Edges.Top : Edges.Bottom)
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
            const pos = root.vertical ? mouse.y : mouse.x;
            const zone = root.zoneItems.find(zone => zone.visible && pos >= root.along(zone, 0) && pos <= root.along(zone, 1)) ?? startZone;
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

    // Soft shadow under the zones' contents, so text stays readable on a see-through bar
    component ZoneShadow: MultiEffect {
        shadowEnabled: true
        shadowBlur: 0.5
        shadowColor: ColorUtils.transparentize(Appearance.m3colors.m3shadow, 0.35)
        shadowVerticalOffset: 1
        shadowHorizontalOffset: 0
    }
    readonly property bool textShadow: Config.options.bar.style.textShadow

    // Centered by the Grid's item alignment: anchors aren't allowed inside a Grid and would stop it
    component CenterSeparator: Rectangle {
        implicitWidth: root.vertical ? Appearance.sizes.baseVerticalBarWidth / 3 : 1
        implicitHeight: root.vertical ? 1 : Appearance.sizes.baseBarHeight / 3
        color: Appearance.colors.colOutlineVariant
    }

    readonly property bool drawsBackground: Config.options.bar.showBackground && !Config.options.bar.style.islands
    readonly property real edgePadding: Config.options.bar.style.edgePadding >= 0 ? Config.options.bar.style.edgePadding
        : vertical ? (Appearance.sizes.baseVerticalBarWidth - 30) / 2 + Appearance.sizes.hyprlandGapsOut : Appearance.rounding.screenRounding

    // Background shadow
    Loader {
        active: root.drawsBackground && Config.options.bar.cornerStyle === 1 && Config.options.bar.floatStyleShadow
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
            margins: Config.options.bar.cornerStyle === 1 ? Appearance.sizes.barFloatMargin : 0
        }
        color: root.drawsBackground ? Appearance.colors.colBarBackground : "transparent"
        radius: Config.options.bar.cornerStyle === 1 ? (Config.options.bar.style.radius >= 0 ? Config.options.bar.style.radius : Appearance.rounding.windowRounding) : 0
        border.width: Config.options.bar.cornerStyle === 1 && root.drawsBackground ? 1 : 0
        border.color: Appearance.colors.colLayer0Border
    }

    BarZone {
        id: startZone
        clip: true // Widgets that don't fit stay inside the zone instead of running off the screen
        layer.enabled: root.textShadow
        layer.effect: ZoneShadow {}
        editing: root.editing
        onMenuRequested: (x, y) => root.openMenu(startZone, x, y)
        zoneName: "start"
        items: root.zones.start ?? []
        actions: root.actions.start ?? ({})
        factory: factory
        tier: root.tier
        vertical: root.vertical
        anchors {
            top: parent.top
            left: parent.left
            bottom: root.vertical ? middleRow.top : parent.bottom
            right: root.vertical ? parent.right : middleRow.left
        }
        outerSide: root.vertical ? "top" : "left"
        outerPadding: root.edgePadding
        innerPadding: Appearance.rounding.screenRounding
        spacing: 10
    }

    Grid {
        id: middleRow
        anchors {
            top: root.vertical ? undefined : parent.top
            bottom: root.vertical ? undefined : parent.bottom
            left: root.vertical ? parent.left : undefined
            right: root.vertical ? parent.right : undefined
        }
        x: root.vertical ? 0 : root.middlePosition(width)
        y: root.vertical ? root.middlePosition(height) : 0
        flow: root.vertical ? Grid.TopToBottom : Grid.LeftToRight
        rows: root.vertical ? 5 : 1
        columns: root.vertical ? 1 : 5
        spacing: 4
        verticalItemAlignment: Grid.AlignVCenter
        horizontalItemAlignment: Grid.AlignHCenter

        BarZone {
            id: centerStartZone
            layer.enabled: root.textShadow
            layer.effect: ZoneShadow {}
            editing: root.editing
            onMenuRequested: (x, y) => root.openMenu(centerStartZone, x, y)
            zoneName: "centerStart"
            items: root.zones.centerStart ?? []
            actions: root.actions.centerStart ?? ({})
            factory: factory
            tier: root.tier
            vertical: root.vertical
            width: root.vertical ? middleRow.width : implicitWidth
            height: root.vertical ? implicitHeight : middleRow.height
            fixedLength: root.balanced ? root.balancedSide : -1
            visible: hasContent || root.balanced || root.editing
            align: "end"
        }

        CenterSeparator {
            visible: Config.options.bar.borderless && centerStartZone.hasContent && centerZone.hasContent
        }

        BarZone {
            id: centerZone
            layer.enabled: root.textShadow
            layer.effect: ZoneShadow {}
            editing: root.editing
            onMenuRequested: (x, y) => root.openMenu(centerZone, x, y)
            zoneName: "center"
            items: root.zones.center ?? []
            actions: root.actions.center ?? ({})
            factory: factory
            tier: root.tier
            vertical: root.vertical
            width: root.vertical ? middleRow.width : implicitWidth
            height: root.vertical ? implicitHeight : middleRow.height
            visible: hasContent || root.editing
        }

        CenterSeparator {
            visible: Config.options.bar.borderless && centerZone.hasContent && centerEndZone.hasContent
        }

        BarZone {
            id: centerEndZone
            layer.enabled: root.textShadow
            layer.effect: ZoneShadow {}
            editing: root.editing
            onMenuRequested: (x, y) => root.openMenu(centerEndZone, x, y)
            zoneName: "centerEnd"
            items: root.zones.centerEnd ?? []
            actions: root.actions.centerEnd ?? ({})
            factory: factory
            tier: root.tier
            vertical: root.vertical
            width: root.vertical ? middleRow.width : implicitWidth
            height: root.vertical ? implicitHeight : middleRow.height
            fixedLength: root.balanced ? root.balancedSide : -1
            visible: hasContent || root.balanced || root.editing
        }
    }

    BarZone {
        id: endZone
        clip: true // Widgets that don't fit stay inside the zone instead of running off the screen
        layer.enabled: root.textShadow
        layer.effect: ZoneShadow {}
        editing: root.editing
        onMenuRequested: (x, y) => root.openMenu(endZone, x, y)
        zoneName: "end"
        items: root.zones.end ?? []
        actions: root.actions.end ?? ({})
        factory: factory
        tier: root.tier
        vertical: root.vertical
        anchors {
            top: root.vertical ? middleRow.bottom : parent.top
            left: root.vertical ? parent.left : middleRow.right
            bottom: parent.bottom
            right: parent.right
        }
        outerSide: root.vertical ? "bottom" : "right"
        outerPadding: root.vertical ? Appearance.rounding.screenRounding : root.edgePadding
        innerPadding: 4
        spacing: root.vertical ? 4 : 5
        align: "end"
    }
}
