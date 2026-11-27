import QtQuick
import QtQuick.Window
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

RippleButton {
    id: root

    property bool showPing: false
    property bool thinking: false
    Accessible.description: thinking ? Translation.tr("AI is thinking") : ""

    readonly property bool barVisible: SidebarLayout.shownParts("left").length > 0
    visible: barVisible

    property real buttonPadding: 5
    implicitWidth: distroIcon.width + buttonPadding * 2
    implicitHeight: distroIcon.height + buttonPadding * 2
    buttonRadius: Appearance.rounding.full
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active
    colBackgroundToggled: Appearance.colors.colSecondaryContainer
    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
    colRippleToggled: Appearance.colors.colSecondaryContainerActive
    toggled: GlobalStates.sidebarLeftOpen
    scale: down && Config.options.bar.microAnimations ? 0.9 : 1
    Behavior on scale {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    onPressed: {
        GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
    }

    Connections {
        target: Ai
        function onResponseFinished() {
            if (GlobalStates.sidebarLeftOpen) return;
            root.showPing = true;
        }
    }

    Connections {
        target: Booru
        function onResponseFinished() {
            if (GlobalStates.sidebarLeftOpen) return;
            root.showPing = true;
        }
    }

    Connections {
        target: GlobalStates
        function onSidebarLeftOpenChanged() {
            root.showPing = false;
        }
    }

    CustomIcon {
        id: distroIcon
        objectName: "sidebarButtonIcon"
        anchors.centerIn: parent
        width: 19.5
        height: 19.5
        source: Config.options.bar.topLeftIcon == 'distro' ? SystemInfo.distroIcon : `${Config.options.bar.topLeftIcon}-symbolic`
        colorize: true
        color: root.thinking ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer0
        Behavior on color { ColorAnimation { duration: Appearance.scaledDuration(150) } }
        property real pulseScale: 1
        scale: pulse.running ? pulseScale : 1
        SequentialAnimation on pulseScale {
            id: pulse
            running: root.thinking && root.visible && (root.Window.window?.visible ?? false) && Appearance.animationSpeed > 0
            loops: Animation.Infinite
            NumberAnimation { from: 0.8; to: 1.16; duration: Appearance.scaledDuration(550); easing.type: Easing.InOutSine }
            NumberAnimation { from: 1.16; to: 0.8; duration: Appearance.scaledDuration(550); easing.type: Easing.InOutSine }
        }

        Rectangle {
            opacity: root.showPing ? 1 : 0
            visible: opacity > 0
            anchors {
                bottom: parent.bottom
                right: parent.right
                bottomMargin: -2
                rightMargin: -2
            }
            implicitWidth: 8
            implicitHeight: 8
            radius: Appearance.rounding.full
            color: Appearance.colors.colTertiary

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }
}
