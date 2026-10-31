import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.network

/** One Bluetooth device: everything known about it and all that can be done with it, as in bluedevil. */
ContentPage {
    id: page
    readonly property var device: BluetoothManager.device
    readonly property string path: page.device?.path ?? ""
    readonly property string errorText: BluetoothManager.errors[page.path] ?? ""
    readonly property bool busy: BluetoothManager.busy[page.path] === true
    readonly property bool sendingHere: BluetoothManager.sendingTo.length > 0 && BluetoothManager.sendingTo === page.device?.address

    // Background loading can run before pageShown is assigned. Only the device page itself may
    // redirect to the device list; preloading it must never change another page's navigation.
    function returnToDevicesIfMissing(): void {
        const window = ApplicationWindow.window;
        if (page.device === null && page.pageShown && window?.currentPageData?.key === "bluetooth-device") window.openPage("bluetooth");
    }
    onDeviceChanged: Qt.callLater(page.returnToDevicesIfMissing)
    onPageShownChanged: Qt.callLater(page.returnToDevicesIfMissing)

    NoticeBox {
        visible: page.errorText.length > 0 || BluetoothManager.sendError.length > 0
        Layout.fillWidth: true
        materialIcon: "error"
        text: page.errorText || BluetoothManager.sendError
    }

    NoticeBox {
        visible: page.device?.blocked ?? false
        Layout.fillWidth: true
        materialIcon: "block"
        text: Translation.tr("This device is blocked. Unblock it below to connect to it.")
    }

    ContentSection {
        icon: BluetoothManager.typeSymbol(page.device?.deviceType ?? "")
        title: page.device?.name ?? ""
        visible: page.device !== null

        ConfigTextRow {
            id: nameField
            label: Translation.tr("Name")
            wrapMode: TextEdit.NoWrap
            Component.onCompleted: nameField.value = page.device?.name ?? ""
            Connections {
                target: page
                function onPathChanged() {
                    nameField.value = page.device?.name ?? "";
                }
            }
            onEditingFinished: {
                if (nameField.value.length > 0 && nameField.value !== page.device?.name) BluetoothManager.rename(page.path, nameField.value);
            }
        }
        InfoRow {
            buttonIcon: "category"
            title: Translation.tr("Type")
            valueText: BluetoothManager.typeLabel(page.device?.deviceType ?? "")
        }
        InfoRow {
            buttonIcon: "battery_android_full"
            title: Translation.tr("Battery")
            valueText: (page.device?.battery ?? null) !== null ? `${page.device.battery}%` : ""
        }
        InfoRow {
            buttonIcon: "tag"
            title: Translation.tr("Address")
            valueText: page.device?.address ?? ""
        }
        InfoRow {
            buttonIcon: "bluetooth"
            title: Translation.tr("Adapter")
            valueText: page.device?.adapterName ?? ""
        }
        InfoRow {
            buttonIcon: "extension"
            title: Translation.tr("What it can do")
            valueText: (page.device?.services ?? []).map(service => Translation.tr(service)).join(", ")
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 8
            spacing: 6
            DialogButton {
                enabled: !page.busy && !(page.device?.blocked ?? false)
                buttonText: page.device?.connected ? Translation.tr("Disconnect") : Translation.tr("Connect")
                onClicked: page.device.connected ? BluetoothManager.disconnectDevice(page.path) : BluetoothManager.connectDevice(page.path)
            }
            DialogButton {
                visible: (page.device?.canReceiveFiles ?? false) && (page.device?.connected ?? false)
                enabled: !page.sendingHere
                buttonText: Translation.tr("Send a file…")
                onClicked: fileDialog.open()
            }
            Item {
                Layout.fillWidth: true
            }
            ForgetButton {
                label: Translation.tr("Forget this device")
                onConfirmed: BluetoothManager.forget(page.path)
            }
        }

        StyledText {
            visible: page.sendingHere
            Layout.fillWidth: true
            Layout.margins: 12
            text: Translation.tr("Sending %1: %2 of %3").arg(BluetoothManager.sendingName).arg(ConnectivityPrompts.sizeText(BluetoothManager.sendingDone)).arg(ConnectivityPrompts.sizeText(BluetoothManager.sendingSize))
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }
    }

    ContentSection {
        icon: "tune"
        title: Translation.tr("Options")
        visible: page.device !== null

        ConfigSwitch {
            buttonIcon: "autorenew"
            text: Translation.tr("Trusted")
            description: Translation.tr("It connects by itself and doesn't have to ask")
            autoToggle: false
            checked: page.device?.trusted ?? false
            onClicked: BluetoothManager.setTrusted(page.path, !checked)
        }
        ConfigSwitch {
            buttonIcon: "block"
            text: Translation.tr("Blocked")
            description: Translation.tr("Refuses every connection from this device")
            autoToggle: false
            checked: page.device?.blocked ?? false
            onClicked: BluetoothManager.setBlocked(page.path, !checked)
        }
    }

    FileDialog {
        id: fileDialog
        fileMode: FileDialog.OpenFiles
        onAccepted: BluetoothManager.sendFiles(page.device.address, selectedFiles.map(file => FileUtils.trimFileProtocol(decodeURIComponent(file.toString()))))
    }
}
