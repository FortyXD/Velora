import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

/**
 * Read-only fact in a settings card (an address, a signal level). Clicking copies the value.
 */
ConfigNavRow {
    id: root
    property bool copied: false

    visible: root.valueText.length > 0
    trailingIcon: root.copied ? "check" : root.hovered ? "content_copy" : ""
    colBackgroundHover: Appearance.colors.colLayer2Hover
    onClicked: {
        Quickshell.clipboardText = root.valueText;
        root.copied = true;
        copiedTimer.restart();
    }

    Timer {
        id: copiedTimer
        interval: 1500
        onTriggered: root.copied = false
    }
}
