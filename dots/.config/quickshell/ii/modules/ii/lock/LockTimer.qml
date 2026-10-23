import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * A running pomodoro, timer or stopwatch. With `liveData` off (the settings app) an example.
 */
Rectangle {
    id: root
    property bool liveData: true
    readonly property string kind: {
        if (!root.liveData) return "pomodoro";
        if (TimerService.pomodoroRunning) return "pomodoro";
        if (TimerService.countdownRunning) return "countdown";
        if (TimerService.stopwatchRunning) return "stopwatch";
        return "";
    }
    readonly property bool hasContent: root.kind.length > 0
    readonly property string label: {
        if (root.kind === "pomodoro") return root.liveData && TimerService.pomodoroBreak ? Translation.tr("Break") : Translation.tr("Focus");
        if (root.kind === "stopwatch") return Translation.tr("Stopwatch");
        return Translation.tr("Timer");
    }
    readonly property string timeText: {
        if (!root.liveData) return "24:13";
        if (root.kind === "pomodoro") return DateUtils.formatDuration(TimerService.pomodoroSecondsLeft);
        if (root.kind === "countdown") return DateUtils.formatDuration(TimerService.countdownSecondsLeft);
        if (root.kind === "stopwatch") return DateUtils.formatDuration(TimerService.stopwatchTime / 100);
        return "00:00";
    }

    implicitWidth: row.implicitWidth + 36
    implicitHeight: 64
    radius: height / 2
    color: Appearance.colors.colTertiaryContainer

    StyledRectangularShadow {
        target: root
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 10
        MaterialSymbol {
            text: root.kind === "stopwatch" ? "timer_play" : root.kind === "countdown" ? "hourglass_top" : "nest_clock_farsight_analog"
            iconSize: 28
            fill: 1
            color: Appearance.colors.colOnTertiaryContainer
        }
        ColumnLayout {
            spacing: -4
            StyledText {
                text: root.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnTertiaryContainer
                opacity: 0.8
            }
            StyledText {
                text: root.timeText
                font.pixelSize: Appearance.font.pixelSize.larger
                font.family: Appearance.font.family.numbers
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnTertiaryContainer
            }
        }
    }
}
