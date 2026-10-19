import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * One bar zone in the layout editor: its name, its widgets as chips and a button to add more.
 * While something is dragged over it, `dropIndex` marks where it would land.
 */
Rectangle {
    id: root

    required property string zone
    property string title
    property string icon
    property var items: []
    property string selectedUid: ""
    property string draggedUid: ""
    property int dropIndex: -1
    property bool highlighted: false

    signal chipClicked(var item)
    signal chipDragStarted(var item, real sceneX, real sceneY, real offsetX, real offsetY)
    signal chipDragMoved(real sceneX, real sceneY)
    signal chipDragEnded(real sceneX, real sceneY)
    signal addRequested()

    // Chips other than the dragged one, in order: indexes count without the dragged item
    readonly property var otherChips: {
        let result = [];
        for (let i = 0; i < chipRepeater.count; i++) {
            const chip = chipRepeater.itemAt(i);
            if (chip && chip.itemData.uid !== root.draggedUid) result.push(chip);
        }
        return result;
    }

    function containsScene(sceneX, sceneY) {
        const p = root.mapFromItem(null, sceneX, sceneY);
        return p.x >= 0 && p.y >= 0 && p.x <= root.width && p.y <= root.height;
    }

    // Where a chip dropped at this scene position would go
    function indexAt(sceneX, sceneY) {
        const p = chipFlow.mapFromItem(null, sceneX, sceneY);
        for (let i = 0; i < root.otherChips.length; i++) {
            const chip = root.otherChips[i];
            if (p.y < chip.y) return i;
            if (p.y <= chip.y + chip.height && p.x < chip.x + chip.width / 2) return i;
        }
        return root.otherChips.length;
    }

    implicitHeight: Math.max(56, laneRow.implicitHeight + 16)
    radius: Appearance.rounding.normal
    color: root.highlighted ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
    border.width: root.dropIndex >= 0 ? 2 : 0
    border.color: Appearance.colors.colPrimary

    RowLayout {
        id: laneRow
        anchors {
            fill: parent
            leftMargin: 12
            rightMargin: 8
            topMargin: 8
            bottomMargin: 8
        }
        spacing: 10

        RowLayout {
            Layout.fillWidth: false
            Layout.preferredWidth: 128
            Layout.maximumWidth: 128
            Layout.alignment: Qt.AlignTop | Qt.AlignLeft
            Layout.topMargin: 8
            spacing: 6
            MaterialSymbol {
                text: root.icon
                iconSize: 18
                color: Appearance.colors.colSubtext
            }
            StyledText {
                Layout.fillWidth: true
                text: root.title
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: Math.max(36, chipFlow.implicitHeight)

            StyledText {
                visible: root.items.length === 0
                anchors.verticalCenter: parent.verticalCenter
                text: Translation.tr("Empty: drag widgets here")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            Flow {
                id: chipFlow
                width: parent.width
                spacing: 6

                Repeater {
                    id: chipRepeater
                    model: root.items
                    delegate: WidgetChip {
                        required property var modelData
                        readonly property var itemData: modelData
                        readonly property var meta: BarWidgetCatalog.get(modelData.type)
                        label: meta?.name ?? modelData.type
                        icon: meta?.icon ?? "help"
                        unknown: meta === null
                        pill: !!modelData.pill
                        hideAt: modelData.hideAt ?? 0
                        selected: root.selectedUid === modelData.uid
                        dimmed: root.draggedUid === modelData.uid
                        onClicked: root.chipClicked(modelData)
                        onDragStarted: (sceneX, sceneY, offsetX, offsetY) => root.chipDragStarted(modelData, sceneX, sceneY, offsetX, offsetY)
                        onDragMoved: (sceneX, sceneY) => root.chipDragMoved(sceneX, sceneY)
                        onDragEnded: (sceneX, sceneY) => root.chipDragEnded(sceneX, sceneY)
                    }
                }
            }

            Rectangle { // Where a dragged widget would land
                visible: root.dropIndex >= 0
                readonly property var anchorChip: root.dropIndex < root.otherChips.length ? root.otherChips[root.dropIndex] : null
                readonly property var lastChip: root.otherChips.length > 0 ? root.otherChips[root.otherChips.length - 1] : null
                x: anchorChip ? anchorChip.x - 4 : lastChip ? lastChip.x + lastChip.width + 2 : 0
                y: anchorChip ? anchorChip.y : lastChip ? lastChip.y : 0
                width: 3
                height: 36
                radius: 2
                color: Appearance.colors.colPrimary
            }
        }

        RippleButton {
            Layout.alignment: Qt.AlignTop
            implicitWidth: 36
            implicitHeight: 36
            buttonRadius: Appearance.rounding.full
            colBackgroundHover: Appearance.colors.colLayer2Hover
            onClicked: root.addRequested()
            contentItem: MaterialSymbol {
                text: "add"
                iconSize: 20
                horizontalAlignment: Text.AlignHCenter
                color: Appearance.colors.colOnLayer2
            }
            StyledToolTip {
                text: Translation.tr("Add a widget here")
            }
        }
    }
}
