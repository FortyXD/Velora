import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * One part of the bar on the canvas: its widgets as chips, grouped into pills or islands like on the
 * real bar. While something is dragged, `dropIndex` marks where it would land, and an empty part
 * shows a slot to drop on. A "+" slot on its inner side asks to add a widget here.
 */
Item {
    id: root
    required property string zone
    property var items: []
    property bool vertical: false
    property bool islands: false
    property string pillStyle: "filled"
    property string selectedUid: ""
    property string draggedUid: ""
    property int dropIndex: -1
    property bool showSlot: false
    property bool highlighted: false // The part new widgets are added to
    property color contentColor: Appearance.colors.colOnLayer0
    property color pillColor: Appearance.colors.colLayer1
    property color islandColor: Appearance.colors.colLayer0
    property real islandRadius: 12
    // The slot sits toward the center of the bar
    readonly property bool slotFirst: root.zone === "end" || root.zone === "centerEnd"

    signal chipClicked(var item)
    signal chipDragStarted(var item, real sceneX, real sceneY, real offsetX, real offsetY)
    signal chipDragMoved(real sceneX, real sceneY)
    signal chipDragEnded(real sceneX, real sceneY)
    signal addRequested()

    readonly property var segments: BarLayoutUtils.segments(root.items, root.islands)

    implicitWidth: line.implicitWidth
    implicitHeight: line.implicitHeight

    // Chips in order, without the one being dragged: drop indexes count without it
    function chips() {
        let result = [];
        for (let i = 0; i < segmentRepeater.count; i++) {
            const segment = segmentRepeater.itemAt(i);
            if (!segment) continue;
            for (let j = 0; j < segment.chipCount; j++) {
                const chip = segment.chipAt(j);
                if (chip && chip.itemData.uid !== root.draggedUid) result.push(chip);
            }
        }
        return result;
    }

    // How far a scene point is from this part, along the bar; Infinity when it's off the bar
    function distanceTo(sceneX, sceneY, reach) {
        const p = root.mapFromItem(null, sceneX, sceneY);
        const along = root.vertical ? p.y : p.x;
        const across = root.vertical ? p.x : p.y;
        const length = root.vertical ? root.height : root.width;
        const thickness = root.vertical ? root.width : root.height;
        if (across < -reach || across > thickness + reach) return Infinity;
        return along < 0 ? -along : along > length ? along - length : 0;
    }

    function indexAt(sceneX, sceneY) {
        const list = root.chips();
        for (let i = 0; i < list.length; i++) {
            const center = list[i].mapToItem(null, list[i].width / 2, list[i].height / 2);
            if ((root.vertical ? sceneY : sceneX) < (root.vertical ? center.y : center.x)) return i;
        }
        return list.length;
    }

    Grid {
        id: line
        columns: root.vertical ? 1 : 99
        spacing: 4
        verticalItemAlignment: Grid.AlignVCenter
        horizontalItemAlignment: Grid.AlignHCenter

        AddSlot {
            visible: root.showSlot && root.slotFirst
        }

        Repeater {
            id: segmentRepeater
            model: root.segments
            delegate: Rectangle {
                id: segment
                required property var modelData
                readonly property bool pill: modelData.pill
                readonly property real padding: segment.pill ? 3 : 0
                readonly property int chipCount: chipRepeater.count
                function chipAt(index) {
                    return chipRepeater.itemAt(index);
                }

                implicitWidth: chipLine.implicitWidth + segment.padding * 2
                implicitHeight: chipLine.implicitHeight + segment.padding * 2
                radius: root.islands ? root.islandRadius : Math.min(width, height) / 2
                color: !segment.pill ? "transparent"
                    : root.islands ? root.islandColor
                    : root.pillStyle === "filled" ? root.pillColor : "transparent"
                border.width: segment.pill && (root.islands || root.pillStyle === "outlined") ? 1 : 0
                border.color: Appearance.colors.colOutlineVariant

                Grid {
                    id: chipLine
                    anchors.centerIn: parent
                    columns: root.vertical ? 1 : 99
                    spacing: 2
                    verticalItemAlignment: Grid.AlignVCenter
                    horizontalItemAlignment: Grid.AlignHCenter
                    Repeater {
                        id: chipRepeater
                        model: segment.modelData.items
                        delegate: CanvasChip {
                            required property var modelData
                            itemData: modelData
                            vertical: root.vertical
                            contentColor: root.contentColor
                            selected: root.selectedUid === modelData.uid
                            dimmed: root.draggedUid === modelData.uid
                            onClicked: root.chipClicked(modelData)
                            onDragStarted: (sceneX, sceneY, offsetX, offsetY) => root.chipDragStarted(modelData, sceneX, sceneY, offsetX, offsetY)
                            onDragMoved: (sceneX, sceneY) => root.chipDragMoved(sceneX, sceneY)
                            onDragEnded: (sceneX, sceneY) => root.chipDragEnded(sceneX, sceneY)
                        }
                    }
                }
            }
        }

        AddSlot {
            visible: root.showSlot && !root.slotFirst
        }
    }

    Rectangle { // Where a dragged widget would land
        visible: root.dropIndex >= 0
        readonly property var list: root.dropIndex >= 0 ? root.chips() : []
        readonly property var before: root.dropIndex < list.length ? list[root.dropIndex] : null
        readonly property var after: list.length > 0 && root.dropIndex >= list.length ? list[list.length - 1] : null
        readonly property point spot: before ? before.mapToItem(root, 0, 0)
            : after ? after.mapToItem(root, after.width, after.height)
            : Qt.point(root.vertical ? 0 : root.width / 2, root.vertical ? root.height / 2 : 0)
        x: root.vertical ? (root.width - width) / 2 : spot.x - (before ? 3 : 0) - 1
        y: root.vertical ? spot.y - (before ? 3 : 0) - 1 : (root.height - height) / 2
        width: root.vertical ? 30 : 3
        height: root.vertical ? 3 : 30
        radius: 2
        color: Appearance.colors.colPrimary
        z: 5
    }

    component AddSlot: Rectangle {
        id: slot
        width: 26
        height: 26
        radius: 13
        color: slotMouse.containsMouse ? ColorUtils.transparentize(root.contentColor, 0.8) : "transparent"
        border.width: 1
        border.color: root.highlighted ? Appearance.colors.colPrimary : ColorUtils.transparentize(root.contentColor, 0.5)
        MaterialSymbol {
            anchors.centerIn: parent
            text: "add"
            iconSize: 16
            color: root.highlighted ? Appearance.colors.colPrimary : root.contentColor
        }
        MouseArea {
            id: slotMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.addRequested()
        }
        StyledToolTip {
            alternativeVisibleCondition: slotMouse.containsMouse
            extraVisibleCondition: false
            text: Translation.tr("Add a widget here")
        }
    }
}
