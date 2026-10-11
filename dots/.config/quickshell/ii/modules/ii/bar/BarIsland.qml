import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

/**
 * The media slot of the bar, taken over by ongoing activities while they last:
 * screen recording, then pomodoro, then the stopwatch, then a short card when the track changes.
 * Only the visible page is loaded.
 */
Item {
    id: root
    readonly property var options: Config.options.bar.island
    readonly property bool animate: Config.options.bar.microAnimations

    // Paused timers keep their page, so they can be resumed from here
    readonly property bool pomodoroActive: TimerService.pomodoroRunning || !TimerService.pomodoroLapFresh
    readonly property bool stopwatchActive: TimerService.stopwatchRunning || TimerService.stopwatchTime > 0
    property bool trackToastShown: false

    readonly property string mode: (options.showRecording && ScreenRecorder.recording) ? "recording"
        : (options.showPomodoro && pomodoroActive) ? "pomodoro"
        : (options.showStopwatch && stopwatchActive) ? "stopwatch"
        : trackToastShown ? "track"
        : "media"

    Layout.fillHeight: true
    implicitHeight: Appearance.sizes.barHeight

    function formatDuration(totalSeconds) {
        const seconds = Math.max(0, Math.floor(totalSeconds));
        const h = Math.floor(seconds / 3600);
        const m = Math.floor(seconds / 60) % 60;
        const s = seconds % 60;
        const pad = n => n.toString().padStart(2, "0");
        return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${pad(m)}:${pad(s)}`;
    }

    // Track change card
    property string lastTrackTitle: ""
    Component.onCompleted: lastTrackTitle = MprisController.activeTrack?.title ?? ""
    Connections {
        target: MprisController
        enabled: root.options.trackToast
        function onTrackChanged() {
            const title = MprisController.activeTrack?.title ?? "";
            const previous = root.lastTrackTitle;
            root.lastTrackTitle = title;
            if (previous.length === 0 || title.length === 0 || title === previous) return;
            root.trackToastShown = true;
            trackToastTimer.restart();
        }
    }
    Timer {
        id: trackToastTimer
        interval: 3000
        onTriggered: root.trackToastShown = false
    }

    component IslandPage: FadeLoader {
        id: page
        required property string pageMode
        anchors.fill: parent
        shown: root.mode === pageMode
        transform: Translate {
            y: page.shown || !root.animate ? 0 : 6
            Behavior on y {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }

    component PageLabel: StyledText {
        Layout.alignment: Qt.AlignVCenter
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colSubtext
    }

    component PageTime: RollingText {
        Layout.alignment: Qt.AlignVCenter
        pixelSize: Appearance.font.pixelSize.normal
        weight: Font.Medium
        color: Appearance.colors.colOnLayer1
        animate: root.animate
    }

    // Left click runs the page action, right click opens the sidebar that holds the full timers
    component PageMouseArea: MouseArea {
        property var action
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onPressed: event => {
            if (event.button === Qt.RightButton) GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
            else if (action) action();
        }
    }

    IslandPage {
        pageMode: "media"
        sourceComponent: Media {}
    }

    IslandPage {
        pageMode: "recording"
        sourceComponent: Item {
            id: recordingPage
            property real now: Date.now()
            Timer {
                interval: 1000
                running: true
                repeat: true
                onTriggered: {
                    recordingPage.now = Date.now();
                    if (root.animate) recordingPulse.restart();
                }
            }

            PageMouseArea {
                action: () => ScreenRecorder.toggle()
            }

            RowLayout {
                anchors.centerIn: parent
                spacing: 8

                Rectangle {
                    id: recordingDot
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 10
                    implicitHeight: 10
                    radius: 5
                    color: Appearance.colors.colError
                    // One short pulse per second rather than a constant animation
                    SequentialAnimation {
                        id: recordingPulse
                        NumberAnimation { target: recordingDot; property: "opacity"; to: 0.35; duration: 250; easing.type: Easing.InOutSine }
                        NumberAnimation { target: recordingDot; property: "opacity"; to: 1; duration: 350; easing.type: Easing.InOutSine }
                    }
                }
                PageLabel {
                    text: Translation.tr("Recording")
                }
                PageTime {
                    text: root.formatDuration((recordingPage.now - ScreenRecorder.startedAt) / 1000)
                }
                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: "stop_circle"
                    fill: 1
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colError
                }
            }
        }
    }

    IslandPage {
        pageMode: "pomodoro"
        sourceComponent: Item {
            PageMouseArea {
                action: () => TimerService.togglePomodoro()
            }

            RowLayout {
                anchors.centerIn: parent
                spacing: 8

                ClippedFilledCircularProgress {
                    id: pomodoroProgress
                    Layout.alignment: Qt.AlignVCenter
                    implicitSize: 20
                    lineWidth: Appearance.rounding.unsharpen
                    value: TimerService.pomodoroSecondsLeft / Math.max(1, TimerService.pomodoroLapDuration)
                    colPrimary: TimerService.pomodoroBreak ? Appearance.colors.colTertiary : Appearance.colors.colOnSecondaryContainer
                    enableAnimation: root.animate
                    animationDuration: 400

                    Item {
                        anchors.centerIn: parent
                        width: pomodoroProgress.implicitSize
                        height: pomodoroProgress.implicitSize
                        MaterialSymbol {
                            anchors.centerIn: parent
                            fill: 1
                            text: TimerService.pomodoroBreak ? "coffee" : "target"
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.m3colors.m3onSecondaryContainer
                        }
                    }
                }
                PageLabel {
                    text: TimerService.pomodoroLongBreak ? Translation.tr("Long break")
                        : TimerService.pomodoroBreak ? Translation.tr("Break") : Translation.tr("Focus")
                }
                PageTime {
                    reverse: true
                    text: root.formatDuration(TimerService.pomodoroSecondsLeft)
                }
                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    visible: !TimerService.pomodoroRunning
                    text: "pause"
                    fill: 1
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }

    IslandPage {
        pageMode: "stopwatch"
        sourceComponent: Item {
            id: stopwatchPage
            // TimerService ticks every 10 ms; the bar only needs whole seconds, so it keeps its own clock
            property real now10ms: TimerService.getCurrentTimeIn10ms()
            Timer {
                interval: 1000
                running: TimerService.stopwatchRunning
                repeat: true
                triggeredOnStart: true
                onTriggered: stopwatchPage.now10ms = TimerService.getCurrentTimeIn10ms()
            }
            // The start time lives in a 32-bit int and wraps; wrapping the difference the same way undoes that
            readonly property int elapsed10ms: TimerService.stopwatchRunning
                ? ((now10ms - TimerService.stopwatchStart) | 0) : TimerService.stopwatchTime
            readonly property int seconds: Math.floor(elapsed10ms / 100)

            PageMouseArea {
                action: () => TimerService.toggleStopwatch()
            }

            RowLayout {
                anchors.centerIn: parent
                spacing: 8

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: "timer"
                    fill: 1
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnLayer1
                }
                PageLabel {
                    text: Translation.tr("Stopwatch")
                }
                PageTime {
                    text: root.formatDuration(stopwatchPage.seconds)
                }
                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    visible: !TimerService.stopwatchRunning
                    text: "pause"
                    fill: 1
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }

    IslandPage {
        pageMode: "track"
        sourceComponent: Item {
            PageMouseArea {
                action: () => GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 2
                anchors.rightMargin: 4
                spacing: 8

                Rectangle {
                    id: cover
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 26
                    implicitHeight: 26
                    radius: Appearance.rounding.verysmall
                    color: Appearance.colors.colLayer2
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: cover.width
                            height: cover.height
                            radius: cover.radius
                        }
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: coverImage.status !== Image.Ready
                        text: "music_note"
                        fill: 1
                        iconSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colOnLayer2
                    }
                    StyledImage {
                        id: coverImage
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        source: MprisController.activeTrack?.artUrl ?? ""
                    }
                }

                ColumnLayout {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.fillWidth: true
                    spacing: -4

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                        text: StringUtils.cleanMusicTitle(MprisController.activeTrack?.title) || ""
                    }
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        text: MprisController.activeTrack?.artist ?? ""
                    }
                }
            }
        }
    }
}
