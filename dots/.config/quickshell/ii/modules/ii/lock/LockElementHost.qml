import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * One part of the lock screen, placed where services/LockLayout.qml says, with its animations:
 * in one by one when the screen locks, flying apart on unlock, and gliding when moved.
 * In an editor (scene.editing) it gets an outline and can be dragged; the scene snaps it to guides.
 * Dragged off the screen, a part that can be hidden turns red and hides when let go.
 */
Item {
    id: host
    required property string elementId
    required property Item scene
    property bool hasContent: true // Parts without anything to show (no music, no notifications) stay hidden on the lock
    default property alias content: holder.data
    readonly property Item element: holder.children.length > 0 ? holder.children[0] : null

    readonly property var spec: LockElementCatalog.get(host.elementId)
    readonly property int order: LockElementCatalog.ids.indexOf(host.elementId)
    readonly property var item: LockLayout.items[host.elementId]
    readonly property bool shown: host.item.show && (host.hasContent || host.scene.editing)
    readonly property real size: host.spec.scalable ? host.item.size : 1
    readonly property bool attached: host.item.attach === "password"
    readonly property bool selected: host.scene.selectedId === host.elementId

    // Where the middle is, in scene coordinates
    property bool dragging: false
    property bool removing: false
    property point dragCenter: Qt.point(0, 0)
    readonly property real visualWidth: host.width * host.size
    readonly property real visualHeight: host.height * host.size
    readonly property point center: {
        if (host.dragging) return host.scene.clampCenter(host.dragCenter, host.visualWidth, host.visualHeight);
        if (host.attached) return host.scene.attachedCenter(host.elementId, host.visualWidth, host.visualHeight);
        return host.scene.clampCenter(Qt.point(host.item.x * host.scene.width, host.item.y * host.scene.height), host.visualWidth, host.visualHeight);
    }

    width: host.element?.implicitWidth ?? 0
    height: host.element?.implicitHeight ?? 0
    x: Math.round(host.center.x - host.width / 2)
    y: Math.round(host.center.y - host.height / 2)
    scale: host.size
    z: host.selected ? 2 : 1
    visible: opacity > 0.001
    Behavior on x {
        enabled: !host.dragging && host.scene.animations !== "none"
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    Behavior on y {
        enabled: !host.dragging && host.scene.animations !== "none"
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }
    Behavior on scale {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    // ---- Animations: enter (0 → 1), exit (0 → 1) and the clock's glide from the desktop ----
    property real enter: host.scene.startHidden && host.scene.animations !== "none" ? 0 : 1
    property real exit: 0
    property real glideX: 0
    property real glideY: 0
    property real glideScale: 1
    readonly property bool full: host.scene.animations === "full"
    property real shownFactor: host.shown ? 1 : 0
    Behavior on shownFactor {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
    opacity: host.shownFactor * host.enter * (1 - host.exit)

    transform: [
        Scale {
            origin.x: host.width / 2
            origin.y: host.height / 2
            readonly property real factor: host.glideScale * (host.full ? (0.92 + 0.08 * host.enter) * (1 - 0.08 * host.exit) : 1)
            xScale: factor
            yScale: factor
        },
        Translate {
            // Out on unlock: away from the middle of the screen
            readonly property real awayX: (host.center.x - host.scene.width / 2) * 0.15
            readonly property real awayY: (host.center.y - host.scene.height / 2) * 0.15
            x: (host.glideX + (host.full ? host.exit * awayX : 0)) / host.size
            y: (host.glideY + (host.full ? (1 - host.enter) * 36 + host.exit * awayY : 0)) / host.size
        }
    ]

    function startEntrance(glideFrom) {
        enterAnim.stop();
        glideAnim.stop();
        host.exit = 0;
        if (host.scene.animations === "none") {
            host.enter = 1;
            return;
        }
        // The clock continues from where it was on the desktop
        if (glideFrom && host.full) {
            host.enter = 1;
            host.glideX = glideFrom.x + glideFrom.width / 2 - host.center.x;
            host.glideY = glideFrom.y + glideFrom.height / 2 - host.center.y;
            host.glideScale = Math.max(0.2, glideFrom.width / Math.max(1, host.visualWidth));
            glideAnim.start();
            return;
        }
        host.enter = 0;
        enterAnim.delay = host.full ? 120 + host.order * 55 : 0;
        enterAnim.start();
    }

    function startExit() {
        enterAnim.stop();
        if (host.scene.animations === "none") return;
        exitAnim.start();
    }

    SequentialAnimation {
        id: enterAnim
        property int delay: 0
        PauseAnimation {
            duration: enterAnim.delay
        }
        NumberAnimation {
            target: host
            property: "enter"
            to: 1
            duration: host.full ? Appearance.animation.elementMoveEnter.duration * 1.4 : Appearance.animation.elementMoveFast.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: host.full ? Appearance.animationCurves.expressiveDefaultSpatial : Appearance.animationCurves.standardDecel
        }
    }
    ParallelAnimation {
        id: glideAnim
        readonly property int duration: Appearance.animation.elementMove.duration * 1.6
        NumberAnimation { target: host; property: "glideX"; to: 0; duration: glideAnim.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial }
        NumberAnimation { target: host; property: "glideY"; to: 0; duration: glideAnim.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial }
        NumberAnimation { target: host; property: "glideScale"; to: 1; duration: glideAnim.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial }
    }
    NumberAnimation {
        id: exitAnim
        target: host
        property: "exit"
        to: 1
        duration: host.full ? 280 : 180
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
    }

    Item {
        id: holder
        anchors.fill: parent
    }

    // ---- Editing ----
    Rectangle {
        visible: host.scene.editing
        anchors {
            fill: parent
            margins: -4 / host.size
        }
        radius: 10 / host.size
        color: host.removing ? ColorUtils.transparentize(Appearance.colors.colError, 0.55)
            : host.selected ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.85) : "transparent"
        border.width: (host.selected || host.removing ? 3 : 1.5) / (host.scene.editScale * host.size)
        border.color: host.removing ? Appearance.colors.colError
            : host.selected ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.4)

        MaterialSymbol {
            visible: host.removing
            anchors.centerIn: parent
            text: "visibility_off"
            iconSize: Math.min(parent.width, parent.height, 48 / host.scene.editScale) * 0.7
            color: Appearance.colors.colOnError
        }
    }
    MouseArea {
        id: dragArea
        enabled: host.scene.editing
        visible: enabled
        anchors {
            fill: parent
            margins: -4 / host.size
        }
        hoverEnabled: true
        preventStealing: true
        cursorShape: host.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property point startPoint
        property point startCenter

        onPressed: mouse => {
            startPoint = mapToItem(host.scene, mouse.x, mouse.y);
            startCenter = host.center;
            host.scene.selectElement(host.elementId);
        }
        onPositionChanged: mouse => {
            if (!pressed) return;
            const p = mapToItem(host.scene, mouse.x, mouse.y);
            const dx = p.x - startPoint.x;
            const dy = p.y - startPoint.y;
            if (!host.dragging && Math.hypot(dx, dy) < 4 / host.scene.editScale) return;
            host.dragCenter = host.scene.snap(host, Qt.point(startCenter.x + dx, startCenter.y + dy));
            host.dragging = true;
            // Off the screen: its middle left it, or the pointer is at the edge of a full-size editor
            const w = host.scene.width;
            const h = host.scene.height;
            const rawX = startCenter.x + dx;
            const rawY = startCenter.y + dy;
            host.removing = (host.spec.hideable ?? false) && (rawX < 0 || rawX > w || rawY < 0 || rawY > h
                || p.x <= 1 || p.y <= 1 || p.x >= w - 1 || p.y >= h - 1);
        }
        onReleased: {
            if (!host.dragging) return;
            const c = host.center;
            const removing = host.removing;
            host.dragging = false;
            host.removing = false;
            host.scene.clearGuides();
            if (removing) host.scene.elementRemoved(host.elementId);
            else host.scene.elementMoved(host.elementId, c.x / host.scene.width, c.y / host.scene.height);
        }
        onCanceled: {
            host.dragging = false;
            host.removing = false;
            host.scene.clearGuides();
        }
        onDoubleClicked: host.scene.elementReset(host.elementId)
    }
}
