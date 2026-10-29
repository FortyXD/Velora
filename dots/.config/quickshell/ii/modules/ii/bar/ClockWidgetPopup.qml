import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * Today's date over a month calendar with week numbers.
 * Scroll over it or use the arrows to see other months; the month title goes back to today.
 */
StyledPopup {
    id: root
    interactive: true

    readonly property var locale: Qt.locale(Config.options.calendar.locale)
    readonly property date today: DateTime.clock.date
    property int monthOffset: 0
    property int lastStep: 0 // Direction of the last month change, for the slide
    readonly property date shownMonth: new Date(today.getFullYear(), today.getMonth() + monthOffset, 1)
    onActiveChanged: if (!active) monthOffset = 0

    function capitalize(text) {
        return text.length > 0 ? text.charAt(0).toUpperCase() + text.slice(1) : text;
    }
    function changeMonth(step) {
        lastStep = step;
        monthOffset += step;
        if (Config.options.bar.microAnimations) monthSlide.restart();
    }
    function sameDay(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }
    // ISO 8601: weeks start on Monday, week 1 holds the first Thursday
    function isoWeek(date) {
        const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
        const weekday = d.getUTCDay() || 7;
        d.setUTCDate(d.getUTCDate() + 4 - weekday);
        const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
        return Math.ceil(((d - yearStart) / 86400000 + 1) / 7);
    }

    // Six weeks from the Monday on or before the 1st
    readonly property var weeks: {
        const first = shownMonth;
        const lead = (first.getDay() + 6) % 7;
        const result = [];
        for (let w = 0; w < 6; w++) {
            const days = [];
            for (let d = 0; d < 7; d++) {
                const date = new Date(first.getFullYear(), first.getMonth(), 1 - lead + w * 7 + d);
                days.push({
                    day: date.getDate(),
                    inMonth: date.getMonth() === first.getMonth(),
                    isToday: sameDay(date, today),
                    weekend: d >= 5
                });
            }
            result.push({ week: isoWeek(new Date(first.getFullYear(), first.getMonth(), 1 - lead + w * 7)), days: days });
        }
        return result;
    }
    // Monday first
    readonly property var weekdayNames: [1, 2, 3, 4, 5, 6, 0].map(d => capitalize(locale.dayName(d, Locale.ShortFormat).slice(0, 2)))

    readonly property real cellSize: 30

    component NavButton: RippleButton {
        id: navButton
        required property string iconName
        implicitWidth: 28
        implicitHeight: 28
        buttonRadius: Appearance.rounding.full
        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            text: navButton.iconName
            iconSize: Appearance.font.pixelSize.larger
            color: Appearance.colors.colOnSurfaceVariant
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 10

        // Today
        ColumnLayout {
            spacing: -2
            StyledText {
                text: root.capitalize(root.locale.toString(root.today, "dddd"))
                font.pixelSize: Appearance.popup.titleSize
                font.weight: Font.DemiBold
                color: Appearance.popup.colText
            }
            StyledText {
                text: root.locale.toString(root.today, "d MMMM yyyy")
                font.pixelSize: Appearance.popup.textSize
                color: Appearance.popup.colSubtext
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Appearance.colors.colOutlineVariant
        }

        // Month navigation
        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            NavButton {
                iconName: "chevron_left"
                onClicked: root.changeMonth(-1)
            }
            RippleButton {
                id: monthTitleButton
                Layout.fillWidth: true
                implicitHeight: 28
                buttonRadius: Appearance.rounding.full
                onClicked: if (root.monthOffset !== 0) root.changeMonth(-root.monthOffset)
                contentItem: StyledText {
                    horizontalAlignment: Text.AlignHCenter
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurfaceVariant
                    text: `${root.capitalize(root.locale.standaloneMonthName(root.shownMonth.getMonth(), Locale.LongFormat))} ${root.shownMonth.getFullYear()}`
                }
            }
            NavButton {
                iconName: "chevron_right"
                onClicked: root.changeMonth(1)
            }
        }

        // Calendar
        Item {
            id: calendarArea
            implicitWidth: calendarGrid.implicitWidth
            implicitHeight: calendarGrid.implicitHeight

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => root.changeMonth(event.angleDelta.y < 0 ? 1 : -1)
            }

            ParallelAnimation {
                id: monthSlide
                NumberAnimation { target: calendarGrid; property: "opacity"; from: 0.3; to: 1; duration: 220; easing.type: Easing.OutCubic }
                NumberAnimation { target: gridTranslate; property: "x"; from: 14 * root.lastStep; to: 0; duration: 260; easing.type: Easing.OutCubic }
            }

            GridLayout {
                id: calendarGrid
                columns: 8
                rowSpacing: 0
                columnSpacing: 0
                transform: Translate { id: gridTranslate }

                // Header: week number column, then weekday names
                StyledText {
                    Layout.preferredWidth: root.cellSize
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOutline
                    text: "#"
                }
                Repeater {
                    model: root.weekdayNames
                    delegate: StyledText {
                        required property string modelData
                        required property int index
                        Layout.preferredWidth: root.cellSize
                        Layout.preferredHeight: root.cellSize - 6
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: index >= 5 ? Appearance.colors.colTertiary : Appearance.colors.colSubtext
                        text: modelData
                    }
                }

                Repeater {
                    model: root.weeks
                    delegate: Repeater {
                        id: weekRow
                        required property var modelData
                        // Week number, then the seven days
                        model: [{ weekNumber: weekRow.modelData.week }, ...weekRow.modelData.days]
                        delegate: Item {
                            id: cell
                            required property var modelData
                            readonly property bool isWeekNumber: modelData.weekNumber !== undefined
                            Layout.preferredWidth: root.cellSize
                            Layout.preferredHeight: root.cellSize

                            Rectangle {
                                anchors.centerIn: parent
                                width: root.cellSize - 4
                                height: width
                                radius: width / 2
                                visible: !cell.isWeekNumber && cell.modelData.isToday
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                anchors.centerIn: parent
                                font.pixelSize: cell.isWeekNumber ? Appearance.font.pixelSize.smallest : Appearance.font.pixelSize.small
                                font.weight: !cell.isWeekNumber && cell.modelData.isToday ? Font.DemiBold : Font.Normal
                                color: cell.isWeekNumber ? Appearance.colors.colOutline
                                    : cell.modelData.isToday ? Appearance.colors.colOnPrimary
                                    : !cell.modelData.inMonth ? Appearance.colors.colOutlineVariant
                                    : cell.modelData.weekend ? Appearance.colors.colTertiary
                                    : Appearance.colors.colOnSurfaceVariant
                                text: cell.isWeekNumber ? cell.modelData.weekNumber : cell.modelData.day
                            }
                        }
                    }
                }
            }
        }
    }
}
