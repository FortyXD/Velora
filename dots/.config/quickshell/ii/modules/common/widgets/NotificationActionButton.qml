import qs.modules.common
import qs.modules.common.functions
import QtQuick

RippleButton {
    id: root
    required property string symbol
    property bool destructive: false
    implicitWidth: destructive ? 20 : 26
    implicitHeight: implicitWidth
    padding: 0
    focusPolicy: Qt.TabFocus
    buttonRadius: implicitWidth / 2
    colBackground: "transparent"
    colBackgroundHover: destructive ? Appearance.colors.colErrorContainer : Appearance.colors.colLayer3Hover
    colRipple: destructive ? Appearance.colors.colErrorContainer : Appearance.colors.colLayer3Active
    Accessible.name: buttonText
    contentItem: Item {
        Rectangle {
            visible: root.destructive
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.4)
        }
        MaterialSymbol {
            visible: root.symbol !== "close"
            anchors.fill: parent
            text: root.symbol
            iconSize: 16
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: Appearance.colors.colOnLayer2
        }
        Repeater {
            model: root.symbol === "close" ? [45, -45] : []
            delegate: Rectangle {
                required property int modelData
                anchors.centerIn: parent
                anchors.alignWhenCentered: false
                width: 10
                height: 1.6
                radius: height / 2
                rotation: modelData
                antialiasing: true
                color: root.hovered || root.down ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnLayer2
            }
        }
    }
    StyledToolTip { text: root.buttonText; delay: 400; alternativeVisibleCondition: root.visualFocus }
}
