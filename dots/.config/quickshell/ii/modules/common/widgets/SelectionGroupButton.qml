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
    verticalPadding: 8
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

    contentItem: RowLayout {
        spacing: 4 * (root.buttonText?.length > 0)

        Loader {
            Layout.alignment: Qt.AlignVCenter
            active: root.buttonIcon && root.buttonIcon.length > 0
            visible: active
            sourceComponent: Item {
                implicitWidth: materialSymbol.implicitWidth
                MaterialSymbol {
                    id: materialSymbol
                    anchors.centerIn: parent
                    text: root.buttonIcon
                    iconSize: Appearance.font.pixelSize.larger
                    color: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                }
            }
        }

        Item {
            implicitWidth: root.buttonText?.length > 0 ? textItem.implicitWidth : 0
            implicitHeight: textMetrics.height // Force height to that of regular text

            TextMetrics {
                id: textMetrics
                font.family: Appearance.font.family.main
                text: "Abc"
            }

            StyledText {
                id: textItem
                anchors.centerIn: parent
                color: root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                text: root.buttonText
            }
        }
    }
}
