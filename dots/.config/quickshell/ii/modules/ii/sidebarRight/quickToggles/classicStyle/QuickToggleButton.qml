import qs.modules.common
import qs.services
import qs.modules.common.widgets
import QtQuick

GroupButton {
    id: button
    property string buttonIcon
    property string toggleType: ""
    baseWidth: toggleType ? Math.min(parent?.width || 130, SidebarLayout.classicSize(toggleType) * 45 - 5) : 40
    baseHeight: 40
    clickedWidth: baseWidth + 20
    toggled: false
    buttonRadius: (altAction && toggled) ? Appearance?.rounding.normal : Math.min(baseHeight, baseWidth) / 2
    buttonRadiusPressed: Appearance?.rounding?.small

    contentItem: MaterialSymbol {
        anchors.centerIn: parent
        iconSize: 22
        fill: toggled ? 1 : 0
        color: toggled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer1
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: buttonIcon

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

}
