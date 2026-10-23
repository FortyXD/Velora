import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * A plain countdown: click the time to type your own, or pick a quick one.
 */
Item {
    id: root

    implicitHeight: contentColumn.implicitHeight
    implicitWidth: contentColumn.implicitWidth

    ColumnLayout {
        id: contentColumn
        anchors.fill: parent
        spacing: 0

        CircularProgress {
            Layout.alignment: Qt.AlignHCenter
            lineWidth: 8
            value: TimerService.countdownSecondsLeft / Math.max(1, TimerService.countdownDuration)
            implicitSize: 200
            enableAnimation: true

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 0

                EditableTime {
                    id: timeEdit
                    Layout.alignment: Qt.AlignHCenter
                    seconds: TimerService.countdownSecondsLeft
                    onTimeEntered: seconds => TimerService.setCountdown(seconds, true)
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: timeEdit.editing ? Translation.tr("10 · 25:00 · 1h 30m")
                        : TimerService.countdownDone ? Translation.tr("Time's up")
                        : TimerService.countdownRunning ? Translation.tr("Timer")
                        : TimerService.countdownFresh ? Translation.tr("Click the time to change it")
                        : Translation.tr("Paused")
                    font.pixelSize: TimerService.countdownFresh || timeEdit.editing ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.normal
                    color: TimerService.countdownDone ? Appearance.colors.colError : Appearance.colors.colSubtext
                }
            }
        }

        // Quick times
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 8
            Layout.bottomMargin: 8
            spacing: 6
            Repeater {
                model: [1, 5, 10, 15, 30]
                delegate: RippleButton {
                    id: quickTime
                    required property int modelData
                    implicitHeight: 30
                    implicitWidth: 46
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: TimerService.setCountdown(modelData * 60, true)
                    contentItem: StyledText {
                        horizontalAlignment: Text.AlignHCenter
                        text: Translation.tr("%1 m").arg(quickTime.modelData)
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer2
                    }
                }
            }
        }

        // Start / pause and reset
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 10

            RippleButton {
                contentItem: StyledText {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: TimerService.countdownRunning ? Translation.tr("Pause") : TimerService.countdownFresh || TimerService.countdownDone ? Translation.tr("Start") : Translation.tr("Resume")
                    color: TimerService.countdownRunning ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnPrimary
                }
                implicitHeight: 35
                implicitWidth: 90
                font.pixelSize: Appearance.font.pixelSize.larger
                onClicked: TimerService.toggleCountdown()
                colBackground: TimerService.countdownRunning ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimary
                colBackgroundHover: TimerService.countdownRunning ? Appearance.colors.colSecondaryContainer : Appearance.colors.colPrimary
            }

            RippleButton {
                implicitHeight: 35
                implicitWidth: 90
                onClicked: TimerService.resetCountdown()
                enabled: !TimerService.countdownFresh || TimerService.countdownDone
                font.pixelSize: Appearance.font.pixelSize.larger
                colBackground: Appearance.colors.colErrorContainer
                colBackgroundHover: Appearance.colors.colErrorContainerHover
                colRipple: Appearance.colors.colErrorContainerActive
                contentItem: StyledText {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: Translation.tr("Reset")
                    color: Appearance.colors.colOnErrorContainer
                }
            }
        }
    }
}
