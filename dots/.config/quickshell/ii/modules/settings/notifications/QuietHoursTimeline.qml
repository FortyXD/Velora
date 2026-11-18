pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

SettingsBranchLink {
    id: root
    readonly property var schedule: NotificationPreferences.schedule
    readonly property color accent: ColorUtils.mix("#a99ce1", Appearance.colors.colPrimary, 0.55)
    readonly property int fromMinute: NotificationPreferences.minutesOfDay(schedule.from)
    readonly property int toMinute: NotificationPreferences.minutesOfDay(schedule.to)
    readonly property int currentMinute: NotificationPreferences.clock.hours * 60 + NotificationPreferences.clock.minutes
    title: Translation.tr("Quiet hours")
    summary: schedule.enabled ? schedule.from + " – " + schedule.to : Translation.tr("Off")
    Accessible.name: title + " · " + summary
    implicitHeight: body.implicitHeight + 20
    contentItem: ColumnLayout {
        id: body
        spacing: 6
        RowLayout {
            Layout.fillWidth: true
            MaterialSymbol { text: "schedule"; iconSize: 16; color: Appearance.colors.colSubtext }
            StyledText { Layout.fillWidth: true; text: root.title; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer2 }
            StyledText { text: root.summary; font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext }
            MaterialSymbol { text: "chevron_right"; iconSize: 16; color: Appearance.colors.colSubtext }
        }
        Rectangle {
            id: day
            visible: root.schedule.enabled
            Layout.fillWidth: true; implicitHeight: 8; radius: 4
            color: Appearance.colors.colLayer3
            readonly property var spans: {
                const a = root.fromMinute, b = root.toMinute;
                if (a < 0 || b < 0 || a === b) return [];
                return a < b ? [[a,b]] : [[0,b],[a,1440]];
            }
            Repeater {
                model: day.spans
                Rectangle {
                    required property var modelData
                    x: day.width * modelData[0] / 1440
                    width: day.width * (modelData[1] - modelData[0]) / 1440
                    height: day.height; radius: height / 2
                    color: root.accent
                }
            }
            Rectangle {
                x: Math.min(day.width - width, day.width * root.currentMinute / 1440)
                anchors.verticalCenter: parent.verticalCenter; width: 2; height: 14; radius: 1
                color: Appearance.colors.colOnLayer2
            }
        }
        Item {
            id: labels
            visible: root.schedule.enabled
            Layout.fillWidth: true
            implicitHeight: childrenRect.height
            Repeater {
                model: ["00", "06", "12", "18", "24"]
                StyledText {
                    required property int index
                    required property string modelData
                    x: Math.max(0, Math.min(labels.width - width, labels.width * index / 4 - width / 2))
                    text: modelData; font.pixelSize: Appearance.font.pixelSize.smallest; color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
