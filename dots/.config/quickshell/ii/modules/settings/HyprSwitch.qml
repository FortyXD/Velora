import QtQuick
import qs.services
import qs.modules.common.widgets

/**
 * Switch row for a boolean Hyprland option.
 */
ConfigSwitch {
    id: root
    required property string option
    property bool fallback: false

    enabled: HyprlandSettings.ready
    autoToggle: false
    checked: HyprlandSettings.get(root.option, root.fallback) === true
    onClicked: HyprlandSettings.set(root.option, !root.checked)
}
