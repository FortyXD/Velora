import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * The quick toggles laid out as in the sidebar, to rearrange: drag one and the others make room,
 * click it to make it wide or narrow (tiles style), × takes it out, and the list below puts one back.
 */
ColumnLayout {
    id: root
    readonly property bool classic: Config.options.sidebar.quickToggles.style === "classic"
    readonly property int columns: Config.options.sidebar.quickToggles.android.columns
    readonly property var used: root.classic ? SidebarLayout.classicToggles().map(type => ({ "type": type, "size": 1 }))
        : SidebarLayout.androidToggles().map(t => ({ "type": t.type, "size": Math.min(t.size, root.columns) }))
    readonly property var unused: SidebarCatalog.toggles.filter(t => (!root.classic || t.classic) && !root.used.some(u => u.type === t.type))
    readonly property real tileSpacing: 6
    readonly property real tileHeight: root.classic ? 52 : 52
    readonly property real cell: root.classic ? 52 : Math.floor((grid.width - root.tileSpacing * (root.columns - 1)) / root.columns)
    readonly property int perRow: root.classic ? Math.max(1, Math.floor((grid.width + root.tileSpacing) / (root.cell + root.tileSpacing))) : root.columns

    // Dragging: the toggle follows the pointer, the others take the order it would make
    property string dragType: ""
    property int dragTarget: -1 // Index among the toggles without the dragged one
    property point dragPos: Qt.point(0, 0)
    readonly property var previewList: {
        if (root.dragType.length === 0 || root.dragTarget < 0) return root.used;
        let others = root.used.filter(t => t.type !== root.dragType);
        others.splice(root.dragTarget, 0, root.used.find(t => t.type === root.dragType));
        return others;
    }
    readonly property var places: root.layout(root.previewList)

    // Rows like the sidebar's: a toggle that doesn't fit starts the next row
    function layout(list) {
        let result = {};
        let x = 0;
        let row = 0;
        let used = 0;
        for (const t of list) {
            if (used + t.size > root.perRow && used > 0) {
                row++;
                used = 0;
            }
            const width = root.cell * t.size + root.tileSpacing * (t.size - 1);
            result[t.type] = { "x": used * (root.cell + root.tileSpacing), "y": row * (root.tileHeight + root.tileSpacing), "width": width };
            used += t.size;
        }
        result.height = list.length === 0 ? 0 : (row + 1) * (root.tileHeight + root.tileSpacing) - root.tileSpacing;
        return result;
    }
    // The order that puts the dragged toggle's slot nearest the pointer
    function targetFor(type, point) {
        const dragged = root.used.find(t => t.type === type);
        const others = root.used.filter(t => t.type !== type);
        let best = 0;
        let bestDistance = 1e9;
        for (let i = 0; i <= others.length; i++) {
            let list = others.slice();
            list.splice(i, 0, dragged);
            const place = root.layout(list)[type];
            const distance = Math.hypot(place.x + place.width / 2 - point.x, place.y + root.tileHeight / 2 - point.y);
            if (distance < bestDistance) {
                bestDistance = distance;
                best = i;
            }
        }
        return best;
    }

    Layout.fillWidth: true
    Layout.leftMargin: 12
    Layout.rightMargin: 12
    spacing: 10

    readonly property bool settingsSearchable: true
    property string searchText: Translation.tr("Quick toggles order size add remove")

    Item {
        id: grid
        Layout.fillWidth: true
        implicitHeight: Math.max(root.tileHeight, root.places.height ?? 0)
        Behavior on implicitHeight {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        Repeater {
            model: root.used
            delegate: Rectangle {
                id: tile
                required property var modelData
                readonly property var info: SidebarCatalog.toggle(modelData.type)
                readonly property bool dragging: root.dragType === modelData.type
                readonly property var place: root.places[modelData.type] ?? { "x": 0, "y": 0, "width": root.cell }
                x: tile.dragging ? root.dragPos.x - tileArea.grabOffset.x : tile.place.x
                y: tile.dragging ? root.dragPos.y - tileArea.grabOffset.y : tile.place.y
                width: root.classic ? root.cell : tile.place.width
                height: root.tileHeight
                Behavior on x {
                    enabled: !tile.dragging
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on y {
                    enabled: !tile.dragging
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on width {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                radius: root.classic ? width / 2 : (modelData.size > 1 ? height / 2 : 16)
                color: tileArea.containsMouse || tile.dragging ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainer
                border.width: tile.dragging ? 2 : 0
                border.color: Appearance.colors.colPrimary
                z: tile.dragging ? 5 : 1
                scale: tile.dragging ? 1.06 : 1
                Behavior on scale {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: root.classic || tile.modelData.size === 1 ? 0 : 16
                        rightMargin: root.classic || tile.modelData.size === 1 ? 0 : 28
                    }
                    spacing: 8
                    MaterialSymbol {
                        Layout.alignment: root.classic || tile.modelData.size === 1 ? Qt.AlignCenter : Qt.AlignVCenter
                        text: tile.info?.icon ?? "help"
                        iconSize: 22
                        fill: 1
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                    StyledText {
                        visible: !root.classic && tile.modelData.size > 1
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: tile.info?.name ?? tile.modelData.type
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                }

                MouseArea {
                    id: tileArea
                    anchors.fill: parent
                    hoverEnabled: true
                    preventStealing: true // The settings page must not scroll away with the drag
                    cursorShape: tile.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    property point start
                    property point grabOffset
                    onPressed: mouse => {
                        start = mapToItem(grid, mouse.x, mouse.y);
                        grabOffset = Qt.point(start.x - tile.x, start.y - tile.y);
                    }
                    onPositionChanged: mouse => {
                        if (!pressed) return;
                        const p = mapToItem(grid, mouse.x, mouse.y);
                        if (!tile.dragging && Math.hypot(p.x - start.x, p.y - start.y) < 5) return;
                        root.dragPos = p;
                        root.dragTarget = root.targetFor(tile.modelData.type, p);
                        root.dragType = tile.modelData.type;
                    }
                    onReleased: {
                        // Reset first: any change rebuilds the tiles
                        const dragged = tile.dragging;
                        const type = tile.modelData.type;
                        const target = root.dragTarget;
                        const classic = root.classic;
                        root.dragType = "";
                        root.dragTarget = -1;
                        if (dragged) {
                            if (classic) SidebarLayout.moveClassicToggle(type, target);
                            else SidebarLayout.moveAndroidToggle(type, target);
                        } else if (!classic) {
                            SidebarLayout.resizeAndroidToggle(type);
                        }
                    }
                    onCanceled: {
                        root.dragType = "";
                        root.dragTarget = -1;
                    }
                }

                // Take it out
                RippleButton {
                    visible: (tileArea.containsMouse || hovered) && !tile.dragging
                    anchors {
                        right: parent.right
                        top: parent.top
                        rightMargin: root.classic ? -4 : 4
                        topMargin: root.classic ? -4 : (parent.height - height) / 2
                    }
                    implicitWidth: 20
                    implicitHeight: 20
                    buttonRadius: 10
                    colBackground: Appearance.colors.colErrorContainer
                    colBackgroundHover: Appearance.colors.colErrorContainerHover
                    onClicked: {
                        if (root.classic) SidebarLayout.toggleClassicToggle(tile.modelData.type);
                        else SidebarLayout.removeAndroidToggle(tile.modelData.type);
                    }
                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        text: "close"
                        iconSize: 14
                        color: Appearance.colors.colOnErrorContainer
                    }
                }

                StyledToolTip {
                    extraVisibleCondition: tileArea.containsMouse && !tile.dragging
                    text: `${tile.info?.name ?? ""}\n` + (root.classic ? Translation.tr("Drag to move") : Translation.tr("Click: wide or narrow • drag to move"))
                }
            }
        }
    }

    StyledText {
        visible: root.unused.length > 0
        text: Translation.tr("Add")
        font.pixelSize: Appearance.font.pixelSize.small
        font.weight: Font.Medium
        color: Appearance.colors.colOnLayer2
    }
    Flow {
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: root.unused
            delegate: RippleButton {
                id: addChip
                required property var modelData
                implicitHeight: 34
                leftPadding: 10
                rightPadding: 12
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer3
                colBackgroundHover: Appearance.colors.colLayer3Hover
                onClicked: {
                    if (root.classic) SidebarLayout.toggleClassicToggle(modelData.type);
                    else SidebarLayout.addAndroidToggle(modelData.type);
                }
                contentItem: RowLayout {
                    spacing: 6
                    MaterialSymbol {
                        text: "add"
                        iconSize: 16
                        color: Appearance.colors.colOnLayer3
                    }
                    MaterialSymbol {
                        text: addChip.modelData.icon
                        iconSize: 16
                        fill: 1
                        color: Appearance.colors.colOnLayer3
                    }
                    StyledText {
                        text: addChip.modelData.name
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer3
                    }
                }
            }
        }
    }
}
