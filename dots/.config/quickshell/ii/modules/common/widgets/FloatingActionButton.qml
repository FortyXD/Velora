import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * Material 3 FAB.
 */
RippleButton {
    id: root
    property string iconText: "add"
    property bool expanded: false
    property real baseSize: 56
    property real elementSpacing: 5
    implicitWidth: Math.max(contentRowLayout.implicitWidth + (baseSize - icon.implicitWidth), baseSize)
    implicitHeight: baseSize
    buttonRadius: baseSize / 14 * 4
    colBackground: Appearance.colors.colPrimaryContainer
    colBackgroundHover: Appearance.colors.colPrimaryContainerHover
    colRipple: Appearance.colors.colPrimaryContainerActive
    property color colOnBackground: Appearance.colors.colOnPrimaryContainer
    contentItem: Item {
        implicitWidth: contentRowLayout.implicitWidth
        implicitHeight: contentRowLayout.implicitHeight

        Row {
            id: contentRowLayout
            anchors.centerIn: parent
            anchors.alignWhenCentered: false
            spacing: 0

            MaterialSymbol {
                id: icon
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                iconSize: 26
                color: root.colOnBackground
                text: root.iconText
            }
            Loader {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.buttonText?.length > 0
                active: visible
                sourceComponent: Revealer {
                    visible: root.expanded || implicitWidth > 0
                    reveal: root.expanded
                    implicitWidth: reveal ? (buttonText.implicitWidth + root.elementSpacing) : 0
                    implicitHeight: buttonText.implicitHeight
                    StyledText {
                        id: buttonText
                        anchors {
                            left: parent.left
                            leftMargin: root.elementSpacing
                            verticalCenter: parent.verticalCenter
                        }
                        text: root.buttonText
                        color: Appearance.colors.colOnPrimaryContainer
                        font.pixelSize: 14
                        font.weight: 450
                    }
                }
            }
        }
    }
}
