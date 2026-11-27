import QtQuick
import qs.modules.common
import qs.modules.common.functions

Rectangle {
    id: root
    property bool requested: false
    property rect bounds: Qt.rect(0, 0, 0, 0)

    function show(target: rect): void {
        // The first frame appears at the correct edge. Later targets move from the current frame.
        bounds = target;
        requested = true;
    }

    x: bounds.x * parent.width
    y: bounds.y * parent.height
    width: bounds.width * parent.width
    height: bounds.height * parent.height
    opacity: requested ? 1 : 0
    scale: 0.96 + 0.04 * opacity
    radius: Appearance.rounding.windowRounding
    color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.80)
    border.width: 2
    border.color: Appearance.colors.colPrimary

    Behavior on bounds {
        enabled: root.requested
        PropertyAnimation { duration: Appearance.scaledDuration(170); easing.type: Easing.OutCubic }
    }
    Behavior on opacity {
        NumberAnimation { duration: Appearance.scaledDuration(root.requested ? 150 : 110); easing.type: Easing.OutCubic }
    }
}
