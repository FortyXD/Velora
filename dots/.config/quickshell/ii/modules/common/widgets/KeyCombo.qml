import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.services
import qs.modules.common.widgets

/**
 * A key combo drawn as keycaps, e.g. [Super] [Shift] [S].
 * Labels follow the cheat sheet options (Super symbol, modifier, mouse and F-key symbols).
 */
Row {
    id: root
    property var mods: []
    property string key: ""
    property var labels: KeyUtils.comboLabels(root.mods, root.key)
    property real pixelSize: Config.options?.cheatsheet.fontSize.key || Appearance.font.pixelSize.smaller
    property bool showPlus: Config.options?.cheatsheet.splitButtons ?? false
    property color keyColor: Appearance.colors.colLayer3
    property color edgeColor: ColorUtils.mix(Appearance.colors.colOutlineVariant, root.keyColor, 0.6)
    property color textColor: Appearance.colors.colOnLayer2

    spacing: 3

    Repeater {
        model: root.labels
        delegate: Row {
            id: keyItem
            required property string modelData
            required property int index
            spacing: root.spacing

            StyledText {
                visible: root.showPlus && keyItem.index > 0
                anchors.verticalCenter: parent.verticalCenter
                text: "+"
                font.pixelSize: root.pixelSize
                color: Appearance.colors.colSubtext
            }

            Rectangle { // Edge, shows under the face like the side of a key
                implicitWidth: Math.max(face.implicitHeight, label.implicitWidth + 12)
                implicitHeight: face.implicitHeight + 2
                radius: 6
                color: root.edgeColor

                Rectangle {
                    id: face
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                    }
                    implicitHeight: label.implicitHeight + 6
                    radius: 6
                    color: root.keyColor

                    StyledText {
                        id: label
                        anchors.centerIn: parent
                        text: keyItem.modelData
                        font.pixelSize: root.pixelSize
                        font.weight: Font.Medium
                        color: root.textColor
                    }
                }
            }
        }
    }
}
