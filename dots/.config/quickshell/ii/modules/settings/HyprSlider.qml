import QtQuick
import qs.services
import qs.modules.common.widgets

/**
 * Slider row for a numeric Hyprland option. Only user drags are written.
 */
ConfigSlider {
    id: root
    required property string option
    property real fallback: 0
    property int decimals: 2
    property bool integer: false

    enabled: HyprlandSettings.ready
    usePercentTooltip: false
    value: HyprlandSettings.get(root.option, root.fallback)
    valueText: root.integer ? `${Math.round(root.value)}` : root.value.toFixed(root.decimals)
    onMoved: {
        const step = Math.pow(10, root.decimals);
        HyprlandSettings.set(root.option, root.integer ? Math.round(root.value) : Math.round(root.value * step) / step);
    }
}
