import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.background.widgets
import "../../../sidebarRight/calendar/calendar_layout.js" as CalendarLayout

/**
 * Month view. Scroll to change month, click the title to return to the current one.
 */
DesktopWidgetCard {
    id: root
    configEntryName: "calendar"

    property int monthShift: 0
    // Recomputed when the day changes
    readonly property int today: DateTime.clock.date.getDate()
    readonly property var viewingDate: {
        root.today; // Dependency
        return CalendarLayout.getDateInXMonthsTime(root.monthShift);
    }
    readonly property var calendarLayout: CalendarLayout.getCalendarLayout(root.viewingDate, root.monthShift === 0)
    readonly property bool highlightWeekends: Config.options.background.widgets.calendar.highlightWeekends
    readonly property var weekDayNames: {
        // Monday first, like the layout
        const monday = new Date(2024, 0, 1);
        return [...Array(7).keys()].map(i => Qt.locale().toString(new Date(monday.getTime() + i * 86400000), "ddd").substring(0, 2));
    }

    onWheel: event => {
        if (event.angleDelta.y > 0) root.monthShift--;
        else if (event.angleDelta.y < 0) root.monthShift++;
    }

    ColumnLayout {
        anchors.fill: parent
        implicitWidth: 7 * 36 + 6 * 2
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            RippleButton {
                id: titleButton
                Layout.fillWidth: true
                implicitHeight: 34
                leftPadding: 8
                buttonRadius: Appearance.rounding.full
                colBackgroundHover: root.colLayer
                colRipple: root.colLayer
                onClicked: root.monthShift = 0
                contentItem: StyledText {
                    text: `${root.monthShift !== 0 ? "• " : ""}${root.viewingDate.toLocaleDateString(Qt.locale(), "MMMM yyyy")}`
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: root.colOnCard
                }
            }
            Repeater {
                model: [
                    { icon: "chevron_left", step: -1 },
                    { icon: "chevron_right", step: 1 }
                ]
                delegate: RippleButton {
                    id: stepButton
                    required property var modelData
                    implicitWidth: 34
                    implicitHeight: 34
                    buttonRadius: Appearance.rounding.full
                    colBackgroundHover: root.colLayer
                    colRipple: root.colLayer
                    onClicked: root.monthShift += modelData.step
                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        text: stepButton.modelData.icon
                        iconSize: 20
                        color: root.colOnCard
                    }
                }
            }
        }

        GridLayout {
            Layout.alignment: Qt.AlignHCenter
            columns: 7
            columnSpacing: 2
            rowSpacing: 2

            Repeater {
                model: root.weekDayNames
                delegate: StyledText {
                    required property string modelData
                    required property int index
                    Layout.preferredWidth: 36
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: (root.highlightWeekends && index >= 5) ? root.colAccent : root.colOnCardVariant
                }
            }

            Repeater {
                model: 42
                delegate: Item {
                    id: dayCell
                    required property int index
                    readonly property var cell: root.calendarLayout[Math.floor(index / 7)][index % 7]
                    readonly property bool isToday: cell.today === 1
                    readonly property bool inMonth: cell.today !== -1
                    readonly property bool weekend: index % 7 >= 5
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 32

                    Rectangle {
                        anchors.centerIn: parent
                        width: 32
                        height: 32
                        radius: width / 2
                        visible: dayCell.isToday
                        color: root.colAccent
                    }
                    StyledText {
                        anchors.centerIn: parent
                        text: dayCell.cell.day
                        font.family: Appearance.font.family.numbers
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: dayCell.isToday ? Font.Bold : Font.Normal
                        color: dayCell.isToday ? root.colOnAccent
                            : (root.highlightWeekends && dayCell.weekend && dayCell.inMonth) ? root.colAccent
                            : root.colOnCard
                        opacity: dayCell.inMonth ? 1 : 0.35
                    }
                }
            }
        }
    }
}
