pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Where you are in the setup: the steps by name, the current one underlined by a pill that slides
 * along; finished ones get a check mark drawn in.
 */
Item {
    id: root
    required property var flow
    // The greeting has no place in the list
    readonly property var steps: root.flow.steps.filter(step => step.id !== "hello")
    readonly property int current: root.steps.findIndex(step => step.id === root.flow.step)
    implicitHeight: 40
    implicitWidth: row.implicitWidth

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6

        Repeater {
            id: labels
            model: root.steps

            delegate: Item {
                id: item
                required property var modelData
                required property int index
                readonly property bool done: index < root.current
                readonly property bool active: index === root.current
                width: label.implicitWidth + (done ? 22 : 0) + 20
                height: 32
                Behavior on width {
                    NumberAnimation { duration: Motion.ms(260); easing.type: Easing.OutCubic }
                }

                MaterialSymbol {
                    id: check
                    anchors.verticalCenter: parent.verticalCenter
                    x: 8
                    text: "check"
                    iconSize: 16
                    color: Appearance.colors.colPrimary
                    scale: item.done ? 1 : 0
                    opacity: item.done ? 1 : 0
                    Behavior on scale {
                        NumberAnimation { duration: Motion.ms(320); easing.type: Easing.OutBack }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: Motion.ms(160) }
                    }
                }
                StyledText {
                    id: label
                    anchors.verticalCenter: parent.verticalCenter
                    x: item.done ? 28 : 10
                    text: item.modelData.title
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: item.active ? Font.DemiBold : Font.Normal
                    color: item.active ? Appearance.colors.colOnLayer0 : Appearance.colors.colSubtext
                    Behavior on x {
                        NumberAnimation { duration: Motion.ms(260); easing.type: Easing.OutCubic }
                    }
                    Behavior on color {
                        ColorAnimation { duration: Motion.ms(200) }
                    }
                }
            }
        }
    }

    // Slides under the current step and stretches on the way
    Rectangle {
        readonly property Item target: labels.itemAt(Math.max(0, root.current))
        visible: root.current >= 0
        y: row.y + row.height - 2
        x: row.x + (target?.x ?? 0) + 8
        width: Math.max(12, (target?.width ?? 0) - 16)
        height: 3
        radius: 1.5
        color: Appearance.colors.colPrimary
        Behavior on x {
            NumberAnimation { duration: Motion.ms(420); easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spatial }
        }
        Behavior on width {
            NumberAnimation { duration: Motion.ms(420); easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spatial }
        }
    }
}
