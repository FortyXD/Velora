import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * One step of the setup: a title, a line under it and the step's content, which comes in item by item
 * (wrap items in Reveal with increasing `order`). Arrives from the side it was reached from.
 */
Item {
    id: root
    required property var flow
    property string title
    property string subtitle
    default property alias content: column.data
    property bool scrollable: false
    // Gets the keyboard when the page arrives, and whatever is typed while nothing else takes it
    property Item focusTarget: null
    // Height under the title, for pages that fill it instead of scrolling
    readonly property real areaHeight: area.height

    // Entrance: the host sets `fromSide` (1 from the right, -1 from the left) before it shows the page
    property int fromSide: 1
    opacity: 0
    x: Motion.travel(48) * root.fromSide
    Component.onCompleted: enter.start()
    ParallelAnimation {
        id: enter
        NumberAnimation {
            target: root
            property: "opacity"
            to: 1
            duration: Motion.ms(300)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.effects
        }
        NumberAnimation {
            target: root
            property: "x"
            to: 0
            duration: Motion.ms(Motion.page)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.decelerate
        }
    }
    // Leaves toward the other side, fading, then goes
    function leave(toSide) {
        exitX.to = -Motion.travel(48) * toSide;
        exit.start();
    }
    SequentialAnimation {
        id: exit
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "opacity"
                to: 0
                duration: Motion.ms(200)
            }
            NumberAnimation {
                id: exitX
                target: root
                property: "x"
                duration: Motion.ms(260)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.accelerate
            }
        }
        ScriptAction {
            script: root.destroy()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        Reveal {
            order: 0
            ColumnLayout {
                width: parent.width
                spacing: 6
                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    font.family: Appearance.font.family.title
                    font.pixelSize: 34
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer0
                    wrapMode: Text.Wrap
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.subtitle.length > 0
                    text: root.subtitle
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                }
            }
        }

        Flickable {
            id: area
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 18
            contentHeight: column.implicitHeight
            interactive: root.scrollable && contentHeight > height
            clip: root.scrollable
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: column
                width: parent.width
                spacing: 14
            }
        }
    }
}
