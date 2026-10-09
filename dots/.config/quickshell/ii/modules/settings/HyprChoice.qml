import QtQuick
import qs.services
import qs.modules.common.widgets

/**
 * Titled choice chips for a Hyprland option with a few possible values.
 */
ContentSubsection {
    id: root
    required property string option
    property var fallback
    property list<var> choices: []

    enabled: HyprlandSettings.ready
    ConfigSelectionArray {
        currentValue: HyprlandSettings.get(root.option, root.fallback)
        onSelected: newValue => HyprlandSettings.set(root.option, newValue)
        options: root.choices
    }
}
