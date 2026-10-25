import QtQuick
import qs.modules.common

/**
 * One of several tabs stacked in the same place on a settings page. The others stay laid out and
 * "visible" (only transparent and blocked), so settings search still finds their options; revealing
 * one of them asks the page to switch tabs.
 */
Item {
    id: root
    required property string key
    property string current: ""
    readonly property bool shown: root.key === root.current

    signal revealRequested(string key)

    function settingsReveal() {
        if (root.shown) return false;
        root.revealRequested(root.key);
        return true;
    }

    opacity: root.shown ? 1 : 0
    z: root.shown ? 1 : 0
    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    MouseArea { // A tab behind the current one takes no clicks, hover or wheel
        anchors.fill: parent
        z: 1000
        visible: !root.shown
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        onWheel: wheel => wheel.accepted = true
    }
}
