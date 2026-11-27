import QtQuick
import qs.modules.common
import qs.modules.common.widgets

RippleButtonWithIcon {
    Accessible.name: mainText
    implicitHeight: 38
    buttonRadius: Appearance.rounding.small
    colBackground: Appearance.colors.colSecondaryContainer
    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
    colRipple: Appearance.colors.colSecondaryContainerActive
    Keys.onReturnPressed: click()
    Keys.onEnterPressed: click()
}
