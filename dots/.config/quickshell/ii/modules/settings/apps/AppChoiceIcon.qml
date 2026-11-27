import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.modules.common.widgets

Item {
    id: root
    required property string icon
    property string symbol: ""
    implicitWidth: 26
    implicitHeight: 26

    IconImage {
        id: image
        anchors.fill: parent
        source: {
            if (root.symbol || !root.icon) return "";
            if (root.icon.startsWith("/")) return "file://" + root.icon;
            if (root.icon.startsWith("file:")) return root.icon;
            return Quickshell.iconPath(root.icon, true);
        }
    }
    MaterialSymbol {
        anchors.centerIn: parent
        visible: image.status !== Image.Ready
        text: root.symbol || "apps"
        iconSize: 24
    }
}
