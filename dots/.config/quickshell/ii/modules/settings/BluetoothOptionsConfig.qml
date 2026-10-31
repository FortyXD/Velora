import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.network

/** This computer's side of Bluetooth: its name and visibility, what happens at login, and receiving files. */
ContentPage {
    id: page
    readonly property var adapter: BluetoothManager.adapter

    ContentSection {
        icon: "computer"
        title: Translation.tr("This computer")
        visible: BluetoothManager.available

        ConfigComboRow {
            visible: BluetoothManager.adapters.length > 1
            icon: "bluetooth"
            text: Translation.tr("Adapter")
            options: BluetoothManager.adapters.map(adapter => ({ displayName: `${adapter.name} (${adapter.hci})`, value: adapter.path }))
            currentValue: page.adapter?.path ?? ""
            onSelected: value => BluetoothManager.selectedAdapter = value
        }
        ConfigTextRow {
            id: adapterName
            label: Translation.tr("Name other devices see")
            wrapMode: TextEdit.NoWrap
            Component.onCompleted: adapterName.value = page.adapter?.name ?? ""
            Connections {
                target: page
                function onAdapterChanged() {
                    if (!adapterName.textField.activeFocus) adapterName.value = page.adapter?.name ?? "";
                }
            }
            onEditingFinished: if (adapterName.value !== page.adapter?.name) BluetoothManager.setAdapterName(adapterName.value)
        }
        InfoRow {
            buttonIcon: "tag"
            title: Translation.tr("Address")
            valueText: page.adapter?.address ?? ""
        }
        ConfigSwitch {
            buttonIcon: "visibility"
            text: Translation.tr("Visible to nearby devices")
            autoToggle: false
            checked: page.adapter?.discoverable ?? false
            onClicked: BluetoothManager.setDiscoverable(!checked)
        }
        ConfigComboRow {
            icon: "timer"
            text: Translation.tr("Stay visible for")
            currentValue: page.adapter?.discoverableTimeout ?? 180
            options: [
                { displayName: Translation.tr("1 minute"), value: 60 },
                { displayName: Translation.tr("3 minutes"), value: 180 },
                { displayName: Translation.tr("10 minutes"), value: 600 },
                { displayName: Translation.tr("Until turned off"), value: 0 },
            ]
            onSelected: value => BluetoothManager.setDiscoverableTimeout(value)
        }
    }

    ContentSection {
        icon: "login"
        title: Translation.tr("When you log in")

        ConfigComboRow {
            icon: "power_settings_new"
            text: Translation.tr("Bluetooth")
            description: Translation.tr("Coming back from sleep follows the same choice, except that “Off” leaves it as it was")
            currentValue: Config.options.connectivity.bluetoothOnLogin
            options: [
                { displayName: Translation.tr("As it was, reconnecting devices"), value: "remember" },
                { displayName: Translation.tr("On"), value: "on" },
                { displayName: Translation.tr("Off"), value: "off" },
            ]
            onSelected: value => Config.options.connectivity.bluetoothOnLogin = value
        }
    }

    ContentSection {
        icon: "file_download"
        title: Translation.tr("Receiving files")

        ConfigComboRow {
            icon: "rule"
            text: Translation.tr("When a device sends a file")
            currentValue: Config.options.connectivity.bluetoothReceivePolicy
            options: [
                { displayName: Translation.tr("Ask"), value: "ask" },
                { displayName: Translation.tr("Accept from trusted devices"), value: "trusted" },
                { displayName: Translation.tr("Always accept"), value: "always" },
            ]
            onSelected: value => Config.options.connectivity.bluetoothReceivePolicy = value
        }
        ConfigNavRow {
            buttonIcon: "folder"
            title: Translation.tr("Save files in")
            valueText: ConnectivitySettings.receiveFolder
            onClicked: folderDialog.open()
        }
    }

    FolderDialog {
        id: folderDialog
        onAccepted: Config.options.connectivity.bluetoothReceiveFolder = FileUtils.trimFileProtocol(decodeURIComponent(selectedFolder.toString()))
    }
}
