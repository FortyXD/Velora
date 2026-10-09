import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import "../ii/sidebarRight/calendar/calendar_layout.js" as CalendarLayout

/**
 * Settings row with a date and a calendar that opens below it.
 * `dateString` is "yyyy-MM-dd" or empty; `picked` gives the new one.
 */
ColumnLayout {
    id: root
    property string label: Translation.tr("Date")
    property string icon: "event"
    property string dateString: ""
    property bool expanded: false
    signal picked(string dateString)

    readonly property bool settingsSearchable: true
    property string searchText: root.label

    readonly property var date: {
        const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(root.dateString);
        return match ? new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3])) : null;
    }
    // Month shown in the calendar
    property int viewYear: (root.date ?? new Date()).getFullYear()
    property int viewMonth: (root.date ?? new Date()).getMonth()
    readonly property var monthLayout: CalendarLayout.getCalendarLayout(new Date(root.viewYear, root.viewMonth, 1), false)
    readonly property var weekDayNames: {
        const monday = new Date(2024, 0, 1); // Monday first, like the layout
        return [...Array(7).keys()].map(i => Qt.locale().toString(new Date(monday.getTime() + i * 86400000), "ddd").substring(0, 2));
    }

    function pad(number) {
        return number.toString().padStart(2, "0");
    }
    function toDateString(date) {
        return `${date.getFullYear()}-${root.pad(date.getMonth() + 1)}-${root.pad(date.getDate())}`;
    }
    function shiftMonth(step) {
        const date = new Date(root.viewYear, root.viewMonth + step, 1);
        root.viewYear = date.getFullYear();
        root.viewMonth = date.getMonth();
    }
    // Real date of a cell in the 6×7 grid
    function cellDate(row, column) {
        const cell = root.monthLayout[row][column];
        let monthOffset = 0;
        if (cell.today === -1) monthOffset = row === 0 ? -1 : 1;
        return new Date(root.viewYear, root.viewMonth + monthOffset, cell.day);
    }

    onExpandedChanged: {
        if (!root.expanded) return;
        const shown = root.date ?? new Date();
        root.viewYear = shown.getFullYear();
        root.viewMonth = shown.getMonth();
    }

    Layout.fillWidth: true
    spacing: 0

    RippleButton { // The row
        Layout.fillWidth: true
        implicitHeight: 52
        leftPadding: 12
        rightPadding: 10
        buttonRadius: Appearance.rounding.small
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active
        onClicked: root.expanded = !root.expanded
        contentItem: RowLayout {
            spacing: 12
            ConfigIconTile {
                icon: root.icon
                active: root.date !== null
            }
            StyledText {
                Layout.fillWidth: true
                text: root.label
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer2
            }
            StyledText {
                text: root.date ? root.date.toLocaleDateString(Qt.locale(), "d MMMM yyyy, ddd") : Translation.tr("Not set")
                font.pixelSize: Appearance.font.pixelSize.small
                color: root.date ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }
            MaterialSymbol {
                text: "expand_more"
                iconSize: 22
                color: Appearance.colors.colSubtext
                rotation: root.expanded ? 180 : 0
                Behavior on rotation {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }
    }

    Revealer { // The calendar
        Layout.fillWidth: true
        vertical: true
        reveal: root.expanded

        ColumnLayout {
            width: parent.width
            spacing: 6

            RowLayout { // Month and navigation
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 10
                Layout.topMargin: 4
                StyledText {
                    Layout.fillWidth: true
                    text: new Date(root.viewYear, root.viewMonth, 1).toLocaleDateString(Qt.locale(), "MMMM yyyy")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer2
                }
                Repeater {
                    model: [{ icon: "chevron_left", step: -1 }, { icon: "chevron_right", step: 1 }]
                    delegate: RippleButton {
                        id: monthButton
                        required property var modelData
                        implicitWidth: 34
                        implicitHeight: 34
                        buttonRadius: Appearance.rounding.full
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        onClicked: root.shiftMonth(modelData.step)
                        contentItem: MaterialSymbol {
                            horizontalAlignment: Text.AlignHCenter
                            text: monthButton.modelData.icon
                            iconSize: 20
                            color: Appearance.colors.colOnLayer2
                        }
                    }
                }
            }

            GridLayout { // Days
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: 10
                columns: 7
                columnSpacing: 4
                rowSpacing: 2

                Repeater {
                    model: root.weekDayNames
                    delegate: StyledText {
                        required property string modelData
                        Layout.preferredWidth: 38
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
                Repeater {
                    model: 42
                    delegate: RippleButton {
                        id: dayButton
                        required property int index
                        readonly property var cellDate: root.cellDate(Math.floor(index / 7), index % 7)
                        readonly property bool inMonth: root.monthLayout[Math.floor(index / 7)][index % 7].today !== -1
                        readonly property bool selected: root.date !== null && cellDate.toDateString() === root.date.toDateString()
                        readonly property bool today: cellDate.toDateString() === new Date().toDateString()
                        implicitWidth: 38
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.full
                        toggled: selected
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        onClicked: {
                            root.picked(root.toDateString(cellDate));
                            root.expanded = false;
                        }
                        background: Rectangle {
                            radius: height / 2
                            color: dayButton.selected ? Appearance.colors.colPrimary
                                : dayButton.hovered ? Appearance.colors.colLayer2Hover : "transparent"
                            border.width: dayButton.today && !dayButton.selected ? 1 : 0
                            border.color: Appearance.colors.colPrimary
                        }
                        contentItem: StyledText {
                            horizontalAlignment: Text.AlignHCenter
                            text: dayButton.cellDate.getDate()
                            font.family: Appearance.font.family.numbers
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: dayButton.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                            opacity: dayButton.inMonth ? 1 : 0.35
                        }
                    }
                }
            }
        }
    }
}
