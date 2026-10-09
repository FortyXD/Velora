import qs.modules.common.widgets
import qs.modules.common
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

/**
 * Settings row: icon tile, title with optional description, and a switch.
 * The whole row toggles `checked`.
 */
RippleButton {
    id: root
    property string buttonIcon
    property string description: ""
    property alias iconSize: iconTile.iconSize
    // When false the row only emits clicked(): bind `checked` and write the value in onClicked,
    // which keeps the binding alive when the same option is shown elsewhere too
    property bool autoToggle: true

    readonly property bool settingsSearchable: true
    property string searchText: `${root.text} ${root.description}`

    Layout.fillWidth: true
    implicitHeight: Math.max(46, contentItem.implicitHeight + 10 * 2)
    leftPadding: 12
    rightPadding: 12
    buttonRadius: Appearance.rounding.small
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colRipple: Appearance.colors.colLayer2Active
    font.pixelSize: Appearance.font.pixelSize.small

    onClicked: if (root.autoToggle) checked = !checked

    contentItem: RowLayout {
        spacing: 12
        ConfigIconTile {
            id: iconTile
            icon: root.buttonIcon ?? ""
            active: root.checked
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 1
            StyledText {
                id: labelWidget
                Layout.fillWidth: true
                text: root.text
                font: root.font
                wrapMode: Text.Wrap
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
        StyledSwitch {
            id: switchWidget
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: false
            checkable: false // The row owns the state, so the switch never breaks its binding
            down: root.down
            checked: root.checked
            onClicked: root.clicked()
        }
    }
}
