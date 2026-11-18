pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Rectangle {
    id: pad
    objectName: "pointerTestArea"
    readonly property color accent: ColorUtils.mix("#89adf4", Appearance.colors.colPrimary, 0.52)
    Layout.fillWidth: true
    Layout.margins: 8
    implicitHeight: 112
    radius: Appearance.rounding.normal
    color: ColorUtils.mix(accent, Appearance.colors.colLayer1, 0.22)
    clip: true
    property var trail: []
    property string lastClick: ""
    function sample(x, y) {
        const points = trail;
        const last = points[points.length - 1];
        if (last && Math.hypot(last.x - x, last.y - y) < 3) return;
        points.push({x, y});
        if (points.length > 28) points.shift();
        grid.requestPaint();
    }
    Accessible.name: Translation.tr("Click or scroll inside the preview to try your settings.")

    Canvas {
        id: grid
        anchors.fill: parent
        readonly property color ink: pad.accent
        onInkChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            ctx.fillStyle = ColorUtils.applyAlpha(ink, 0.30);
            for (let x = 10; x < width; x += 16)
                for (let y = 10; y < height; y += 16) ctx.fillRect(x, y, 1.3, 1.3);
            const points = pad.trail;
            if (points.length < 2) return;
            ctx.lineWidth = 2.6;
            ctx.lineCap = "round";
            for (let i = 1; i < points.length; i++) {
                ctx.strokeStyle = ColorUtils.applyAlpha(ink, i / points.length);
                ctx.beginPath();
                ctx.moveTo(points[i-1].x, points[i-1].y);
                ctx.lineTo(points[i].x, points[i].y);
                ctx.stroke();
            }
        }
    }
    Rectangle {
        id: mouseBody
        x: Math.max(16, pad.width * 0.38 - width / 2)
        y: (pad.height - height) / 2 - 8
        width: 65; height: 94; radius: 30
        color: Appearance.colors.colLayer2Base
        border.width: 2; border.color: ColorUtils.mix(pad.accent, Appearance.colors.colOutlineVariant, 0.42)
        Repeater {
            model: 2
            Rectangle {
                required property int index
                readonly property bool held: (mouse.pressedButtons & (index === 0 ? Qt.LeftButton : Qt.RightButton)) !== 0
                x: index === 0 ? 3 : mouseBody.width / 2 + 1
                y: 3; width: (mouseBody.width - 8) / 2; height: 41
                topLeftRadius: index === 0 ? 27 : 3
                topRightRadius: index === 1 ? 27 : 3
                bottomLeftRadius: 3; bottomRightRadius: 3
                color: held ? pad.accent : ColorUtils.mix(pad.accent, mouseBody.color, 0.18)
                Behavior on color { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
            }
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 14; width: 10; height: 22; radius: 5
            color: wheelFeedback.running || (mouse.pressedButtons & Qt.MiddleButton) ? pad.accent : Appearance.colors.colSubtext
            Column {
                anchors.centerIn: parent; spacing: 2
                Repeater {
                    model: 3
                    Rectangle { width: 4; height: 1; color: mouseBody.color }
                }
            }
        }
    }
    StyledFlickable {
        id: preview
        objectName: "pointerTestList"
        width: 48; height: Math.max(36, parent.height - 46)
        anchors.right: parent.right; anchors.rightMargin: 10; anchors.top: parent.top; anchors.topMargin: 10
        clip: true
        contentHeight: 1024
        Repeater {
            model: 64
            Item {
                required property int index
                width: preview.width; height: 16
                y: index * height
                Rectangle {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    width: parent.index % 4 ? 6 : 12; height: 1; color: pad.accent
                }
                StyledText {
                    visible: parent.index % 4 === 0
                    anchors.right: parent.right; anchors.rightMargin: 15; anchors.verticalCenter: parent.verticalCenter
                    text: parent.index * 16
                    color: Appearance.colors.colSubtext; font.family: Appearance.font.family.numbers
                    font.pixelSize: Appearance.font.pixelSize.smallest
                }
            }
        }
    }
    StyledText {
        anchors.left: parent.left; anchors.leftMargin: 12; anchors.right: parent.right; anchors.rightMargin: 8
        anchors.bottom: parent.bottom; anchors.bottomMargin: 8
        elide: Text.ElideRight
        text: wheelFeedback.running ? Translation.tr("Scroll: %1 px").arg(Math.round(preview.contentY))
            : pad.lastClick || Translation.tr("Move, click or scroll here")
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colOnLayer2
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onEntered: { pad.trail = []; grid.requestPaint(); }
        onPositionChanged: event => pad.sample(event.x, event.y)
        onPressed: event => {
            pad.lastClick = event.button === Qt.RightButton ? Translation.tr("Right click")
                : event.button === Qt.MiddleButton ? Translation.tr("Middle click") : Translation.tr("Left click");
            ping.x = event.x - ping.width / 2;
            ping.y = event.y - ping.height / 2;
            pulse.restart();
        }
        onWheel: event => preview.wheelArea.wheel(event)
    }
    Connections { target: preview.wheelArea; function onUserScrolled() { wheelFeedback.restart(); } }
    Timer { id: wheelFeedback; interval: 230 }
    Rectangle {
        id: ping
        width: 42; height: 42; radius: 21; opacity: 0
        color: "transparent"; border.width: 2; border.color: Appearance.colors.colPrimary
        ParallelAnimation {
            id: pulse
            NumberAnimation { target: ping; property: "scale"; from: 0.25; to: 1.2; duration: Appearance.scaledDuration(380); easing.type: Easing.OutCubic }
            NumberAnimation { target: ping; property: "opacity"; from: 1; to: 0; duration: Appearance.scaledDuration(380) }
        }
    }
}
