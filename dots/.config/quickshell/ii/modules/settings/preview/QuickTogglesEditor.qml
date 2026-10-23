import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * The quick toggles as they are laid out in the sidebar, to rearrange: drag one to move it, click it to
 * make it wide or narrow (Android style), × takes it out, and the toggles below put one back.
 */
ColumnLayout {
    id: root
    readonly property bool classic: Config.options.sidebar.quickToggles.style === "classic"
    readonly property int columns: Config.options.sidebar.quickToggles.android.columns
    readonly property var used: root.classic ? SidebarLayout.classicToggles().map(type => ({ "type": type, "size": 1 }))
        : SidebarLayout.androidToggles().map(t => ({ "type": t.type, "size": Math.min(t.size, root.columns) }))
    readonly property var unused: SidebarCatalog.toggles.filter(t => (!root.classic || t.classic) && !root.used.some(u => u.type === t.type))
    readonly property real tileSpacing: 6
    readonly property real cell: root.classic ? 52 : Math.floor((grid.width - root.tileSpacing * (root.columns - 1)) / root.columns)

    property string dragType: ""
    property point dragOffset: Qt.point(0, 0)
    property int dropIndex: -1

    Layout.fillWidth: true
    Layout.leftMargin: 12
    Layout.rightMargin: 12
    spacing: 10

    readonly property bool settingsSearchable: true
    property string searchText: Translation.tr("Quick toggles order size add remove")

    Flow {
        id: grid
        Layout.fillWidth: true
        Layout.preferredHeight: implicitHeight
        spacing: root.tileSpacing

        Repeater {
            id: tiles
            model: root.used
            delegate: Rectangle {
                id: tile
                required property var modelData
                required property int index
                readonly property var info: SidebarCatalog.toggle(modelData.type)
                readonly property bool dragging: root.dragType === modelData.type
                width: root.classic ? root.cell : root.cell * modelData.size + root.tileSpacing * (modelData.size - 1)
                height: root.classic ? root.cell : 52
                radius: root.classic ? width / 2 : (modelData.size > 1 ? height / 2 : 16)
                color: tileArea.containsMouse || tile.dragging ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colPrimaryContainer
                border.width: root.dropIndex === tile.index && !tile.dragging ? 2 : 0
                border.color: Appearance.colors.colPrimary
                z: tile.dragging ? 5 : 1
                opacity: tile.dragging ? 0.85 : 1
                transform: Translate {
                    x: tile.dragging ? root.dragOffset.x : 0
                    y: tile.dragging ? root.dragOffset.y : 0
                }

                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: root.classic || tile.modelData.size === 1 ? 0 : 14
                        rightMargin: root.classic || tile.modelData.size === 1 ? 0 : 26
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
                    cursorShape: tile.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                    property point start
                    onPressed: mouse => start = mapToItem(grid, mouse.x, mouse.y)
                    onPositionChanged: mouse => {
                        if (!pressed) return;
                        const p = mapToItem(grid, mouse.x, mouse.y);
                        if (!tile.dragging && Math.hypot(p.x - start.x, p.y - start.y) < 6) return;
                        root.dragType = tile.modelData.type;
                        root.dragOffset = Qt.point(p.x - start.x, p.y - start.y);
                        // The tile nearest to the pointer is where it goes
                        let best = -1;
                        let bestDistance = 1e9;
                        for (let i = 0; i < tiles.count; i++) {
                            const other = tiles.itemAt(i);
                            if (!other) continue;
                            const d = Math.hypot(other.x + other.width / 2 - p.x, other.y + other.height / 2 - p.y);
                            if (d < bestDistance) {
                                bestDistance = d;
                                best = i;
                            }
                        }
                        root.dropIndex = best;
                    }
                    onReleased: {
                        // Reset first: any change rebuilds the tiles
                        const dragged = tile.dragging;
                        const type = tile.modelData.type;
                        const target = root.dropIndex;
                        const moved = target >= 0 && target !== tile.index;
                        const classic = root.classic;
                        root.dragType = "";
                        root.dragOffset = Qt.point(0, 0);
                        root.dropIndex = -1;
                        if (dragged && moved) {
                            if (classic) SidebarLayout.moveClassicToggle(type, target);
                            else SidebarLayout.moveAndroidToggle(type, target);
                        } else if (!dragged && !classic) {
                            SidebarLayout.resizeAndroidToggle(type);
                        }
                    }
                }

                // Take it out
                RippleButton {
                    visible: tileArea.containsMouse || hovered
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
