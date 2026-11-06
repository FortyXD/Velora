pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root
    required property var options
    required property var currentValue
    signal selected(var value)
    readonly property int selectedIndex: Math.max(0, options.findIndex(option => option.value === currentValue))
    implicitHeight: 38
    implicitWidth: 280
    radius: Appearance.rounding.full
    color: Appearance.colors.colLayer3
    clip: true

    Rectangle {
        x: 4 + root.selectedIndex * (root.width - 8) / root.options.length
        y: 4
        width: (root.width - 8) / root.options.length
        height: parent.height - 8
        radius: parent.radius
        color: Appearance.colors.colSecondaryContainer
        Behavior on x { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
        Behavior on width { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
    }
    Row {
        anchors.fill: parent
        anchors.margins: 4
        Repeater {
            model: root.options
            delegate: RippleButton {
                id: choice
                required property var modelData
                width: (root.width - 8) / root.options.length
                height: root.height - 8
                buttonRadius: Appearance.rounding.full
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onClicked: root.selected(modelData.value)
                Accessible.name: modelData.label
                Accessible.role: Accessible.RadioButton
                Accessible.checked: modelData.value === root.currentValue
                contentItem: StyledText {
                    text: choice.modelData.label
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: choice.modelData.value === root.currentValue ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                }
            }
        }
    }
}
