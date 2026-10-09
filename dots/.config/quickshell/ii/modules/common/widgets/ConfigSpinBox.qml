import qs.modules.common.widgets
import qs.modules.common
import QtQuick
import QtQuick.Layouts

/**
 * Settings row: icon tile, title with optional description, and a spin box.
 */
RowLayout {
    id: root
    property string text: ""
    property string icon
    property string description: ""
    property alias value: spinBoxWidget.value
    property alias stepSize: spinBoxWidget.stepSize
    property alias from: spinBoxWidget.from
    property alias to: spinBoxWidget.to

    readonly property bool settingsSearchable: true
    property string searchText: `${root.text} ${root.description}`

    spacing: 12
    Layout.fillWidth: true
    Layout.leftMargin: 12
    Layout.rightMargin: 12
    Layout.topMargin: 5
    Layout.bottomMargin: 5
    opacity: root.enabled ? 1 : 0.4

    ConfigIconTile {
        icon: root.icon ?? ""
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        spacing: 1
        StyledText {
            id: labelWidget
            Layout.fillWidth: true
            text: root.text
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer2
        }
        StyledText {
            visible: root.description.length > 0
            Layout.fillWidth: true
            text: root.description
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }

    StyledSpinBox {
        id: spinBoxWidget
        Layout.fillWidth: false
        Layout.alignment: Qt.AlignVCenter
        radius: Appearance.rounding.full
        colBackground: Appearance.colors.colLayer3
        colButtonHover: Appearance.colors.colLayer3Hover
        colButtonActive: Appearance.colors.colLayer3Active
    }
}
