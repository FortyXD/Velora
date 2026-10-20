import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.settings.preview

/**
 * The bar drawn at its real edge over a miniature of the screen, where its widgets are arranged:
 * drag them between the parts of the bar, click one to set it up in a card beside it, and move
 * the whole bar to another edge with the arrows. The bar keeps a readable size rather than the
 * screen's scale; its style (background, islands, pills, roundness) follows the settings.
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

    implicitHeight: screen.implicitHeight

    MiniScreen {
        id: screen
        anchors.fill: parent

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

        // Arrows that move the bar to another edge
        Repeater {
            model: [
                { "edge": "top", "icon": "arrow_upward", "tip": Translation.tr("Move the bar to the top") },
                { "edge": "bottom", "icon": "arrow_downward", "tip": Translation.tr("Move the bar to the bottom") },
                { "edge": "left", "icon": "arrow_back", "tip": Translation.tr("Move the bar to the left") },
                { "edge": "right", "icon": "arrow_forward", "tip": Translation.tr("Move the bar to the right") },
            ]
            delegate: RippleButton {
                id: edgeButton
                required property var modelData
                readonly property bool side: modelData.edge === "left" || modelData.edge === "right"
                visible: modelData.edge !== root.edge
                opacity: screenHover.hovered || edgeButton.hovered ? 1 : 0.55
                implicitWidth: 34
                implicitHeight: 34
                buttonRadius: Appearance.rounding.full
                colBackground: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.15)
                colBackgroundHover: Appearance.colors.colLayer1Hover
                x: modelData.edge === "left" ? 14 : modelData.edge === "right" ? screen.width - width - 14 : (screen.width - width) / 2
                y: modelData.edge === "top" ? 14 : modelData.edge === "bottom" ? screen.height - height - 14 : (screen.height - height) / 2
                onClicked: {
                    root.selectRequested("");
                    Config.options.bar.vertical = edgeButton.side;
                    Config.options.bar.bottom = modelData.edge === "bottom" || modelData.edge === "right";
                }
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    text: edgeButton.modelData.icon
                    iconSize: 20
                    color: Appearance.colors.colOnLayer0
                }
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                StyledToolTip {
                    text: edgeButton.modelData.tip
                }
            }
        }

        HoverHandler {
            id: screenHover
        }

        // Hint in the middle of the screen while nothing is selected
        Rectangle {
            visible: root.selected === null && !root.dragging
            anchors.centerIn: parent
            implicitWidth: hint.implicitWidth + 28
            implicitHeight: hint.implicitHeight + 16
            radius: height / 2
            color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.2)
            StyledText {
                id: hint
                anchors.centerIn: parent
                text: Translation.tr("Drag widgets to move them · click one to set it up")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer0
            }
        }
    }

    // Where the selected chip is, for placing its card; found once things have been laid out
    property point selectedPoint: Qt.point(0, 0)
    function updateSelectedPoint() {
        const chip = root.selected ? root.chipFor(root.selectedUid) : null;
        if (chip) root.selectedPoint = chip.mapToItem(root, chip.width / 2, chip.height / 2);
    }
    onSelectedUidChanged: Qt.callLater(root.updateSelectedPoint)
    onLayoutChanged: Qt.callLater(root.updateSelectedPoint)
    onWidthChanged: Qt.callLater(root.updateSelectedPoint)

    StyledRectangularShadow {
        target: inspector
        visible: inspector.visible
    }

    WidgetInspector {
        id: inspector
        readonly property real gap: 14
        visible: root.selected !== null && !root.dragging
        orientation: root.orientation
        selected: root.selected
        zoneInfo: root.zoneInfo
        maximumHeight: root.vertical ? root.height - 20 : root.height - root.thickness - root.margin - inspector.gap - 10
        x: root.edge === "left" ? barArea.x + root.thickness + inspector.gap
            : root.edge === "right" ? barArea.x - width - inspector.gap
            : Math.max(10, Math.min(root.width - width - 10, root.selectedPoint.x - width / 2))
        y: root.edge === "top" ? barArea.y + root.thickness + inspector.gap
            : root.edge === "bottom" ? barArea.y - height - inspector.gap
            : Math.max(10, Math.min(root.height - height - 10, root.selectedPoint.y - height / 2))
        onCloseRequested: root.selectRequested("")
        onSelectRequested: uid => root.selectRequested(uid)
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
