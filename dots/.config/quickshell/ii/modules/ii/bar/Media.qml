import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs
import qs.modules.common.functions

import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Services.Mpris
import Quickshell.Hyprland

Item {
    id: root
    property bool borderless: Config.options.bar.borderless
    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    readonly property string cleanedTitle: StringUtils.cleanMusicTitle(activePlayer?.trackTitle) || Translation.tr("No media")
    readonly property bool animate: Config.options.bar.microAnimations
    readonly property bool hovered: hoverHandler.hovered

    Layout.fillHeight: true
    implicitWidth: rowLayout.implicitWidth + rowLayout.spacing * 2
    implicitHeight: Appearance.sizes.barHeight

    HoverHandler {
        id: hoverHandler
    }

    Timer {
        running: activePlayer?.playbackState == MprisPlaybackState.Playing
        interval: Config.options.resources.updateInterval
        repeat: true
        onTriggered: activePlayer.positionChanged()
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.MiddleButton | Qt.BackButton | Qt.ForwardButton | Qt.RightButton | Qt.LeftButton
        onPressed: (event) => {
            if (event.button === Qt.MiddleButton) {
                activePlayer.togglePlaying();
            } else if (event.button === Qt.BackButton) {
                activePlayer.previous();
            } else if (event.button === Qt.ForwardButton || event.button === Qt.RightButton) {
                activePlayer.next();
            } else if (event.button === Qt.LeftButton) {
                GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen
            }
        }
    }

    RowLayout { // Real content
        id: rowLayout

        spacing: 4
        anchors.fill: parent

        ClippedFilledCircularProgress {
            id: mediaCircProg
            Layout.alignment: Qt.AlignVCenter
            lineWidth: Appearance.rounding.unsharpen
            // Without a player this would be NaN, and an animated NaN never settles
            value: activePlayer?.length > 0 ? activePlayer.position / activePlayer.length : 0
            implicitSize: 20
            colPrimary: Appearance.colors.colOnSecondaryContainer
            // Short glide between position updates, so seeking and track changes don't jump
            enableAnimation: root.animate
            animationDuration: 400

            Item {
                anchors.centerIn: parent
                width: mediaCircProg.implicitSize
                height: mediaCircProg.implicitSize

                MaterialSymbol {
                    anchors.centerIn: parent
                    fill: 1
                    text: activePlayer?.isPlaying ? "pause" : "music_note"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.m3colors.m3onSecondaryContainer
                }
            }
        }

        Item { // Title. Long ones fade out at the edges instead of eliding, so resizing never makes letters pop
            id: titleArea
            visible: Config.options.bar.verbose
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true
            Layout.rightMargin: rowLayout.spacing
            implicitHeight: titleText.implicitHeight
            clip: true

            readonly property real overflow: titleText.implicitWidth - width
            readonly property bool marquee: root.animate && root.hovered && overflow > 0
            // Each fade grows with how much text is hidden on that side, up to fadeLength
            readonly property real fadeLength: 20
            readonly property real textLeft: titleMover.x + titleText.x
            readonly property real leftFade: Math.min(fadeLength, Math.max(0, -textLeft))
            readonly property real rightFade: Math.min(fadeLength, Math.max(0, textLeft + titleText.implicitWidth - width))

            layer.enabled: leftFade > 0 || rightFade > 0
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: titleArea.width
                    height: titleArea.height
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: titleArea.leftFade > 0 ? "transparent" : "white" }
                        GradientStop { position: titleArea.leftFade / Math.max(1, titleArea.width); color: "white" }
                        GradientStop { position: 1 - titleArea.rightFade / Math.max(1, titleArea.width); color: "white" }
                        GradientStop { position: 1; color: titleArea.rightFade > 0 ? "transparent" : "white" }
                    }
                }
            }

            Item {
                id: titleMover
                // Centered while it fits, left-aligned once it doesn't; both agree when it just fits
                x: Math.max(0, (titleArea.width - titleText.implicitWidth) / 2)
                width: titleText.implicitWidth
                height: parent.height

                StyledText {
                    id: titleText
                    anchors.verticalCenter: parent.verticalCenter
                    color: Appearance.colors.colOnLayer1
                    text: `${cleanedTitle}${activePlayer?.trackArtist ? ' • ' + activePlayer.trackArtist : ''}`
                    // Smooth return to the start when the marquee stops (the marquee itself bypasses this)
                    Behavior on x {
                        NumberAnimation {
                            duration: 450
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance.animationCurves.emphasized
                        }
                    }
                }
            }

            // Started only after the controls have slid in: a running animation group keeps the values it started with
            onMarqueeChanged: {
                if (marquee) {
                    marqueeDelay.restart();
                } else {
                    marqueeDelay.stop();
                    marqueeAnim.stop();
                    titleText.x = 0;
                }
            }
            onOverflowChanged: { // A new title needs a new scroll distance
                if (!marqueeAnim.running) return;
                marqueeAnim.stop();
                titleText.x = 0;
                marqueeDelay.restart();
            }
            Timer {
                id: marqueeDelay
                interval: 700
                onTriggered: marqueeAnim.restart()
            }
            SequentialAnimation {
                id: marqueeAnim
                loops: Animation.Infinite
                NumberAnimation {
                    target: titleText
                    property: "x"
                    to: -titleArea.overflow
                    duration: Math.max(1, titleArea.overflow) * 22
                    easing.type: Easing.InOutSine
                }
                PauseAnimation { duration: 900 }
                NumberAnimation {
                    target: titleText
                    property: "x"
                    to: 0
                    duration: 450
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.emphasized
                }
                PauseAnimation { duration: 1200 }
            }
        }

        Item { // Playback controls slide in on hover, easing in and out
            id: controls
            readonly property bool reveal: root.hovered && root.activePlayer !== null
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: reveal ? controlsRow.implicitWidth : 0
            implicitHeight: controlsRow.implicitHeight
            visible: implicitWidth > 0
            clip: true

            Behavior on implicitWidth {
                enabled: root.animate
                NumberAnimation {
                    duration: controls.reveal ? 400 : 320
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Appearance.animationCurves.emphasized
                }
            }

            Row {
                id: controlsRow
                anchors.right: parent.right
                spacing: 0
                opacity: controls.reveal ? 1 : 0
                Behavior on opacity {
                    enabled: root.animate
                    NumberAnimation {
                        duration: controls.reveal ? 320 : 200
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.emphasized
                    }
                }

                CircleUtilButton {
                    implicitHeight: 24
                    enabled: MprisController.canGoPrevious
                    iconName: "skip_previous"
                    iconFill: 1
                    onClicked: MprisController.previous()
                }
                CircleUtilButton {
                    implicitHeight: 24
                    enabled: MprisController.canTogglePlaying
                    iconName: MprisController.isPlaying ? "pause" : "play_arrow"
                    iconFill: 1
                    onClicked: MprisController.togglePlaying()
                }
                CircleUtilButton {
                    implicitHeight: 24
                    enabled: MprisController.canGoNext
                    iconName: "skip_next"
                    iconFill: 1
                    onClicked: MprisController.next()
                }
            }
        }
    }
}
