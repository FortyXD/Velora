import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * The session screen, over the whole focused screen. The desktop behind it blurs, dims and pushes in a little,
 * and the clock and the actions rise into it one after another; the highlighted action turns into an
 * expressive shape. Closing plays it all backwards.
 * Arrow keys or Tab move between the actions, Enter runs one, Esc or a click on empty space closes it.
 */
Scope {
    id: root

    // The first `mainCount` get a big button with a shape of their own, the rest a small one below
    readonly property var actions: [
        { "icon": "lock", "text": Translation.tr("Lock"), "shape": MaterialShape.Shape.Cookie9Sided, "run": () => Session.lock() },
        { "icon": "dark_mode", "text": Translation.tr("Sleep"), "shape": MaterialShape.Shape.Clover4Leaf, "run": () => Session.suspend() },
        { "icon": "logout", "text": Translation.tr("Logout"), "shape": MaterialShape.Shape.Pentagon, "run": () => Session.logout() },
        { "icon": "restart_alt", "text": Translation.tr("Reboot"), "shape": MaterialShape.Shape.Cookie12Sided, "run": () => Session.reboot() },
        { "icon": "power_settings_new", "text": Translation.tr("Shutdown"), "shape": MaterialShape.Shape.SoftBurst, "run": () => Session.poweroff() },
        { "icon": "downloading", "text": Translation.tr("Hibernate"), "run": () => Session.hibernate() },
        { "icon": "browse_activity", "text": Translation.tr("Task Manager"), "run": () => Session.launchTaskManager() },
        { "icon": "settings_applications", "text": Translation.tr("Reboot to firmware settings"), "run": () => Session.rebootToFirmware() },
    ]
    readonly property int mainCount: 5

    // Taken when it opens, so it stays there while the pointer moves to other screens
    property var screen: null
    // Follows GlobalStates.sessionOpen once the screen is chosen, so the window never opens on another one
    property bool shown: false
    // Stays loaded for the length of the exit animation
    property bool lingering: false

    Connections {
        target: GlobalStates
        function onSessionOpenChanged() {
            // Each sets the flag that keeps it loaded before clearing the other, or the window would go in between
            if (GlobalStates.sessionOpen) {
                lingerTimer.stop();
                if (!root.lingering)
                    root.screen = Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0];
                root.shown = true;
                root.lingering = false;
                SessionWarnings.refresh();
            } else {
                root.lingering = true;
                root.shown = false;
                lingerTimer.restart();
            }
        }
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked)
                GlobalStates.sessionOpen = false;
        }
    }
    Timer {
        id: lingerTimer
        interval: Appearance.scaledDuration(320)
        onTriggered: root.lingering = false
    }

    // Fades and rises into place `order` steps after the screen opens; drops back all at once when it closes
    component Rise: Item {
        id: rise
        required property int order
        property bool open: false
        property bool appeared: false
        default property Item child

        implicitWidth: rise.child?.implicitWidth ?? 0
        implicitHeight: rise.child?.implicitHeight ?? 0
        children: [rise.child]

        onOpenChanged: {
            if (rise.open) {
                riseTimer.restart();
            } else {
                riseTimer.stop();
                rise.appeared = false;
            }
        }
        Component.onCompleted: if (rise.open) riseTimer.restart()
        Timer {
            id: riseTimer
            interval: Appearance.scaledDuration(70 + rise.order * 45)
            onTriggered: rise.appeared = true
        }

        opacity: rise.appeared ? 1 : 0
        scale: rise.appeared ? 1 : 0.9
        transform: Translate {
            y: rise.appeared ? 0 : 40
            Behavior on y {
                NumberAnimation {
                    duration: Appearance.scaledDuration(rise.appeared ? Appearance.animationCurves.expressiveDefaultSpatialDuration : 180)
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: rise.appeared ? Appearance.animationCurves.expressiveDefaultSpatial : Appearance.animationCurves.emphasizedAccel
                }
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.scaledDuration(rise.appeared ? 280 : 160)
                easing.type: Easing.OutCubic
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: Appearance.scaledDuration(rise.appeared ? Appearance.animationCurves.expressiveDefaultSpatialDuration : 180)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: rise.appeared ? Appearance.animationCurves.expressiveDefaultSpatial : Appearance.animationCurves.emphasizedAccel
            }
        }
    }

    Loader {
        active: root.shown || root.lingering

        sourceComponent: PanelWindow {
            id: sessionWindow
            screen: root.screen
            property int current: 0
            // Up once the capture of the desktop is in, so the blur grows out of exactly what was on screen
            property bool ready: false
            readonly property bool open: root.shown && sessionWindow.ready

            function run(index) {
                root.actions[index].run();
                GlobalStates.sessionOpen = false;
            }
            // Up and down go to the action at about the same place in the other row
            function moveVertically(down) {
                const index = sessionWindow.current;
                const secondaryCount = root.actions.length - root.mainCount;
                if (down && index < root.mainCount) {
                    const column = Math.round((index + 0.5) / root.mainCount * secondaryCount - 0.5);
                    sessionWindow.current = root.mainCount + Math.max(0, Math.min(secondaryCount - 1, column));
                } else if (!down && index >= root.mainCount) {
                    const column = Math.round((index - root.mainCount + 0.5) / secondaryCount * root.mainCount - 0.5);
                    sessionWindow.current = Math.max(0, Math.min(root.mainCount - 1, column));
                }
            }

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:session"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            color: "transparent"
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            // While it plays its way out, clicks already go to what's under it
            mask: Region {
                item: root.shown ? clickCatcher : null
            }

            Timer { // In case the capture never comes
                running: true
                interval: 300
                onTriggered: sessionWindow.ready = true
            }

            // The desktop, blurred, dimmed and pushed in
            ScreencopyView {
                id: desktopCapture
                anchors.fill: parent
                visible: false // Drawn through the blur
                captureSource: root.screen
                live: false
                onHasContentChanged: if (hasContent) sessionWindow.ready = true
            }
            MultiEffect {
                anchors.fill: parent
                visible: desktopCapture.hasContent
                source: desktopCapture
                autoPaddingEnabled: false
                blurEnabled: true
                blurMax: 64
                blur: sessionWindow.open ? 1 : 0
                saturation: sessionWindow.open ? 0.15 : 0
                scale: sessionWindow.open ? 1.07 : 1
                Behavior on blur {
                    NumberAnimation {
                        duration: Appearance.scaledDuration(sessionWindow.open ? 520 : 300)
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: sessionWindow.open ? Appearance.animationCurves.emphasizedDecel : Appearance.animationCurves.emphasizedAccel
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: Appearance.scaledDuration(sessionWindow.open ? 700 : 300)
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: sessionWindow.open ? Appearance.animationCurves.emphasizedDecel : Appearance.animationCurves.emphasizedAccel
                    }
                }
                Behavior on saturation {
                    NumberAnimation {
                        duration: Appearance.scaledDuration(400)
                    }
                }
            }
            Rectangle { // Dim, deeper without a capture to dim
                anchors.fill: parent
                color: Appearance.colors.colLayer0
                opacity: sessionWindow.open ? (desktopCapture.hasContent ? 0.5 : 0.85) : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.scaledDuration(sessionWindow.open ? 420 : 280)
                        easing.type: Easing.OutCubic
                    }
                }
            }

            MouseArea { // Empty space closes it
                id: clickCatcher
                anchors.fill: parent
                onClicked: GlobalStates.sessionOpen = false
            }

            ColumnLayout {
                id: content
                anchors.centerIn: parent
                spacing: 0
                focus: true

                Keys.onPressed: event => {
                    const count = root.actions.length;
                    const current = sessionWindow.current;
                    if (event.key === Qt.Key_Escape) {
                        GlobalStates.sessionOpen = false;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        sessionWindow.run(current);
                    } else if (event.key === Qt.Key_Tab) {
                        sessionWindow.current = (current + 1) % count;
                    } else if (event.key === Qt.Key_Backtab) {
                        sessionWindow.current = (current + count - 1) % count;
                    } else if (event.key === Qt.Key_Left) {
                        if (current !== 0 && current !== root.mainCount) sessionWindow.current = current - 1;
                    } else if (event.key === Qt.Key_Right) {
                        if (current !== root.mainCount - 1 && current !== count - 1) sessionWindow.current = current + 1;
                    } else if (event.key === Qt.Key_Down) {
                        sessionWindow.moveVertically(true);
                    } else if (event.key === Qt.Key_Up) {
                        sessionWindow.moveVertically(false);
                    } else {
                        return;
                    }
                    event.accepted = true;
                }

                Rise {
                    Layout.alignment: Qt.AlignHCenter
                    order: 0
                    open: sessionWindow.open
                    StyledText {
                        text: DateTime.time
                        color: Appearance.colors.colOnLayer0
                        font {
                            family: Appearance.font.family.expressive
                            pixelSize: 88
                            weight: Font.DemiBold
                        }
                    }
                }
                Rise {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 2
                    order: 1
                    open: sessionWindow.open
                    StyledText {
                        text: `${DateTime.longDate}  ·  ${Translation.tr("Up %1").arg(DateTime.uptime)}`
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.large
                    }
                }

                Row {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 64
                    spacing: 28

                    Repeater {
                        model: root.mainCount
                        delegate: Rise {
                            id: mainRise
                            required property int index
                            order: 2 + index
                            open: sessionWindow.open
                            SessionActionButton {
                                buttonIcon: root.actions[mainRise.index].icon
                                buttonText: root.actions[mainRise.index].text
                                selectedShape: root.actions[mainRise.index].shape
                                selected: sessionWindow.current === mainRise.index
                                onHoveredChanged: {
                                    if (hovered) sessionWindow.current = mainRise.index;
                                }
                                onClicked: sessionWindow.run(mainRise.index)
                            }
                        }
                    }
                }

                Row {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 36
                    spacing: 10

                    Repeater {
                        model: root.actions.length - root.mainCount
                        delegate: Rise {
                            id: secondaryRise
                            required property int index
                            readonly property int actionIndex: root.mainCount + index
                            order: 2 + root.mainCount + index
                            open: sessionWindow.open
                            RippleButton {
                                id: pill
                                readonly property bool selected: sessionWindow.current === secondaryRise.actionIndex
                                readonly property color colContent: selected ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
                                implicitHeight: 40
                                implicitWidth: pillRow.implicitWidth + 36
                                buttonRadius: height / 2
                                colBackground: selected ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colLayer1, 0.25)
                                colBackgroundHover: Appearance.colors.colPrimary
                                colRipple: Appearance.colors.colPrimaryActive
                                onHoveredChanged: {
                                    if (hovered) sessionWindow.current = secondaryRise.actionIndex;
                                }
                                onClicked: sessionWindow.run(secondaryRise.actionIndex)

                                contentItem: Item {
                                    Row {
                                        id: pillRow
                                        anchors.centerIn: parent
                                        spacing: 8
                                        MaterialSymbol {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: root.actions[secondaryRise.actionIndex].icon
                                            iconSize: 20
                                            fill: pill.selected ? 1 : 0
                                            color: pill.colContent
                                        }
                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: root.actions[secondaryRise.actionIndex].text
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: pill.colContent
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Rise { // Things that would be lost on a power off
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 28
                    order: 2 + root.actions.length
                    open: sessionWindow.open
                    visible: SessionWarnings.downloadRunning || SessionWarnings.packageManagerRunning
                    Column {
                        spacing: 8
                        Repeater {
                            model: [
                                ...(SessionWarnings.downloadRunning ? [Translation.tr("There might be a download in progress. Check your Downloads folder.")] : []),
                                ...(SessionWarnings.packageManagerRunning ? [Translation.tr("Your package manager is running")] : []),
                            ]
                            delegate: Rectangle {
                                required property string modelData
                                anchors.horizontalCenter: parent?.horizontalCenter
                                implicitWidth: warningRow.implicitWidth + 28
                                implicitHeight: warningRow.implicitHeight + 16
                                radius: height / 2
                                color: Appearance.m3colors.m3errorContainer
                                Row {
                                    id: warningRow
                                    anchors.centerIn: parent
                                    spacing: 8
                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "warning"
                                        iconSize: 20
                                        fill: 1
                                        color: Appearance.m3colors.m3onErrorContainer
                                    }
                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.m3colors.m3onErrorContainer
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Rise { // How to use it, at the bottom of the screen
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    bottom: parent.bottom
                    bottomMargin: 40
                }
                order: 3 + root.actions.length
                open: sessionWindow.open
                StyledText {
                    horizontalAlignment: Text.AlignHCenter
                    text: Translation.tr("Arrow keys to navigate, Enter to select\nEsc or click anywhere to cancel")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }
        }
    }

    IpcHandler {
        target: "session"

        function toggle(): void {
            GlobalStates.sessionOpen = !GlobalStates.sessionOpen;
        }

        function close(): void {
            GlobalStates.sessionOpen = false;
        }

        function open(): void {
            GlobalStates.sessionOpen = true;
        }
    }

    GlobalShortcut {
        name: "sessionToggle"
        description: "Toggles session screen on press"

        onPressed: {
            GlobalStates.sessionOpen = !GlobalStates.sessionOpen;
        }
    }

    GlobalShortcut {
        name: "sessionOpen"
        description: "Opens session screen on press"

        onPressed: {
            GlobalStates.sessionOpen = true;
        }
    }

    GlobalShortcut {
        name: "sessionClose"
        description: "Closes session screen on press"

        onPressed: {
            GlobalStates.sessionOpen = false;
        }
    }
}
