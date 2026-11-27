pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Rectangle {
    id: root
    readonly property bool settingsSection: true
    readonly property bool settingsSearchable: true
    readonly property string title: Translation.tr("Quick settings")
    readonly property string icon: "instant_mix"
    readonly property string searchText: title
    property string quietError: ""

    Layout.fillWidth: true
    implicitHeight: body.implicitHeight + 24
    color: Appearance.colors.colLayer2
    radius: Appearance.rounding.normal

    Process {
        id: quietCommand
        onExited: (code, status) => {
            if (code !== 0 || status !== 0) root.quietError = Translation.tr("Could not reach the running shell.");
        }
    }
    ColumnLayout {
        id: body
        x: 10; y: 12; width: root.width - 20
        spacing: 5
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 6
            Layout.rightMargin: 2
            StyledText {
                Layout.fillWidth: true
                text: root.title
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
            }
            SettingsAction {
                id: monitor
                objectName: "openSystemMonitor"
                readonly property bool settingsSearchable: true
                readonly property string searchText: text + " " + Translation.tr("Running apps and processes")
                readonly property string buttonIcon: "monitoring"
                text: Translation.tr("System monitor")
                Accessible.description: Translation.tr("Running apps and processes")
                implicitWidth: contentItem.implicitWidth + 12
                implicitHeight: 32
                horizontalPadding: 6
                onClicked: Session.launchTaskManager()
                contentItem: RowLayout {
                    spacing: 5
                    MaterialSymbol { text: "monitoring"; iconSize: 17; color: Appearance.colors.colPrimary }
                    StyledText { text: monitor.text; font.pixelSize: Appearance.font.pixelSize.smallie; color: Appearance.colors.colPrimary }
                    MaterialSymbol { text: "open_in_new"; iconSize: 13; color: Appearance.colors.colPrimary }
                }
            }
        }
        Rectangle { Layout.fillWidth: true; Layout.leftMargin: 6; Layout.rightMargin: 6; implicitHeight: 1; color: Appearance.colors.colOutlineVariant }
        GridLayout {
            Layout.fillWidth: true
            columns: root.width >= 560 ? 2 : 1
            uniformCellWidths: true
            columnSpacing: 10
            rowSpacing: 2
            component QuickSwitch: ConfigSwitch {
                Layout.minimumWidth: 0
                Layout.preferredWidth: 1
                autoToggle: false
                leftPadding: 6
                rightPadding: 7
                Accessible.name: text
                Accessible.description: description
                Accessible.role: Accessible.CheckBox
                Accessible.checked: checked
                Keys.onReturnPressed: click()
                Keys.onEnterPressed: click()
            }
            QuickSwitch {
                objectName: "generalQuietMode"
                text: Translation.tr("Do not disturb")
                buttonIcon: checked ? "notifications_paused" : "notifications"
                checked: NotificationPreferences.silent
                enabled: !quietCommand.running
                description: checked && NotificationPreferences.quietEnd > 0 && !NotificationPreferences.state.silent
                    ? Translation.tr("Until %1").arg(Qt.formatTime(new Date(NotificationPreferences.quietEnd), "HH:mm"))
                    : checked ? Translation.tr("Until I turn it off") : Translation.tr("Banners are on")
                onClicked: {
                    root.quietError = "";
                    quietCommand.command = ["qs", "-c", "ii", "ipc", "call", "notifications", "setSilent", NotificationPreferences.silent ? "false" : "true"];
                    quietCommand.running = true;
                }
            }
            QuickSwitch {
                objectName: "generalEnergySaving"
                text: Translation.tr("Energy saving")
                buttonIcon: "energy_savings_leaf"
                checked: PowerSaving.active
                description: PowerSaving.statusText
                onClicked: PowerSaving.toggle()
            }
        }
        StyledText {
            visible: !!root.quietError
            Layout.leftMargin: 6
            Layout.fillWidth: true
            text: root.quietError
            wrapMode: Text.Wrap
            color: Appearance.colors.colError
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }
}
