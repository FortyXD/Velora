import QtQuick
import qs.services
import qs.modules.common.widgets

/**
 * Spin box row for a numeric Hyprland option. `factor` scales the shown number (100 shows 0.5 as 50).
 */
ConfigSpinBox {
    id: root
    required property string option
    property real fallback: 0
    property real factor: 1

    enabled: HyprlandSettings.ready
    value: Math.round(HyprlandSettings.get(root.option, root.fallback) * root.factor)
    onValueChanged: {
        if (!HyprlandSettings.ready) return;
        const newValue = root.factor === 1 ? root.value : Math.round(root.value / root.factor * 1000) / 1000;
        if (newValue !== HyprlandSettings.get(root.option, root.fallback)) HyprlandSettings.set(root.option, newValue);
    }
}
