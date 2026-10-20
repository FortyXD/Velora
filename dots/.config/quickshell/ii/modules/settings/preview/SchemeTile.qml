import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * A choice shown as a small drawn scheme with a label under it. Children are drawn inside the
 * scheme's frame; `ink` and `faint` are the colors to draw with, so a selected tile lights up.
 */
RippleButton {
    id: root
    property string label
    property bool selected: false
    property real frameWidth: 96
    property real frameHeight: 60
    readonly property color ink: root.selected ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
    readonly property color faint: ColorUtils.transparentize(root.ink, 0.6)
    default property alias picture: frame.data

    implicitWidth: Math.max(root.frameWidth + 20, labelText.implicitWidth + 16)
    implicitHeight: root.frameHeight + labelText.implicitHeight + 26
    buttonRadius: Appearance.rounding.normal
    colBackground: root.selected ? Appearance.colors.colSecondaryContainer : "transparent"
    colBackgroundHover: root.selected ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover

    readonly property bool settingsSearchable: true
    property string searchText: root.label

    contentItem: ColumnLayout {
        spacing: 6
        Rectangle {
            id: frame
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: root.frameWidth
            implicitHeight: root.frameHeight
            radius: 8
            color: Appearance.colors.colLayer3
            border.width: root.selected ? 2 : 0
            border.color: Appearance.colors.colPrimary
            clip: true
        }
        StyledText {
            id: labelText
            Layout.alignment: Qt.AlignHCenter
            text: root.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
        }
    }
}
