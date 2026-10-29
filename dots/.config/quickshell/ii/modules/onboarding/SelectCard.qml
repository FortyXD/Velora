import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

/**
 * A choice in the setup: lifts a little under the pointer, and when chosen gets an outline and a
 * check mark that pops in.
 */
Item {
    id: root
    property bool selected: false
    property real radius: Appearance.rounding.large
    default property alias content: inner.data
    signal clicked()

    implicitWidth: 200
    implicitHeight: 120

    StyledRectangularShadow {
        target: card
        opacity: area.containsMouse || root.selected ? 1 : 0.4
        Behavior on opacity {
            NumberAnimation { duration: Motion.ms(200) }
        }
    }
    Rectangle {
        id: card
        width: parent.width
        height: parent.height
        y: area.containsMouse && !Motion.reduced ? -4 : 0
        scale: area.pressed ? 0.98 : 1
        radius: root.radius
        color: Appearance.colors.colLayer1
        border.width: root.selected ? 2 : 1
        border.color: root.selected ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
        clip: true
        Behavior on y {
            NumberAnimation { duration: Motion.ms(240); easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: Motion.ms(160); easing.type: Easing.OutCubic }
        }
        Behavior on border.color {
            ColorAnimation { duration: Motion.ms(200) }
        }

        Item {
            id: inner
            anchors.fill: parent
        }

        Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 10
            width: 26
            height: 26
            radius: 13
            color: Appearance.colors.colPrimary
            scale: root.selected ? 1 : 0
            Behavior on scale {
                NumberAnimation { duration: Motion.ms(360); easing.type: Easing.OutBack; easing.overshoot: 2 }
            }
            MaterialSymbol {
                anchors.centerIn: parent
                text: "check"
                iconSize: 18
                color: Appearance.colors.colOnPrimary
            }
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
