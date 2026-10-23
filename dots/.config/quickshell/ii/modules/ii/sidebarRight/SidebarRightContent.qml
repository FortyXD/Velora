import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland

import qs.modules.ii.sidebarRight.quickToggles
import qs.modules.ii.sidebarRight.quickToggles.classicStyle

import qs.modules.ii.sidebarRight.bluetoothDevices
import qs.modules.ii.sidebarRight.nightLight
import qs.modules.ii.sidebarRight.volumeMixer
import qs.modules.ii.sidebarRight.wifiNetworks

Item {
    id: root
    property int sidebarWidth: Appearance.sizes.sidebarWidth
    property int sidebarPadding: 10
    property string settingsQmlPath: Quickshell.shellPath("settings.qml")
    property bool showAudioOutputDialog: false
    property bool showAudioInputDialog: false
    property bool showBluetoothDialog: false
    property bool showNightLightDialog: false
    property bool showWifiDialog: false
    property bool editMode: false

    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (!GlobalStates.sidebarRightOpen) {
                root.showWifiDialog = false;
                root.showBluetoothDialog = false;
                root.showAudioOutputDialog = false;
                root.showAudioInputDialog = false;
            }
        }
    }

    implicitHeight: sidebarRightBackground.implicitHeight
    implicitWidth: sidebarRightBackground.implicitWidth

    StyledRectangularShadow {
        target: sidebarRightBackground
    }
    Rectangle {
        id: sidebarRightBackground

        anchors.fill: parent
        implicitHeight: parent.height - Appearance.sizes.hyprlandGapsOut * 2
        implicitWidth: sidebarWidth - Appearance.sizes.hyprlandGapsOut * 2
        color: Appearance.colors.colLayer0
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
        radius: Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1

        ColumnLayout {
            id: sectionsColumn
            anchors.fill: parent
            anchors.margins: sidebarPadding
            spacing: sidebarPadding

            SystemButtonRow {
                visible: SidebarLayout.sectionShown("header")
                Layout.fillHeight: false
                Layout.fillWidth: true
                Layout.topMargin: 5
                Layout.bottomMargin: 0
            }

            // The other sections in the order of Config.options.sidebar.right.sections
            Repeater {
                model: SidebarLayout.sections.filter(section => section.type !== "header" && SidebarLayout.sectionShown(section.type)).map(section => section.type)
                delegate: Loader {
                    id: sectionLoader
                    required property string modelData
                    readonly property bool fills: modelData === root.fillingSection
                    Layout.fillWidth: modelData !== "toggles" || (item?.panelFillsWidth ?? true)
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillHeight: sectionLoader.fills
                    Layout.preferredHeight: sectionLoader.fills ? -1 : (item?.implicitHeight ?? 0)
                    active: modelData !== "sliders" || root.slidersWanted
                    visible: active
                    sourceComponent: ({
                        "sliders": slidersSection,
                        "toggles": togglesSection,
                        "notifications": notificationsSection,
                        "widgets": widgetsSection
                    })[modelData] ?? null
                }
            }

            // Keeps the sections at the top when none of them takes the free height
            Item {
                visible: root.fillingSection.length === 0
                Layout.fillHeight: true
            }
        }
    }

    // The notifications take the free height; without them the calendar and tools do
    readonly property string fillingSection: SidebarLayout.sectionShown("notifications") ? "notifications"
        : SidebarLayout.sectionShown("widgets") ? "widgets" : ""
    readonly property bool slidersWanted: {
        const sliders = Config.options.sidebar.quickSliders;
        return sliders.showMic || sliders.showVolume || sliders.showBrightness;
    }

    Component {
        id: slidersSection
        QuickSliders {}
    }
    Component {
        id: togglesSection
        Loader {
            id: quickPanelLoader
            readonly property bool panelFillsWidth: item?.Layout.fillWidth ?? false
            sourceComponent: Config.options.sidebar.quickToggles.style === "classic" ? classicPanel : androidPanel
            Connections {
                target: quickPanelLoader.item
                function onOpenAudioOutputDialog() {
                    root.showAudioOutputDialog = true;
                }
                function onOpenAudioInputDialog() {
                    root.showAudioInputDialog = true;
                }
                function onOpenBluetoothDialog() {
                    root.showBluetoothDialog = true;
                }
                function onOpenNightLightDialog() {
                    root.showNightLightDialog = true;
                }
                function onOpenWifiDialog() {
                    root.showWifiDialog = true;
                }
            }
        }
    }
    Component {
        id: classicPanel
        ClassicQuickPanel {}
    }
    Component {
        id: androidPanel
        AndroidQuickPanel {
            editMode: root.editMode
        }
    }
    Component {
        id: notificationsSection
        CenterWidgetGroup {}
    }
    Component {
        id: widgetsSection
        BottomWidgetGroup {
            availableHeight: sectionsColumn.height
        }
    }

    ToggleDialog {
        shownPropertyString: "showAudioOutputDialog"
        dialog: VolumeDialog {
            isSink: true
        }
    }

    ToggleDialog {
        shownPropertyString: "showAudioInputDialog"
        dialog: VolumeDialog {
            isSink: false
        }
    }

    ToggleDialog {
        shownPropertyString: "showBluetoothDialog"
        dialog: BluetoothDialog {}
        onShownChanged: {
            if (!shown) {
                if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.discovering = false;
            } else {
                if (Bluetooth.defaultAdapter) {
                    Bluetooth.defaultAdapter.enabled = true;
                    Bluetooth.defaultAdapter.discovering = true;
                }
            }
        }
    }

    ToggleDialog {
        shownPropertyString: "showNightLightDialog"
        dialog: NightLightDialog {}
    }

    ToggleDialog {
        shownPropertyString: "showWifiDialog"
        dialog: WifiDialog {}
        onShownChanged: {
            if (!shown) {
                Network.cancelPasswordPrompt();
                return;
            }
            Network.update();
            Network.rescanWifi();
        }
    }

    component ToggleDialog: Loader {
        id: toggleDialogLoader
        required property string shownPropertyString
        property alias dialog: toggleDialogLoader.sourceComponent
        readonly property bool shown: root[shownPropertyString]
        anchors.fill: parent

        onShownChanged: if (shown) toggleDialogLoader.active = true;
        active: shown
        onActiveChanged: {
            if (active) {
                item.show = true;
                item.forceActiveFocus();
            }
        }
        Connections {
            target: toggleDialogLoader.item
            function onDismiss() {
                toggleDialogLoader.item.show = false
                root[toggleDialogLoader.shownPropertyString] = false;
            }
            function onVisibleChanged() {
                if (!toggleDialogLoader.item.visible && !root[toggleDialogLoader.shownPropertyString]) toggleDialogLoader.active = false;
            }
        }
    }

    component SystemButtonRow: Item {
        id: systemButtonRow
        implicitHeight: Math.max(uptimeContainer.implicitHeight, systemButtonsRow.implicitHeight)

        readonly property var buttons: Config.options.sidebar.right.header.buttons
        Rectangle {
            id: uptimeContainer
            visible: Config.options.sidebar.right.header.showUptime
            anchors {
                top: parent.top
                bottom: parent.bottom
                left: parent.left
            }
            color: Appearance.colors.colLayer1
            radius: height / 2
            implicitWidth: uptimeRow.implicitWidth + 24
            implicitHeight: uptimeRow.implicitHeight + 8
            
            Row {
                id: uptimeRow
                anchors.centerIn: parent
                spacing: 8
                CustomIcon {
                    id: distroIcon
                    anchors.verticalCenter: parent.verticalCenter
                    width: 25
                    height: 25
                    source: SystemInfo.distroIcon
                    colorize: true
                    color: Appearance.colors.colOnLayer0
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer0
                    text: Translation.tr("Up %1").arg(DateTime.uptime)
                    textFormat: Text.MarkdownText
                }
            }
        }

        ButtonGroup {
            id: systemButtonsRow
            anchors {
                top: parent.top
                bottom: parent.bottom
                right: parent.right
            }
            color: Appearance.colors.colLayer1
            padding: 4

            QuickToggleButton {
                toggled: root.editMode
                visible: Config.options.sidebar.quickToggles.style === "android" && systemButtonRow.buttons.includes("edit")
                buttonIcon: "edit"
                onClicked: root.editMode = !root.editMode
                StyledToolTip {
                    text: Translation.tr("Edit quick toggles") + (root.editMode ? Translation.tr("\nLMB to enable/disable\nRMB to toggle size\nScroll to swap position") : "")
                }
            }
            QuickToggleButton {
                toggled: false
                visible: systemButtonRow.buttons.includes("reload")
                buttonIcon: "restart_alt"
                onClicked: {
                    Hyprland.dispatch(`hl.dsp.exec_cmd("hyprctl reload")`);
                    Quickshell.reload(true);
                }
                StyledToolTip {
                    text: Translation.tr("Reload Hyprland & Quickshell")
                }
            }
            QuickToggleButton {
                toggled: false
                visible: systemButtonRow.buttons.includes("settings")
                buttonIcon: "settings"
                onClicked: {
                    GlobalStates.sidebarRightOpen = false;
                    Quickshell.execDetached(["qs", "-p", root.settingsQmlPath]);
                }
                StyledToolTip {
                    text: Translation.tr("Settings")
                }
            }
            QuickToggleButton {
                toggled: false
                visible: systemButtonRow.buttons.includes("session")
                buttonIcon: "power_settings_new"
                onClicked: {
                    GlobalStates.sessionOpen = true;
                }
                StyledToolTip {
                    text: Translation.tr("Session")
                }
            }
        }
    }
}
