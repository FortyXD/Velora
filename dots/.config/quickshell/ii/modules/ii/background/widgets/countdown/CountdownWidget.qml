import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets

/**
 * Time left until (or since) a date and time set in the settings.
 * Shows days; on the last day it switches to hours, then minutes.
 */
DesktopWidgetCard {
    id: root
    configEntryName: "countdown"

    readonly property var options: Config.options.background.widgets.countdown
    readonly property var targetDate: {
        const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(root.options.date);
        if (!match) return null;
        const date = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]), root.options.hour, root.options.minute);
        return isNaN(date.getTime()) ? null : date;
    }
    readonly property date now: DateTime.clock.date
    readonly property real msLeft: root.targetDate ? root.targetDate.getTime() - root.now.getTime() : 0
    readonly property bool passed: root.msLeft <= 0
    readonly property bool isToday: root.targetDate !== null && root.targetDate.toDateString() === root.now.toDateString()
    readonly property real absMs: Math.abs(root.msLeft)
    readonly property int days: Math.floor(root.absMs / 86400000)
    readonly property int hours: Math.floor(root.absMs % 86400000 / 3600000)
    readonly property int minutes: Math.floor(root.absMs % 3600000 / 60000)

    // What the big number shows
    readonly property bool celebrating: root.passed && root.isToday
    readonly property int bigNumber: root.days > 0 ? root.days : root.hours > 0 ? root.hours : root.minutes
    readonly property string unitText: {
        if (root.days > 0) return root.passed ? Translation.tr("days ago") : Translation.tr("days left");
        if (root.hours > 0) return root.passed ? Translation.tr("hours ago") : Translation.tr("hours left");
        return root.passed ? Translation.tr("minutes ago") : Translation.tr("minutes left");
    }
    readonly property bool hasTime: root.options.hour !== 0 || root.options.minute !== 0

    ColumnLayout {
        anchors.fill: parent
        spacing: 2

        Item { // Minimum width
            implicitWidth: 220
            implicitHeight: 0
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            MaterialSymbol {
                text: root.celebrating ? "celebration" : root.passed ? "history" : "hourglass_top"
                iconSize: 20
                fill: 1
                color: root.colAccent
            }
            StyledText {
                Layout.fillWidth: true
                text: root.options.title.length > 0 ? root.options.title : Translation.tr("Countdown")
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: root.colOnCard
            }
        }

        // No date yet
        StyledText {
            visible: root.targetDate === null
            Layout.topMargin: 6
            Layout.maximumWidth: 220
            text: Translation.tr("Set a date in Settings › Widgets › Countdown")
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.small
            color: root.colOnCardVariant
        }

        // It's the day
        StyledText {
            visible: root.targetDate !== null && root.celebrating
            Layout.topMargin: 4
            text: Translation.tr("Today!")
            font {
                family: Appearance.font.family.expressive
                pixelSize: 44
                weight: Font.Medium
            }
            color: root.colAccent
        }

        RowLayout {
            visible: root.targetDate !== null && !root.celebrating
            spacing: 10
            StyledText {
                text: root.bigNumber
                font {
                    family: Appearance.font.family.expressive
                    pixelSize: 64
                    weight: Font.Medium
                }
                color: root.colAccent
            }
            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                spacing: 0
                StyledText {
                    text: root.unitText
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: root.colOnCard
                }
                StyledText {
                    visible: root.options.showHours && root.days > 0
                    text: Translation.tr("%1 h %2 min").arg(root.hours).arg(root.minutes)
                    font.family: Appearance.font.family.numbers
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: root.colOnCardVariant
                }
            }
        }

        StyledText {
            visible: root.targetDate !== null
            text: root.targetDate
                ? root.targetDate.toLocaleDateString(Qt.locale(), "d MMMM yyyy, dddd") + (root.hasTime ? `, ${root.targetDate.toLocaleTimeString(Qt.locale(), "HH:mm")}` : "")
                : ""
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.colOnCardVariant
        }
    }
}
