pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Rectangle {
    id: root
    required property var gesture
    required property bool shown
    property color accent: ColorUtils.mix("#75b7b4", Appearance.colors.colPrimary, 0.52)
    readonly property string direction: gesture?.direction ?? "up"
    readonly property int fingers: Math.max(1, Math.min(5, gesture?.fingers ?? 4))
    readonly property bool pinch: direction.startsWith("pinch")
    readonly property real dx: ["horizontal", "right", "swipe"].includes(direction) ? 1 : direction === "left" ? -1 : 0
    readonly property real dy: ["vertical", "up", "swipe"].includes(direction) ? -1 : direction === "down" ? 1 : 0
    property real travel: 1
    function replay() {
        swipe.stop();
        travel = 1;
        if (shown && gesture && Appearance.animationSpeed > 0) swipe.restart();
    }
    onGestureChanged: replay()
    onShownChanged: replay()
    Connections { target: Appearance; function onAnimationSpeedChanged() { root.replay(); } }
    Layout.fillWidth: true
    Layout.margins: 8
    implicitHeight: 128
    radius: Appearance.rounding.normal
    color: ColorUtils.mix(accent, Appearance.colors.colLayer1, 0.18)
    NumberAnimation { id: swipe; target: root; property: "travel"; from: 0; to: 1; duration: Appearance.scaledDuration(780); easing.type: Easing.InOutCubic }
    Rectangle {
        anchors.centerIn: parent
        width: Math.min(178, parent.width - 36)
        height: 92; radius: 13
        color: Appearance.colors.colLayer2Base; border.color: Appearance.colors.colOutlineVariant
        Rectangle { anchors.bottom: parent.bottom; anchors.bottomMargin: 15; width: parent.width - 2; x: 1; height: 1; color: Appearance.colors.colOutlineVariant }
        Repeater {
            model: root.fingers
            delegate: Item {
                required property int index
                readonly property real offset: (index - (root.fingers - 1) / 2) * 18
                readonly property real factor: root.pinch ? (root.direction === "pinchout" ? 0.6 + root.travel * 0.8 : 1.4 - root.travel * 0.8) : 1
                x: parent.width / 2 + offset * factor + (root.travel - 0.5) * root.dx * 42
                y: parent.height * 0.46 + Math.abs(offset) * 0.16 + (root.travel - 0.5) * root.dy * 32
                Rectangle {
                    x: -7 - root.travel * root.dx * 42; y: -10 - root.travel * root.dy * 32
                    width: 14; height: 20; radius: 7; color: "transparent"
                    visible: !root.pinch
                    border.color: ColorUtils.applyAlpha(root.accent, 0.45)
                }
                Rectangle { x: -7; y: -10; width: 14; height: 20; radius: 7; color: root.accent }
            }
        }
    }
    RippleButton {
        anchors.right: parent.right; anchors.rightMargin: 8; anchors.bottom: parent.bottom; anchors.bottomMargin: 8
        implicitWidth: 32; implicitHeight: 32; buttonRadius: 16
        enabled: Appearance.animationSpeed > 0
        Accessible.name: Translation.tr("Replay animation")
        colBackground: Appearance.colors.colLayer2Base
        onClicked: root.replay()
        contentItem: MaterialSymbol { text: "replay"; iconSize: 17; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; color: Appearance.colors.colOnLayer2 }
    }
}
