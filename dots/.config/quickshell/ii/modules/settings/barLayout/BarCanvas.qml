import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.settings.preview

/**
 * The bar drawn at its real edge over a strip of the screen (the wallpaper at that edge), where its
 * widgets are arranged: drag them between the parts of the bar, click one to select it (its card is
 * shown by the page), and move the whole bar to another edge with the picker beside it. Short enough
 * to stay pinned above the page's tabs. The bar keeps a readable size rather than the screen's scale;
 * its style (background, islands, pills, roundness) follows the settings.
 */
Item {
    id: root
    required property string orientation
    required property var layout
    required property var zoneInfo
    property string selectedUid: ""
    property string draggedUid: ""
    property bool dragging: false
    property string addZone: ""

    signal selectRequested(string uid)
    signal chipDragStarted(var item, real sceneX, real sceneY, real offsetX, real offsetY)
    signal chipDragMoved(real sceneX, real sceneY)
    signal chipDragEnded(real sceneX, real sceneY)
    signal addRequested(string zone)

    readonly property bool vertical: root.orientation === "vertical"
    readonly property var bar: Config.options.bar
    readonly property string edge: root.vertical ? (root.bar.bottom ? "right" : "left") : (root.bar.bottom ? "bottom" : "top")
    readonly property bool islands: root.bar.style.islands
    readonly property bool floating: root.bar.cornerStyle === 1 || root.islands
    readonly property bool hasBackground: root.bar.showBackground && !root.islands
    readonly property string pillStyle: root.bar.borderless ? "none" : root.bar.style.pillStyle
    readonly property real thickness: 44
    readonly property real margin: root.floating ? 10 : 0
    readonly property real styleRadius: root.bar.style.radius >= 0 ? root.bar.style.radius : Appearance.rounding.windowRounding
    readonly property real sliver: root.vertical ? 104 : 86 // The bit of desktop beside the bar, for the hint and the edge picker
    readonly property real barDepth: root.thickness + root.margin * 2
    readonly property var selected: root.selectedUid.length > 0 ? BarLayout.find(root.layout, root.selectedUid) : null
    readonly property bool hovered: barHover.hovered

    readonly property var zoneItems: [startZone, centerStartZone, centerZone, centerEndZone, endZone]

    function zoneItem(zone) {
        return root.zoneItems.find(item => item.zone === zone) ?? null;
    }

    // The part of the bar nearest to a scene point while dragging, or null when it's off the bar
    function zoneAt(sceneX, sceneY) {
        let best = null;
        let bestDistance = 48;
        for (const zone of root.zoneItems) {
            const distance = zone.distanceTo(sceneX, sceneY, 36);
            if (distance < bestDistance) {
                best = zone;
                bestDistance = distance;
            }
        }
        return best;
    }

    function chipFor(uid) {
        for (const zone of root.zoneItems) {
            const chip = zone.chips().find(chip => chip.itemData.uid === uid);
            if (chip) return chip;
        }
        return null;
    }

    implicitHeight: root.vertical ? 0 : root.barDepth + root.sliver
    implicitWidth: root.vertical ? root.barDepth + root.sliver : 0

    MiniScreen {
        id: screen
        anchors.fill: parent
        crop: root.edge

        TapHandler { // A click on the empty screen closes the card
            onTapped: root.selectRequested("")
        }

        Item {
            id: barArea
            readonly property real length: (root.vertical ? screen.height : screen.width) - root.margin * 2
            x: root.edge === "right" ? screen.width - root.thickness - root.margin : root.margin
            y: root.edge === "bottom" ? screen.height - root.thickness - root.margin : root.margin
            width: root.vertical ? root.thickness : barArea.length
            height: root.vertical ? barArea.length : root.thickness

            Behavior on x {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
            Behavior on y {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }

            HoverHandler {
                id: barHover
            }

            Rectangle { // The bar itself
                anchors.fill: parent
                visible: root.hasBackground
                color: Appearance.colors.colBarBackground
                radius: root.bar.cornerStyle === 1 ? Math.min(root.styleRadius, root.thickness / 2) : 0
                border.width: root.bar.cornerStyle === 1 ? 1 : 0
                border.color: Appearance.colors.colLayer0Border
            }

            // A busy bar shrinks to fit, like the real one gives up space before running off the screen
            readonly property real fit: {
                const along = item => root.vertical ? item.implicitHeight : item.implicitWidth;
                const needed = Math.max(along(startZone), along(endZone)) * 2 + along(centerRow) + 40;
                return Math.min(1, barArea.length / Math.max(1, needed));
            }

            Zone {
                id: startZone
                zone: "start"
                scale: barArea.fit
                transformOrigin: root.vertical ? Item.Top : Item.Left
                x: root.vertical ? (parent.width - width) / 2 : 8
                y: root.vertical ? 8 : (parent.height - height) / 2
            }

            Grid {
                id: centerRow
                columns: root.vertical ? 1 : 3
                spacing: 6
                scale: barArea.fit
                verticalItemAlignment: Grid.AlignVCenter
                horizontalItemAlignment: Grid.AlignHCenter
                x: (parent.width - width) / 2
                y: (parent.height - height) / 2
                Zone {
                    id: centerStartZone
                    zone: "centerStart"
                }
                Zone {
                    id: centerZone
                    zone: "center"
                }
                Zone {
                    id: centerEndZone
                    zone: "centerEnd"
                }
            }

            Zone {
                id: endZone
                zone: "end"
                scale: barArea.fit
                transformOrigin: root.vertical ? Item.Bottom : Item.Right
                x: root.vertical ? (parent.width - width) / 2 : parent.width - width - 8
                y: root.vertical ? parent.height - height - 8 : (parent.height - height) / 2
            }
        }

        // The desktop beside the bar: the hint and the edge picker
        Item {
            id: sliverArea
            x: root.edge === "left" ? root.barDepth : 0
            y: root.edge === "top" ? root.barDepth : 0
            width: root.vertical ? screen.width - root.barDepth : screen.width
            height: root.vertical ? screen.height : screen.height - root.barDepth

            Rectangle {
                visible: !root.vertical && root.selected === null && !root.dragging
                anchors {
                    verticalCenter: parent.verticalCenter
                    left: parent.left
                    leftMargin: 14
                    right: edgePicker.left
                    rightMargin: 14
                }
                implicitHeight: hint.implicitHeight + 14
                radius: height / 2
                color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.2)
                StyledText {
                    id: hint
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, parent.width - 24)
                    elide: Text.ElideRight
                    text: Translation.tr("Drag widgets to move them · click one to set it up")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer0
                }
            }

            Rectangle {
                id: edgePicker
                anchors {
                    right: root.vertical ? undefined : parent.right
                    rightMargin: 14
                    horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
                    verticalCenter: root.vertical ? undefined : parent.verticalCenter
                    bottom: root.vertical ? parent.bottom : undefined
                    bottomMargin: 14
                }
                implicitWidth: edgeGrid.implicitWidth + 8
                implicitHeight: edgeGrid.implicitHeight + 8
                radius: Appearance.rounding.full
                color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.15)

                Grid {
                    id: edgeGrid
                    anchors.centerIn: parent
                    columns: root.vertical ? 2 : 4
                    spacing: 2
                    Repeater {
                        model: [
                            { "edge": "top", "icon": "vertical_align_top", "tip": Translation.tr("Move the bar to the top") },
                            { "edge": "bottom", "icon": "vertical_align_bottom", "tip": Translation.tr("Move the bar to the bottom") },
                            { "edge": "left", "icon": "align_horizontal_left", "tip": Translation.tr("Move the bar to the left") },
                            { "edge": "right", "icon": "align_horizontal_right", "tip": Translation.tr("Move the bar to the right") },
                        ]
                        delegate: RippleButton {
                            id: edgeButton
                            required property var modelData
                            readonly property bool current: modelData.edge === root.edge
                            implicitWidth: 32
                            implicitHeight: 32
                            buttonRadius: Appearance.rounding.full
                            toggled: edgeButton.current
                            colBackground: "transparent"
                            colBackgroundHover: Appearance.colors.colLayer1Hover
                            onClicked: {
                                if (edgeButton.current) return;
                                root.selectRequested("");
                                Config.options.bar.vertical = modelData.edge === "left" || modelData.edge === "right";
                                Config.options.bar.bottom = modelData.edge === "bottom" || modelData.edge === "right";
                            }
                            contentItem: MaterialSymbol {
                                horizontalAlignment: Text.AlignHCenter
                                text: edgeButton.modelData.icon
                                iconSize: 19
                                color: edgeButton.current ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
                            }
                            StyledToolTip {
                                text: edgeButton.modelData.tip
                            }
                        }
                    }
                }
            }
        }
    }

    // A part of the bar, wired to the layout and to this canvas
    component Zone: CanvasZone {
        id: zoneItem
        items: root.layout.zones[zoneItem.zone] ?? []
        vertical: root.vertical
        islands: root.islands
        pillStyle: root.pillStyle
        islandRadius: Math.min(root.styleRadius, 16)
        islandColor: Appearance.colors.colBarBackground
        selectedUid: root.selectedUid
        draggedUid: root.draggedUid
        highlighted: root.addZone === zoneItem.zone
        // Empty parts open up while dragging; every part offers "+" while the pointer is on the bar
        showSlot: root.dragging ? zoneItem.items.length === 0 : root.hovered
        onChipClicked: item => root.selectRequested(root.selectedUid === item.uid ? "" : item.uid)
        onChipDragStarted: (item, sceneX, sceneY, offsetX, offsetY) => root.chipDragStarted(item, sceneX, sceneY, offsetX, offsetY)
        onChipDragMoved: (sceneX, sceneY) => root.chipDragMoved(sceneX, sceneY)
        onChipDragEnded: (sceneX, sceneY) => root.chipDragEnded(sceneX, sceneY)
        onAddRequested: root.addRequested(zoneItem.zone)
    }
}
