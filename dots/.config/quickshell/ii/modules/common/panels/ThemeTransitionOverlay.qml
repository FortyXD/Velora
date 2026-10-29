pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Wayland

/**
 * The pictures of the screens for ThemeTransition: shown over everything while a change is made
 * underneath, then cut away by a circle growing from the pointer. The circle is one shape across
 * all screens, in global coordinates, so it flows from one monitor onto the next. A window exists
 * only while a transition runs, never takes input, and isn't blurred (rules.lua).
 */
Variants {
    model: Quickshell.screens

    Scope {
        id: screenScope
        required property ShellScreen modelData

        Component.onCompleted: {
            ThemeTransition.overlays++;
            ThemeTransition.debug = Quickshell.env("QS_DEBUG_TRANSITION") === "1";
        }
        Component.onDestruction: ThemeTransition.overlays--

        Connections {
            target: ThemeTransition
            function onCaptureRequested(generation) {
                if (windowLoader.active) windowLoader.item.capture(generation);
                else windowLoader.active = true; // Captures once it's built
            }
            function onRevealRequested(generation) {
                windowLoader.item?.reveal(generation);
            }
        }

        LazyLoader {
            id: windowLoader
            active: false

            component: PanelWindow {
                id: overlayWindow
                screen: screenScope.modelData
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.namespace: "quickshell:themeTransition"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                mask: Region {} // Only draws
                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }

                // Where the wave starts, global: the pointer, or the middle of the first screen when unknown
                readonly property point globalOrigin: {
                    const pointer = ThemeTransition.origin;
                    if (pointer.x >= 0 && pointer.y >= 0) return pointer;
                    const first = Quickshell.screens[0] ?? screenScope.modelData;
                    return Qt.point(first.x + first.width / 2, first.y + first.height / 2);
                }
                // How far the wave goes: to the farthest corner of any screen
                readonly property real reach: {
                    const o = overlayWindow.globalOrigin;
                    let farthest = 0;
                    for (const screen of Quickshell.screens) {
                        const dx = Math.max(Math.abs(o.x - screen.x), Math.abs(screen.x + screen.width - o.x));
                        const dy = Math.max(Math.abs(o.y - screen.y), Math.abs(screen.y + screen.height - o.y));
                        farthest = Math.max(farthest, Math.sqrt(dx * dx + dy * dy));
                    }
                    return farthest;
                }

                function capture(generation) {
                    snapshotComponent.createObject(snapshots, { "generation": generation });
                }
                function reveal(generation) {
                    for (const snapshot of snapshots.taken()) {
                        if (snapshot.generation === generation) snapshot.reveal();
                    }
                }
                Component.onCompleted: overlayWindow.capture(ThemeTransition.generation)

                Item {
                    id: snapshots
                    anchors.fill: parent
                    // Not every child is a picture: a layer adds items of its own
                    function taken() {
                        return Array.from(snapshots.children).filter(child => child.isSnapshot === true);
                    }
                    property int count: 0
                    // The last picture gone: the window goes too
                    onCountChanged: if (count === 0) Qt.callLater(() => {
                        if (snapshots.count === 0) windowLoader.active = false;
                    })
                }

                Component {
                    id: snapshotComponent

                    // One picture of the screen. A newer one, taken over a picture still giving way, replaces it.
                    ScreencopyView {
                        id: snapshot
                        required property int generation
                        readonly property bool isSnapshot: true
                        Component.onCompleted: snapshots.count++
                        Component.onDestruction: snapshots.count--
                        anchors.fill: parent
                        live: false
                        captureSource: screenScope.modelData
                        opacity: hasContent ? 1 : 0
                        property real progress: 0
                        property real reach: 0
                        // In this screen's coordinates; may lie on another screen
                        property point waveOrigin: Qt.point(0, 0)
                        property bool reported: false
                        // Soft, but a clear edge: about 3% of the screen's diagonal on each side
                        readonly property real feather: Math.max(36, Math.hypot(width, height) * 0.03)

                        function report() {
                            if (snapshot.reported) return;
                            snapshot.reported = true;
                            ThemeTransition.reportCaptured(snapshot.generation, screenScope.modelData.name);
                        }
                        onHasContentChanged: {
                            if (!hasContent || snapshot.generation !== ThemeTransition.generation) return;
                            // What's under it is in this picture already
                            for (const older of snapshots.taken()) {
                                if (older !== snapshot) older.destroy();
                            }
                            snapshot.report();
                        }
                        Timer { // No picture in time: let the change go ahead without one
                            running: true
                            interval: 320
                            onTriggered: {
                                snapshot.report();
                                if (!snapshot.hasContent) snapshot.destroy();
                            }
                        }

                        function reveal() {
                            const origin = overlayWindow.globalOrigin;
                            snapshot.waveOrigin = Qt.point(origin.x - screenScope.modelData.x, origin.y - screenScope.modelData.y);
                            snapshot.reach = overlayWindow.reach;
                            if (snapshot.hasContent) revealAnimation.start();
                            else snapshot.destroy();
                        }
                        NumberAnimation {
                            id: revealAnimation
                            target: snapshot
                            property: "progress"
                            from: 0
                            to: 1
                            duration: ThemeTransition.revealDuration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.emphasized
                            onFinished: snapshot.destroy()
                        }

                        // The picture at its own resolution, sampled one to one (fractional scales included)
                        layer.enabled: true
                        layer.smooth: false
                        layer.textureSize: snapshot.hasContent && snapshot.sourceSize.width > 0 ? snapshot.sourceSize : Qt.size(0, 0)
                        layer.effect: ShaderEffect {
                            fragmentShader: Quickshell.shellPath("assets/shaders/themeWave.frag.qsb")
                            property variant source // The picture, set by the layer
                            property vector2d resolution: Qt.vector2d(snapshot.width, snapshot.height)
                            property vector2d origin: Qt.vector2d(snapshot.waveOrigin.x, snapshot.waveOrigin.y)
                            property real radius: -snapshot.feather + (snapshot.reach + snapshot.feather * 2) * snapshot.progress
                            property real feather: snapshot.feather
                            property real progress: snapshot.progress
                            // The new palette is already applied underneath: its accent leads the way
                            property color rimColor: Appearance.m3colors.m3primary
                            property real rim: 0.22
                        }
                    }
                }
            }
        }
    }
}
