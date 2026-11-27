pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Rectangle {
    id: root
    required property bool pageActive
    required property string version
    signal updatesRequested()
    readonly property bool motionEnabled: Appearance.animationSpeed > 0
    readonly property bool animating: entrance.running
    property real progress: 1
    readonly property color accent: ColorUtils.mix(Appearance.colors.colPrimary, "#ffe6cf", 0.56)
    readonly property color ink: ColorUtils.mix("#151418", Appearance.colors.colPrimary, 0.93)

    Layout.fillWidth: true
    implicitHeight: Math.max(width < 480 ? 159 : 184, identity.implicitHeight + 36)
    radius: Appearance.rounding.normal
    color: ink

    function play() {
        entrance.stop();
        if (pageActive && motionEnabled) entrance.restart();
        else progress = 1;
    }
    Component.onCompleted: play()
    onPageActiveChanged: play()
    onMotionEnabledChanged: play()
    NumberAnimation {
        id: entrance
        target: root; property: "progress"; from: 0; to: 1
        duration: Appearance.scaledDuration(1650)
        easing.type: Easing.InOutSine
    }

    Item {
        id: art
        anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
        width: parent.width * 0.54
        Canvas {
            id: contours
            anchors.fill: parent
            readonly property real phase: root.progress
            readonly property color tint: root.accent
            onPhaseChanged: requestPaint()
            onTintChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d"), w = width, h = height, r = root.radius;
                if (!ctx || w <= 0 || h <= 0) return;
                ctx.clearRect(0, 0, w, h);
                ctx.save();
                ctx.beginPath();
                ctx.roundedRect(-r, 0, w + r, h, r, r);
                ctx.clip();

                const cx = w * 0.60, cy = h * 0.46;
                const glow = ctx.createRadialGradient(cx, cy, 0, cx, cy, Math.min(w * 0.64, h * 1.22));
                glow.addColorStop(0, Qt.rgba(tint.r, tint.g, tint.b, 0.23));
                glow.addColorStop(1, Qt.rgba(tint.r, tint.g, tint.b, 0));
                ctx.fillStyle = glow;
                ctx.fillRect(0, 0, w, h);

                const thread = ctx.createLinearGradient(0, 0, w, 0);
                thread.addColorStop(0, Qt.rgba(tint.r, tint.g, tint.b, 0));
                thread.addColorStop(0.38, Qt.rgba(tint.r, tint.g, tint.b, 0.20));
                thread.addColorStop(1, Qt.rgba(tint.r, tint.g, tint.b, 0.53));
                ctx.strokeStyle = thread;
                ctx.lineWidth = 1;
                // Each curve folds a little farther around the V. They settle as the stroke is drawn.
                for (let n = 0; n < 21; n++) {
                    const t = n / 20;
                    const slide = (1 - phase) * h * (0.45 + t * 0.35);
                    ctx.beginPath();
                    ctx.moveTo(-2, h * (-0.30 + t * 0.94) + slide);
                    ctx.bezierCurveTo(w * 0.29, h * (-0.34 + t * 1.15) + slide,
                                      w * (0.26 + t * 0.13), h * (0.96 + t * 0.60) + slide,
                                      w * (0.56 + t * 0.14), h * (0.84 + t * 0.49) + slide);
                    ctx.bezierCurveTo(w * 0.80, h * (0.72 + t * 0.61) + slide,
                                      w * (0.81 + t * 0.18), h * (-0.06 + t * 0.50) + slide,
                                      w + 3, h * (-0.24 + t * 0.63) + slide);
                    ctx.stroke();
                }
                ctx.restore();
            }
        }
        VeloraLogo {
            size: Math.min(art.width * 0.44, art.height * 0.60)
            x: art.width * 0.60 - width / 2
            y: art.height * 0.46 - height / 2
            progress: Math.min(1, root.progress * 1.2)
            opacity: Math.min(1, progress * 8)
            color: Qt.lighter(root.accent, 1.16)
        }
    }
    ColumnLayout {
        id: identity
        anchors { left: parent.left; leftMargin: root.width < 480 ? 19 : 26; verticalCenter: parent.verticalCenter }
        width: root.width * 0.50
        spacing: 2
        RowLayout {
            spacing: 6
            MaterialSymbol { text: "desktop_windows"; iconSize: 15; color: root.accent }
            StyledText { text: SystemInfo.distroName; color: root.accent; font.pixelSize: Appearance.font.pixelSize.smallie }
        }
        StyledText {
            text: "Velora"
            font.family: Appearance.font.family.title
            font.pixelSize: root.width < 480 ? 40 : 55
            font.letterSpacing: -2
            font.weight: Font.DemiBold
            color: "#fff9f4"
        }
        StyledText {
            Layout.fillWidth: true
            text: "Hyprland  /  Quickshell"
            color: "#e0d8d5"
            font.pixelSize: Appearance.font.pixelSize.small
            wrapMode: Text.Wrap
        }
        SettingsAction {
            id: updates
            objectName: "aboutUpdates"
            Layout.topMargin: 5
            implicitHeight: 30
            implicitWidth: contentItem.implicitWidth + 14
            horizontalPadding: 7
            text: root.version ? Translation.tr("Version %1").arg(root.version) : Translation.tr("Updates")
            Accessible.description: Translation.tr("Updates")
            colBackground: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.11)
            colBackgroundHover: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.23)
            onClicked: root.updatesRequested()
            contentItem: RowLayout {
                spacing: 5
                MaterialSymbol { text: "deployed_code"; iconSize: 15; color: root.accent }
                StyledText { text: updates.text; font.pixelSize: Appearance.font.pixelSize.smaller; color: root.accent }
                MaterialSymbol { text: "chevron_right"; iconSize: 14; color: root.accent }
            }
        }
    }
    SettingsAction {
        id: replay
        objectName: "replayAboutAnimation"
        visible: root.motionEnabled
        anchors { right: parent.right; bottom: parent.bottom; margins: 10 }
        implicitWidth: 30
        implicitHeight: 30
        buttonRadius: width / 2
        text: Translation.tr("Replay animation")
        colBackground: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.72)
        colBackgroundHover: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.24)
        onClicked: root.play()
        contentItem: MaterialSymbol { text: "replay"; iconSize: 18; horizontalAlignment: Text.AlignHCenter; color: root.accent }
        StyledToolTip { text: replay.text; alternativeVisibleCondition: replay.visualFocus }
    }
}
