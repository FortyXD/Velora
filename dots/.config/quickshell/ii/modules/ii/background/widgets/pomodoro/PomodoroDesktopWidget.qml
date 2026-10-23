import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

/**
 * Pomodoro timer. Shares its state with the pomodoro in the right sidebar.
 * Before a period starts, its length can be changed right here: ±5 min or a preset.
 */
DesktopWidgetCard {
    id: root
    configEntryName: "pomodoro"

    readonly property int secondsLeft: TimerService.pomodoroSecondsLeft
    readonly property int lapDuration: TimerService.pomodoroLapDuration
    readonly property bool running: TimerService.pomodoroRunning
    readonly property bool idle: TimerService.pomodoroLapFresh
    readonly property real progress: root.lapDuration > 0 ? (root.lapDuration - root.secondsLeft) / root.lapDuration : 0
    readonly property string phaseKey: TimerService.pomodoroLongBreak ? "longBreak" : TimerService.pomodoroBreak ? "breakTime" : "focus"
    readonly property string phaseName: TimerService.pomodoroLongBreak ? Translation.tr("Long break")
        : TimerService.pomodoroBreak ? Translation.tr("Break") : Translation.tr("Focus")
    readonly property string phaseIcon: TimerService.pomodoroLongBreak ? "self_improvement"
        : TimerService.pomodoroBreak ? "coffee" : "target"
    readonly property list<int> presets: root.phaseKey === "focus" ? [15, 25, 45, 60] : root.phaseKey === "breakTime" ? [3, 5, 10, 15] : [10, 15, 20, 30]

    function pad(number) {
        return number.toString().padStart(2, "0");
    }

    // Length of the current period in minutes, written to the config
    function setMinutes(minutes) {
        Config.options.time.pomodoro[root.phaseKey] = Math.max(1, Math.min(180, minutes)) * 60;
    }

    component CircleButton: RippleButton {
        id: circleButton
        property string buttonIcon
        property bool primary: false
        property real size: 40
        implicitWidth: size
        implicitHeight: size
        buttonRadius: Appearance.rounding.full
        colBackground: circleButton.primary ? root.colAccent : root.colLayer
        colBackgroundHover: ColorUtils.mix(circleButton.colBackground, root.colOnCard, 0.85)
        colRipple: ColorUtils.mix(circleButton.colBackground, root.colOnCard, 0.7)
        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            text: circleButton.buttonIcon
            iconSize: circleButton.size * 0.5
            fill: 1
            color: circleButton.primary ? root.colOnAccent : root.colOnCard
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        Item { // Width of the widget
            implicitWidth: 248
            implicitHeight: 0
        }

        RowLayout { // Header
            Layout.fillWidth: true
            spacing: 8
            MaterialSymbol {
                text: "timer"
                iconSize: 20
                fill: 1
                color: root.colAccent
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Pomodoro")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: root.colOnCard
            }
            Rectangle { // Phase
                implicitHeight: 26
                implicitWidth: phaseRow.implicitWidth + 18
                radius: Appearance.rounding.full
                color: root.colLayer
                RowLayout {
                    id: phaseRow
                    anchors.centerIn: parent
                    spacing: 4
                    MaterialSymbol {
                        text: root.phaseIcon
                        iconSize: 15
                        fill: 1
                        color: root.colOnCard
                    }
                    StyledText {
                        text: root.phaseName
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: root.colOnCard
                    }
                }
            }
        }

        Item { // Ring with the time, ±5 min while idle
            Layout.fillWidth: true
            implicitHeight: 168

            CircularProgress {
                anchors.centerIn: parent
                implicitSize: 168
                lineWidth: 10
                value: root.progress
                colPrimary: root.colAccent
                colSecondary: root.colLayer
                enableAnimation: true
            }
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 0
                EditableTime { // Click to type a time; the background asks for keyboard focus meanwhile
                    id: timeEdit
                    Layout.alignment: Qt.AlignHCenter
                    seconds: root.secondsLeft
                    pixelSize: 38
                    fontFamily: Appearance.font.family.numbers
                    color: root.colOnCard
                    onTimeEntered: seconds => TimerService.setPomodoroTime(seconds)
                    onEditingChanged: GlobalStates.desktopWidgetEditing = timeEdit.editing
                    Component.onDestruction: if (timeEdit.editing) GlobalStates.desktopWidgetEditing = false
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("Cycle %1 of %2").arg(TimerService.pomodoroCycle + 1).arg(TimerService.cyclesBeforeLongBreak)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: root.colOnCardVariant
                }
            }
            CircleButton {
                anchors {
                    left: parent.left
                    verticalCenter: parent.verticalCenter
                }
                size: 34
                opacity: root.idle ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                buttonIcon: "remove"
                onClicked: root.setMinutes(Math.round(root.lapDuration / 60) - 5)
                StyledToolTip {
                    text: Translation.tr("5 minutes less")
                }
            }
            CircleButton {
                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                size: 34
                opacity: root.idle ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                buttonIcon: "add"
                onClicked: root.setMinutes(Math.round(root.lapDuration / 60) + 5)
                StyledToolTip {
                    text: Translation.tr("5 minutes more")
                }
            }
        }

        RowLayout { // Presets while idle
            Layout.alignment: Qt.AlignHCenter
            visible: root.idle
            spacing: 4
            Repeater {
                model: root.presets
                delegate: RippleButton {
                    id: presetButton
                    required property int modelData
                    readonly property bool selected: Math.round(root.lapDuration / 60) === modelData
                    implicitWidth: 52
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.full
                    colBackground: selected ? root.colAccent : root.colLayer
                    colBackgroundHover: ColorUtils.mix(presetButton.colBackground, root.colOnCard, 0.85)
                    colRipple: ColorUtils.mix(presetButton.colBackground, root.colOnCard, 0.7)
                    onClicked: root.setMinutes(modelData)
                    contentItem: StyledText {
                        horizontalAlignment: Text.AlignHCenter
                        text: Translation.tr("%1 min").arg(presetButton.modelData)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: presetButton.selected ? root.colOnAccent : root.colOnCard
                    }
                }
            }
        }

        RowLayout { // Controls
            Layout.alignment: Qt.AlignHCenter
            spacing: 10
            CircleButton {
                buttonIcon: "restart_alt"
                enabled: !root.idle || TimerService.pomodoroCycle > 0 || TimerService.pomodoroBreak
                onClicked: TimerService.resetPomodoro()
                StyledToolTip {
                    text: Translation.tr("Reset")
                }
            }
            RippleButton {
                id: playButton
                implicitHeight: 48
                implicitWidth: playRow.implicitWidth + 36
                buttonRadius: Appearance.rounding.full
                colBackground: root.colAccent
                colBackgroundHover: ColorUtils.mix(root.colAccent, root.colOnCard, 0.85)
                colRipple: ColorUtils.mix(root.colAccent, root.colOnCard, 0.7)
                onClicked: TimerService.togglePomodoro()
                contentItem: Item {
                    RowLayout {
                        id: playRow
                        anchors.centerIn: parent
                        spacing: 6
                        MaterialSymbol {
                            text: root.running ? "pause" : "play_arrow"
                            iconSize: 24
                            fill: 1
                            color: root.colOnAccent
                        }
                        StyledText {
                            text: root.running ? Translation.tr("Pause") : root.idle ? Translation.tr("Start") : Translation.tr("Resume")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: root.colOnAccent
                        }
                    }
                }
            }
            CircleButton {
                buttonIcon: "skip_next"
                onClicked: TimerService.skipPomodoro()
                StyledToolTip {
                    text: TimerService.pomodoroBreak ? Translation.tr("Skip the break") : Translation.tr("Skip to the break")
                }
            }
        }
    }
}
