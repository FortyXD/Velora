import QtQuick
import qs.modules.common

/**
 * The rounded block a sidebar part sits on. `focusTarget` gets the keyboard when the part is focused.
 */
Rectangle {
    id: root
    property Item host: null
    property Item focusTarget: null
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1
    clip: true
}
