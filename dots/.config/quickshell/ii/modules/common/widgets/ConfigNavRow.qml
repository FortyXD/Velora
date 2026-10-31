import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * Row inside a settings card that leads somewhere: icon, title, optional value text and a chevron.
 */
RippleButton {
    id: root
    property string buttonIcon: ""
    property string title: ""
    property string description: ""
    property string valueText: ""
    property string trailingIcon: "chevron_right"
    property real trailingIconRotation: 0
    property color tileColor: "transparent" // See ConfigIconTile

    readonly property bool settingsSearchable: true
    property string searchText: `${root.title} ${root.description}`

    Layout.fillWidth: true
    implicitHeight: Math.max(46, contentItem.implicitHeight + 10 * 2)
    leftPadding: 12
    rightPadding: 10
    buttonRadius: Appearance.rounding.small
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colRipple: Appearance.colors.colLayer2Active

    contentItem: RowLayout {
        spacing: 12
        ConfigIconTile {
            icon: root.buttonIcon
            tileColor: root.tileColor
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 1
            StyledText {
                Layout.fillWidth: true
                text: root.title
                elide: Text.ElideRight
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
        StyledText {
            visible: root.valueText.length > 0
            Layout.maximumWidth: 220
            text: root.valueText
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }
        MaterialSymbol {
            text: root.trailingIcon
            rotation: root.trailingIconRotation
            Behavior on rotation {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            iconSize: 20
            color: Appearance.colors.colSubtext
            transform: Translate {
                x: root.hovered ? 2 : 0
                Behavior on x {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }
    }
}
