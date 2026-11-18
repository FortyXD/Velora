import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * One part of the bar on the canvas: its widgets as chips, grouped into pills or islands like on the
 * real bar. Each chip leaves room for the insertion slot on its active side.
 */
Item {
    id: root
    required property string zone
    readonly property string zoneName: zone
    property var editGuide
    readonly property alias emptySlot: emptyGap
    property var items: []
    property bool vertical: false
    property bool islands: false
    property string pillStyle: "filled"
    property string selectedUid: ""
    property string draggedUid: ""
    property color contentColor: Appearance.colors.colOnLayer0
    property color pillColor: Appearance.colors.colLayer1
    property color islandColor: Appearance.colors.colLayer0
    property real islandRadius: 12

    signal chipClicked(var item)
    signal chipDragStarted(var item, real sceneX, real sceneY, real offsetX, real offsetY)
    signal chipDragMoved(real sceneX, real sceneY)
    signal chipDragEnded(real sceneX, real sceneY)

    readonly property var segments: BarLayoutUtils.segments(root.items, root.islands)

    implicitWidth: Math.max(root.items.length ? 0 : 26, line.implicitWidth)
    implicitHeight: Math.max(root.items.length ? 0 : 26, line.implicitHeight)

    function orderedHosts() {
        let result = [];
        for (let i = 0; i < segmentRepeater.count; i++) {
            const segment = segmentRepeater.itemAt(i);
            if (!segment) continue;
            for (let j = 0; j < segment.chipCount; j++) {
                const chip = segment.chipAt(j);
                if (chip) result.push(chip);
            }
        }
        return result;
    }

    BarInsertionSlot {
        id: emptyGap
        guide: root.editGuide
        vertical: root.vertical
    }

    Grid {
        id: line
        columns: root.vertical ? 1 : 99
        spacing: 4
        verticalItemAlignment: Grid.AlignVCenter
        horizontalItemAlignment: Grid.AlignHCenter

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
                    return chipRepeater.itemAt(index)?.chip ?? null;
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
                        delegate: Item {
                            id: wrapper
                            required property var modelData
                            readonly property alias chip: widget
                            implicitWidth: widget.implicitWidth + (root.vertical ? 0 : widget.editSlot.amount)
                            implicitHeight: widget.implicitHeight + (root.vertical ? widget.editSlot.amount : 0)
                            CanvasChip {
                                id: widget
                                itemData: wrapper.modelData
                                editGuide: root.editGuide
                                x: root.vertical ? 0 : editSlot.before
                                y: root.vertical ? editSlot.before : 0
                                vertical: root.vertical
                                contentColor: root.contentColor
                                selected: root.selectedUid === wrapper.modelData.uid
                                dimmed: root.draggedUid === wrapper.modelData.uid
                                onClicked: root.chipClicked(wrapper.modelData)
                                onDragStarted: (sceneX, sceneY, offsetX, offsetY) => root.chipDragStarted(wrapper.modelData, sceneX, sceneY, offsetX, offsetY)
                                onDragMoved: (sceneX, sceneY) => root.chipDragMoved(sceneX, sceneY)
                                onDragEnded: (sceneX, sceneY) => root.chipDragEnded(sceneX, sceneY)
                            }
                        }
                    }
                }
            }
        }

    }
}
