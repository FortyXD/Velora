import QtQuick
import QtQuick.Controls
import Quickshell
import qs.modules.common

Popup {
    id: root
    property Item pane
    parent: pane ?? Overlay.overlay
    anchors.centerIn: parent
    popupType: Popup.Item
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    Overlay.modal: Item {
        id: dimmer
        // Qt checks the dimmer's containment when routing input outside a modal popup.
        containmentMask: surface
        TransformWatcher { id: mapping; a: dimmer; b: root.parent }
        Rectangle {
            id: surface
            objectName: "settingsPopupShade"
            readonly property rect bounds: {
                mapping.transform;
                const pane = root.parent;
                return pane ? pane.mapToItem(dimmer, 0, 0, pane.width, pane.height) : Qt.rect(0, 0, 0, 0);
            }
            x: bounds.x
            y: bounds.y
            width: bounds.width
            height: bounds.height
            radius: root.pane ? Appearance.rounding.normal : 0
            color: Appearance.colors.colScrim
        }
        Behavior on opacity { NumberAnimation { duration: Appearance.scaledDuration(180) } }
    }
    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Appearance.scaledDuration(180); easing.type: Easing.OutCubic }
        NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: Appearance.scaledDuration(220); easing.type: Easing.OutCubic }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; to: 0; duration: Appearance.scaledDuration(140); easing.type: Easing.InCubic }
        NumberAnimation { property: "scale"; to: 0.97; duration: Appearance.scaledDuration(140); easing.type: Easing.InCubic }
    }
}
