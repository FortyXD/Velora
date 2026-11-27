import QtQuick
import qs.modules.common
import qs.modules.waffle.looks
import qs.services

NumberAnimation {
    id: root
    property: "x"
    to: target?.width ?? 0
    duration: Appearance.scaledDuration(250)
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Looks.transition.easing.bezierCurve.easeIn

    function dismiss(ids) {
        if (running || ids.length === 0) return;
        if (duration > 0) start();
        Notifications.discardAfter(ids, duration);
    }
}
