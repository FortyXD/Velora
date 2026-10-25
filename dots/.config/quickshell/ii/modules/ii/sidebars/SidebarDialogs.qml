import QtQuick
import Quickshell.Bluetooth
import qs.services
import qs.modules.ii.sidebarRight.bluetoothDevices
import qs.modules.ii.sidebarRight.nightLight
import qs.modules.ii.sidebarRight.volumeMixer
import qs.modules.ii.sidebarRight.wifiNetworks

/**
 * The dialogs quick toggles open (Wi-Fi, Bluetooth, sound, night light), over the sidebar the toggles are in.
 * show("wifi" | "bluetooth" | "audioOutput" | "audioInput" | "nightLight"); all close with the sidebar.
 */
Item {
    id: root
    property bool open: false
    property bool showAudioOutputDialog: false
    property bool showAudioInputDialog: false
    property bool showBluetoothDialog: false
    property bool showNightLightDialog: false
    property bool showWifiDialog: false

    function show(name) {
        const key = ({ "wifi": "showWifiDialog", "bluetooth": "showBluetoothDialog", "audioOutput": "showAudioOutputDialog",
            "audioInput": "showAudioInputDialog", "nightLight": "showNightLightDialog" })[name];
        if (key) root[key] = true;
    }

    onOpenChanged: {
        if (root.open) return;
        root.showWifiDialog = false;
        root.showBluetoothDialog = false;
        root.showAudioOutputDialog = false;
        root.showAudioInputDialog = false;
        root.showNightLightDialog = false;
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
}
