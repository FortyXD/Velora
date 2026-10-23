import QtQuick
import qs.modules.common

/**
 * Wheel and touchpad scrolling for StyledFlickable and StyledListView.
 * A mouse wheel notch glides (the flickable's Behavior on contentY follows `gliding`); a touchpad moves the
 * content straight away at about the speed of browsers and keeps going a little after the fingers lift.
 * Scrolling past an end moves the flickable around this one instead.
 *
 * Vertical wheel events never reach the flickable's own wheel handler: Qt's touchpad code there jumps to
 * positions saved at the last click or an earlier swipe, which threw the page back during quick swipes.
 */
MouseArea {
    id: root

    required property Flickable flickable
    property bool gliding: false // A mouse wheel glide is running
    property real targetY: 0 // Where the glide is heading; notches stack onto it
    signal userScrolled() // Any scroll this area made, so programmatic scrolling can step aside

    readonly property var scrolling: Config.options?.interactions.scrolling
    readonly property real mouseScrollFactor: scrolling?.mouseScrollFactor ?? 120
    readonly property real mouseScrollDeltaThreshold: scrolling?.mouseScrollDeltaThreshold ?? 120
    // Qt takes touchpad steps 1:1, while browsers and Electron apps multiply them about tenfold
    readonly property real touchpadSpeed: scrolling?.touchpadSpeed ?? 10

    property var samples: [] // Recent touchpad steps {time, step} for the glide after the fingers lift

    anchors.fill: parent
    acceptedButtons: Qt.NoButton

    function fling() {
        momentumTimer.stop();
        const now = Date.now();
        const recent = root.samples.filter(sample => now - sample.time < 120);
        root.samples = [];
        if (recent.length < 2) return false;
        const duration = Math.max(16, recent[recent.length - 1].time - recent[0].time);
        const velocity = recent.reduce((sum, sample) => sum + sample.step, 0) / duration * 1000; // px/s
        if (Math.abs(velocity) < 300) return false;
        // Glide about as far as browsers do: a little after a slow swipe, more (but less than in proportion) after a quick one
        const speed = 4.2 * Math.pow(Math.abs(velocity), 0.75) * Math.sqrt(root.flickable.flickDeceleration / 1500);
        root.flickable.flick(0, Math.sign(velocity) * speed);
        return true;
    }

    // Moves the content by `step` px (positive = towards the top). Returns false when it's already at that end.
    function scroll(step, mouseWheel) {
        const f = root.flickable;
        const maxY = Math.max(0, f.contentHeight - f.height) + f.originY;
        const minY = f.originY;
        if (maxY <= minY) return false;
        const base = root.gliding ? root.targetY : f.contentY;
        const target = Math.max(minY, Math.min(base - step, maxY));
        if (Math.abs(target - f.contentY) < 0.5 && !root.gliding) return false;
        f.cancelFlick();
        if (mouseWheel) {
            root.samples = [];
        } else {
            root.samples = [...root.samples.filter(sample => Date.now() - sample.time < 120), { "time": Date.now(), "step": step }];
            momentumTimer.restart(); // In case the end of the scroll never arrives
        }
        root.gliding = mouseWheel;
        root.targetY = target;
        f.contentY = target;
        root.userScrolled();
        return true;
    }

    // The nearest flickable around this one, with its wheel area if it has one
    function outerFlickable() {
        for (let node = root.flickable.parent; node; node = node.parent) {
            if (node.contentItem !== undefined && node.contentY !== undefined && typeof node.flick === "function") return node;
        }
        return null;
    }

    function scrollOuter(step, mouseWheel) {
        const outer = root.outerFlickable();
        if (!outer) return;
        if (outer.wheelArea) {
            outer.wheelArea.scroll(step, mouseWheel);
            return;
        }
        const maxY = Math.max(0, outer.contentHeight - outer.height) + outer.originY;
        outer.contentY = Math.max(outer.originY, Math.min(outer.contentY - step, maxY));
    }

    onWheel: wheelEvent => {
        const f = root.flickable;
        // The end of a touchpad scroll arrives as an empty event
        if (wheelEvent.pixelDelta.y === 0 && wheelEvent.angleDelta.y === 0 && wheelEvent.angleDelta.x === 0) {
            if (!root.fling()) root.outerFlickable()?.wheelArea?.fling();
            wheelEvent.accepted = true;
            return;
        }
        if (Math.abs(wheelEvent.angleDelta.x) > Math.abs(wheelEvent.angleDelta.y)) {
            // Sideways: only a flickable that scrolls sideways has a use for it
            wheelEvent.accepted = !(f.contentWidth > f.width + 1 && f.flickableDirection !== Flickable.VerticalFlick);
            return;
        }
        // The angleDelta.y of a mouse wheel comes in multiples of ±120; a touchpad sends small pixel steps
        const mouseWheel = wheelEvent.pixelDelta.y === 0 && Math.abs(wheelEvent.angleDelta.y) >= root.mouseScrollDeltaThreshold;
        const notches = wheelEvent.angleDelta.y / root.mouseScrollDeltaThreshold;
        let step;
        if (mouseWheel) step = notches * root.mouseScrollFactor;
        else if (root.scrolling?.fasterTouchpadScroll) step = notches * (root.scrolling?.touchpadScrollFactor ?? 450);
        else step = (wheelEvent.pixelDelta.y !== 0 ? wheelEvent.pixelDelta.y : wheelEvent.angleDelta.y / 12) * root.touchpadSpeed;
        if (!root.scroll(step, mouseWheel)) root.scrollOuter(step, mouseWheel);
        wheelEvent.accepted = true;
    }

    Timer {
        id: momentumTimer
        interval: 90
        onTriggered: root.fling()
    }
}
