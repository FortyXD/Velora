pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import qs.modules.common
import qs.services

Rectangle {
    id: root

    property bool active: false
    property color accent: Appearance.colors.colPrimary
    property string text: Translation.tr("AI is thinking")
    readonly property bool animating: active && visible && (Window.window?.visible ?? false) && Appearance.animationSpeed > 0

    visible: active
    implicitWidth: content.implicitWidth + 20
    implicitHeight: 26
    radius: height / 2
    color: Qt.rgba(accent.r, accent.g, accent.b, 0.09)
    border.color: Qt.rgba(accent.r, accent.g, accent.b, 0.16)
    border.width: 1
    opacity: active ? 1 : 0
    Accessible.role: Accessible.StaticText
    Accessible.name: text

    Behavior on opacity {
        enabled: Appearance.animationSpeed > 0
        NumberAnimation { duration: Appearance.scaledDuration(160) }
    }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 7

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            Accessible.ignored: true
            Repeater {
                model: 3
                delegate: Rectangle {
                    id: dot
                    required property int index
                    width: 4
                    height: 4
                    radius: 2
                    color: root.accent
                    opacity: 0.65

                    // Render-thread transforms only; no canvas, shader, or frame timer.
                    SequentialAnimation {
                        running: root.animating
                        loops: Animation.Infinite
                        onRunningChanged: if (!running) { dot.scale = 1; dot.opacity = 0.65; }
                        PauseAnimation { duration: Math.max(1, Appearance.scaledDuration(dot.index * 140)) }
                        ParallelAnimation {
                            ScaleAnimator { target: dot; from: 0.8; to: 1.35; duration: Math.max(1, Appearance.scaledDuration(300)); easing.type: Easing.InOutSine }
                            OpacityAnimator { target: dot; from: 0.35; to: 1; duration: Math.max(1, Appearance.scaledDuration(300)); easing.type: Easing.InOutSine }
                        }
                        ParallelAnimation {
                            ScaleAnimator { target: dot; from: 1.35; to: 0.8; duration: Math.max(1, Appearance.scaledDuration(300)); easing.type: Easing.InOutSine }
                            OpacityAnimator { target: dot; from: 1; to: 0.35; duration: Math.max(1, Appearance.scaledDuration(300)); easing.type: Easing.InOutSine }
                        }
                        PauseAnimation { duration: Math.max(1, Appearance.scaledDuration((2 - dot.index) * 140 + 320)) }
                    }
                }
            }
        }
        StyledText {
            text: root.text
            textFormat: Text.PlainText
            color: root.accent
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Medium
            Accessible.ignored: true
        }
    }
}
