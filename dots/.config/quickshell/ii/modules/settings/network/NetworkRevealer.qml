import QtQuick
import QtQuick.Layouts
import qs.modules.common

/** A settings foldout that keeps its contents through the closing animation. */
Item {
    id: root
    property bool expanded: false
    property bool animationsEnabled: true
    property bool instant: false
    property real bottomPadding: 0
    property alias spacing: content.spacing
    default property alias contentData: content.data
    signal expandRequested()

    // Settings search needs the final layout before it scrolls to a folded row.
    function settingsReveal(): bool {
        if (root.expanded) return false;
        root.instant = true;
        root.expandRequested();
        Qt.callLater(() => root.instant = false);
        return root.expanded;
    }

    Layout.fillWidth: true
    Layout.preferredHeight: implicitHeight
    implicitWidth: content.implicitWidth
    implicitHeight: root.expanded ? content.implicitHeight + root.bottomPadding : 0
    visible: root.expanded || implicitHeight > 0
    enabled: root.expanded
    clip: true
    opacity: root.expanded ? 1 : 0

    Behavior on implicitHeight {
        enabled: root.animationsEnabled && !root.instant
        NumberAnimation {
            duration: Appearance.animation.elementResize.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.standard
        }
    }
    Behavior on opacity {
        enabled: root.animationsEnabled && !root.instant
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveEffects
        }
    }

    ColumnLayout {
        id: content
        width: root.width
        spacing: 0
    }
}
