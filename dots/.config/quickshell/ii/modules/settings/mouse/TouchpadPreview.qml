import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Rectangle {
    id: root
    objectName: "touchpadTestArea"
    readonly property bool tap: HyprlandSettings.get("input:touchpad:tap_to_click", true)
    readonly property bool clickfinger: HyprlandSettings.get("input:touchpad:clickfinger_behavior", true)
    property string feedback: ""
    readonly property color accent: ColorUtils.mix("#7bc5ac", Appearance.colors.colPrimary, 0.55)
    Layout.fillWidth: true
    Layout.margins: 8
    implicitHeight: 112
    radius: Appearance.rounding.normal
    color: ColorUtils.mix(accent, Appearance.colors.colLayer1, 0.22)
    Rectangle {
        id: surface
        anchors.horizontalCenter: parent.horizontalCenter
        y: (parent.height - height) / 2 - 8
        width: Math.min(190, parent.width - 32); height: Math.min(105, parent.height - 32); radius: 11
        color: Appearance.colors.colLayer2Base
        border.width: 2; border.color: ColorUtils.mix(root.accent, Appearance.colors.colOutlineVariant, 0.5)
        Rectangle {
            anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 3
            width: parent.width * 0.42; height: 17; radius: 5
            opacity: (testArea.pressedButtons & Qt.RightButton) ? 1 : root.clickfinger ? 0 : 0.65
            color: root.accent
            Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
        }
        Rectangle { x: 3; y: parent.height - 22; width: parent.width - 6; height: 1; color: Appearance.colors.colOutlineVariant }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter; y: 23; spacing: 5
            Repeater {
                model: root.clickfinger ? 2 : 1
                Rectangle {
                    width: 15; height: 23; radius: 8
                    color: root.tap || testArea.pressed ? root.accent : "transparent"
                    border.color: root.accent; border.width: 2
                    Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                }
            }
        }
        StyledFlickable {
            id: scrollSample
            objectName: "touchpadTestScroll"
            x: parent.width - width - 12; y: 10; width: 4; height: parent.height - 39
            contentHeight: 640
        }
        Rectangle {
            x: scrollSample.x; y: scrollSample.y; width: scrollSample.width; height: scrollSample.height
            radius: 2; color: Appearance.colors.colOutlineVariant
            opacity: scrollFeedback.running ? 1 : 0
            Behavior on opacity { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
            Rectangle {
                width: parent.width; height: 12; radius: 2; color: root.accent
                y: (parent.height - height) * Math.max(0, Math.min(1, scrollSample.contentY / (scrollSample.contentHeight - scrollSample.height)))
            }
        }
    }
    StyledText {
        anchors.left: parent.left; anchors.leftMargin: 12; anchors.right: parent.right; anchors.rightMargin: 8
        anchors.bottom: parent.bottom; anchors.bottomMargin: 8
        text: scrollFeedback.running ? Translation.tr("Scroll: %1 px").arg(Math.round(scrollSample.contentY))
            : root.feedback || (root.clickfinger ? Translation.tr("Two-finger click") : Translation.tr("Bottom-right corner"))
        elide: Text.ElideRight; color: Appearance.colors.colOnLayer2; font.pixelSize: Appearance.font.pixelSize.smaller
    }
    MouseArea {
        id: testArea
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: event => {
            root.feedback = event.button === Qt.RightButton ? Translation.tr("Right click")
                : event.button === Qt.MiddleButton ? Translation.tr("Middle click") : Translation.tr("Left click");
            contact.x = event.x - contact.width / 2;
            contact.y = event.y - contact.height / 2;
            pulse.restart();
        }
        onWheel: event => scrollSample.wheelArea.wheel(event)
    }
    Connections { target: scrollSample.wheelArea; function onUserScrolled() { scrollFeedback.restart(); } }
    Timer { id: scrollFeedback; interval: 650 }
    Rectangle {
        id: contact
        width: 30; height: 30; radius: 15; color: "transparent"
        opacity: 0; border.color: root.accent; border.width: 2
        ParallelAnimation {
            id: pulse
            NumberAnimation { target: contact; property: "scale"; from: 0.3; to: 1.45; duration: Appearance.scaledDuration(360) }
            NumberAnimation { target: contact; property: "opacity"; from: 1; to: 0; duration: Appearance.scaledDuration(360) }
        }
    }
}
