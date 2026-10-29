//@ pragma UseQApplication
// The setup assistant, in its own process so that whatever happens to it, the desktop keeps running
//@ pragma AppId org.velora.Setup
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

// Started by services/FirstRunExperience.qml on the first login, by Shift+Super+Alt+/ and from
// Settings → About. Super+Shift+Escape (a Hyprland bind) always closes it.
// QS_ONBOARDING_DRYRUN=1 qs -p onboarding.qml: shows everything, changes nothing.

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.onboarding

ShellRoot {
    id: root

    // A screen's name, big, while the Screens step asks to show them
    component ScreenName: StyledText {
        required property string name
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 48
        text: name
        font.family: Appearance.font.family.title
        font.pixelSize: 96
        font.weight: Font.Bold
        color: Appearance.colors.colPrimary
        opacity: flow.identifying ? 1 : 0
        scale: flow.identifying ? 1 : 0.9
        Behavior on opacity { NumberAnimation { duration: Motion.ms(240) } }
        Behavior on scale { NumberAnimation { duration: Motion.ms(360); easing.type: Easing.OutBack } }
    }
    // Where it starts, for good: following the focus made it jump between monitors with the pointer
    property var mainScreen: null
    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme(true);
        root.mainScreen = Quickshell.screens.find(screen => screen.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0];
    }

    OnboardingFlow {
        id: flow
    }

    // The other screens: dimmed and blurred the same way, so the whole desktop waits for the setup
    Variants {
        model: root.mainScreen ? Quickshell.screens.filter(screen => screen !== root.mainScreen) : []
        PanelWindow {
            required property ShellScreen modelData
            visible: Config.ready && flow.ready
            screen: modelData
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:onboarding"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            Rectangle {
                anchors.fill: parent
                color: Appearance.colors.colLayer0
                opacity: flow.closing ? 0 : 0.7
                Behavior on opacity {
                    NumberAnimation { duration: Motion.ms(460) }
                }
                Component.onCompleted: fade.start()
                NumberAnimation on opacity { id: fade; running: false; from: 0; to: 0.7; duration: Motion.ms(600) }
            }
            VeloraLogo {
                anchors.centerIn: parent
                size: 56
                opacity: flow.closing || flow.identifying ? 0 : 0.5
                Behavior on opacity {
                    NumberAnimation { duration: Motion.ms(300) }
                }
            }
            ScreenName {
                name: modelData.name
            }
        }
    }

    PanelWindow {
        id: window
        visible: root.mainScreen !== null && Config.ready && flow.ready
        screen: root.mainScreen
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:onboarding"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        ScreenName {
            z: 10
            name: root.mainScreen?.name ?? ""
        }
        OnboardingView {
            anchors.fill: parent
            flow: flow
            onClosed: tour => {
                if (tour) Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "tour", "start"]);
                Qt.quit();
            }
        }
    }
}
