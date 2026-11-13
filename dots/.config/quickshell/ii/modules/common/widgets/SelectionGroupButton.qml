import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.services
import qs.modules.common
import qs.modules.common.widgets

GroupButton {
    id: root
    horizontalPadding: 12
    verticalPadding: 3
    bounce: false
    property string buttonIcon
    property bool leftmost: false
    property bool rightmost: false
    // Same shape whether selected or not: pill ends at the edges of a row, small corners inside
    leftRadius: leftmost ? (height / 2) : Appearance.rounding.verysmall
    rightRadius: rightmost ? (height / 2) : Appearance.rounding.verysmall
    // Icon-only buttons would otherwise be nearly round
    implicitWidth: Math.max(baseWidth, buttonText?.length > 0 ? 0 : Math.round(baseHeight * 1.25))
    colBackground: Appearance.colors.colSecondaryContainer
    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
    colBackgroundActive: Appearance.colors.colSecondaryContainerActive

    FontMetrics {
        id: iconLineMetrics
        font.family: Appearance.font.family.iconMaterial
        font.pixelSize: Appearance.font.pixelSize.larger
    }

    contentItem: Item {
        implicitWidth: contentRow.implicitWidth
        // Keep text-only and icon options the same height, without zero-height
        // icon slots or a hidden empty label taking a share of the row's width.
        implicitHeight: Math.max(contentRow.implicitHeight, Math.ceil(iconLineMetrics.height))

        RowLayout {
            id: contentRow
            anchors.centerIn: parent
            anchors.alignWhenCentered: false
            spacing: 4

            Loader {
                Layout.alignment: Qt.AlignVCenter
                active: root.buttonIcon && root.buttonIcon.length > 0
                visible: active
                sourceComponent: MaterialSymbol {
                    text: root.buttonIcon
                    iconSize: Appearance.font.pixelSize.larger
                    color: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                }
            }

            StyledText {
                visible: text.length > 0
                Layout.alignment: Qt.AlignVCenter
                color: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                text: root.buttonText
            }
        }
    }
}
