import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.ii.sidebarRight.quickToggles

/**
 * The quick toggles, as tiles or round buttons (Config.options.sidebar.quickToggles). The dialogs they
 * open (Wi-Fi, Bluetooth, sound, night light) are shown by the sidebar they're in.
 */
Item {
    id: root
    property Item host: null
    implicitHeight: panelLoader.item?.implicitHeight ?? 0

    function request(name) {
        root.host?.column?.dialogRequested(name);
    }

    Loader {
        id: panelLoader
        readonly property bool fillsWidth: Config.options.sidebar.quickToggles.style !== "classic"
        anchors.horizontalCenter: parent.horizontalCenter
        width: panelLoader.fillsWidth ? parent.width : (item?.implicitWidth ?? 0)
        height: parent.height
        sourceComponent: Config.options.sidebar.quickToggles.style === "classic" ? classicPanel : androidPanel
        Connections {
            target: panelLoader.item
            function onOpenAudioOutputDialog() { root.request("audioOutput") }
            function onOpenAudioInputDialog() { root.request("audioInput") }
            function onOpenBluetoothDialog() { root.request("bluetooth") }
            function onOpenNightLightDialog() { root.request("nightLight") }
            function onOpenWifiDialog() { root.request("wifi") }
        }
    }
    Component {
        id: classicPanel
        ClassicQuickPanel {}
    }
    Component {
        id: androidPanel
        AndroidQuickPanel {
            editMode: root.host?.column?.editMode ?? false
        }
    }
}
