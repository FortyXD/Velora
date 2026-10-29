pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * The quick tour: a small card in a corner that asks for one thing at a time — press these keys,
 * do this gesture — and notices when you've done it. Nothing is dimmed and nothing is in the way:
 * keys and clicks go to the desktop, so everything is done for real. A panel a step opened closes
 * once it's checked off, ready for the next step. The keys shown are the ones bound now.
 *
 * Started by the setup assistant, Settings → About or `qs ipc call tour start`.
 */
Scope {
    id: root
    property bool active: false
    property bool finished: false
    property int index: 0
    property var steps: []
    property var checked: [] // Tasks of the current step already done
    property bool touchpad: false
    property real stepStarted: 0
    readonly property var step: root.steps[root.index] ?? null
    readonly property bool stepDone: !!root.step && root.checked.length >= root.step.tasks.length

    // A shortcut as it's bound now
    function keys(id, mods, key) {
        const bind = HyprlandKeybinds.binds.find(entry => entry.id === id && !entry.disabled);
        return bind ? { "mods": bind.mods ?? [], "key": bind.key } : { "mods": mods, "key": key };
    }
    function task(label, combo, detect, extra = {}) {
        return Object.assign({ "label": label, "combo": combo, "detect": detect }, extra);
    }

    function build() {
        const free = HyprlandSettings.windowMode === "floating";
        let list = [
            { "id": "search", "title": Translation.tr("Search and overview"),
              "text": Translation.tr("Type the name of an app to open it. Below are all your workspaces and windows. Super+Tab opens the same panel."),
              "tasks": [root.task(Translation.tr("Tap Super and let go"), { "mods": [], "key": "Super" }, "overview")],
              "close": "overview" },
            { "id": "library", "title": Translation.tr("All your apps"),
              "text": Translation.tr("Every app in a grid. On a touchpad: four fingers toward you."),
              "tasks": [root.task(Translation.tr("Open all apps"), root.keys("shell.app_library", ["Super", "Shift"], "Space"), "library")],
              "close": "library" },
            { "id": "terminal", "title": Translation.tr("Open an app with a key"),
              "text": Translation.tr("A terminal, a browser (Super+B) and files (Super+E) have their own keys."),
              "tasks": [root.task(Translation.tr("Open a terminal"), root.keys("app.terminal", ["Super"], "Return"), "window")] },
            free ? { "id": "windows", "title": Translation.tr("Put windows in place"),
              "text": Translation.tr("Windows stay where you put them; Super and the arrows send one to a half or a quarter of the screen."),
              "tasks": [root.task(Translation.tr("Snap the window to the left"), { "mods": ["Super"], "key": "Left" }, "snap:left"),
                        root.task(Translation.tr("Now to the top-left quarter"), { "mods": ["Super"], "key": "Up" }, "snap:top-left")] }
            : { "id": "windows", "title": Translation.tr("Windows side by side"),
              "text": Translation.tr("Tiled windows share the screen; Super and the arrows move between them."),
              "tasks": [root.task(Translation.tr("Open the file manager"), root.keys("app.files", ["Super"], "E"), "window"),
                        root.task(Translation.tr("Move to the other window"), { "mods": ["Super"], "key": "Left" }, "focus")] },
            { "id": "switch", "title": Translation.tr("Switch between windows"),
              "text": Translation.tr("Alt+Tab goes back to the window before; hold Alt and press Tab again to pick another."),
              "tasks": [root.task(Translation.tr("Switch windows"), root.keys("window.switch_next", ["Alt"], "Tab"), "focus")] },
            { "id": "workspaces", "title": Translation.tr("Workspaces"),
              "text": Translation.tr("Spread your work over several screens' worth of space. Super+Alt+number sends the window there."),
              "tasks": [root.task(Translation.tr("Go to workspace 2"), { "mods": ["Super"], "key": "2" }, "workspace:2"),
                        root.task(Translation.tr("And back to 1"), { "mods": ["Super"], "key": "1" }, "workspace:1")] },
            { "id": "quick", "title": Translation.tr("Quick settings"),
              "text": Translation.tr("Wi-Fi, sound, brightness and your notifications, on the right."),
              "tasks": [root.task(Translation.tr("Open quick settings"), root.keys("shell.sidebar_right", ["Super"], "N"), "sidebar")],
              "close": "sidebar", "corner": "left" },
            { "id": "screenshot", "title": Translation.tr("Screenshots"),
              "text": Translation.tr("Select a part of the screen with the mouse, or press Esc to leave."),
              "tasks": [root.task(Translation.tr("Take a screenshot of a region"), root.keys("tools.screenshot_region", ["Super", "Shift"], "S"), "region")],
              "waitFor": "region" },
        ];
        if (root.touchpad) list.push({ "id": "gestures", "title": Translation.tr("Touchpad gestures"),
            "text": Translation.tr("Four fingers: sideways switch workspaces, up shows the overview, toward you all apps."),
            "tasks": [root.task(Translation.tr("Swipe up with four fingers"), null, "gesture:overview", { "gesture": "swipe_up" }),
                      root.task(Translation.tr("Swipe toward you with four fingers"), null, "gesture:library", { "gesture": "swipe_down" })],
            "close": "overview,library" });
        list.push({ "id": "settings", "title": Translation.tr("Make it yours"),
            "text": Translation.tr("Settings has everything: the bar, presets, windows, gestures, shortcuts."),
            "tasks": [root.task(Translation.tr("Open Settings"), root.keys("shell.settings", ["Super"], "I"), "settings")] });
        list.push({ "id": "cheatsheet", "title": Translation.tr("Forgot a shortcut?"),
            "text": Translation.tr("Every shortcut, always up to date."),
            "tasks": [root.task(Translation.tr("Open the shortcuts"), root.keys("shell.cheatsheet", ["Super"], "Slash"), "cheatsheet")] });
        return list;
    }

    property var screen: null // Where it was started; it stays there
    function start() {
        root.screen = Quickshell.screens.find(screen => screen.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0];
        touchpadProc.running = true;
        root.steps = root.build();
        root.finished = false;
        root.go(0);
        root.active = true;
    }
    function stop() {
        root.active = false;
    }
    function go(index) {
        root.index = index;
        root.checked = [];
        root.stepStarted = Date.now();
    }
    function next() {
        advance.stop();
        if (root.index >= root.steps.length - 1) root.finished = true;
        else root.go(root.index + 1);
    }
    function back() {
        if (root.index > 0) root.go(root.index - 1);
    }

    // Something happened: is it what the current task asked for?
    function saw(kind) {
        if (!root.active || root.finished || !root.step || root.stepDone) return;
        // Ignore what was still settling from the previous step or task: opening a window also
        // moves the focus, which mustn't count as "switch to the other window"
        if (Date.now() - root.stepStarted < 500) return;
        const position = root.checked.length;
        if (root.step.tasks[position]?.detect !== kind) return;
        root.checked = [...root.checked, position];
        root.stepStarted = Date.now();
        if (root.stepDone) advance.restart();
    }
    // Done: close what it opened, then on to the next step (after a screenshot, once it's taken or left)
    Timer {
        id: advance
        interval: 1100
        onTriggered: {
            const close = root.step?.close ?? "";
            if (close.includes("overview")) GlobalStates.overviewOpen = false;
            if (close.includes("library")) GlobalStates.appLibraryOpen = false;
            if (close.includes("sidebar")) GlobalStates.sidebarRightOpen = false;
            if (root.step?.waitFor === "region" && GlobalStates.regionSelectorOpen) return; // Goes on when it closes
            root.next();
        }
    }

    Process {
        id: touchpadProc
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.touchpad = (JSON.parse(text).mice ?? []).some(mouse => /touchpad|trackpad/i.test(mouse.name));
                } catch (error) {}
                if (!root.active) return;
                const current = root.step?.id;
                root.steps = root.build();
                root.index = Math.max(0, root.steps.findIndex(step => step.id === current));
            }
        }
    }

    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() { if (GlobalStates.overviewOpen) root.saw("overview"); }
        function onAppLibraryOpenChanged() { if (GlobalStates.appLibraryOpen) root.saw("library"); }
        function onSidebarRightOpenChanged() { if (GlobalStates.sidebarRightOpen) root.saw("sidebar"); }
        function onRegionSelectorOpenChanged() {
            if (GlobalStates.regionSelectorOpen) root.saw("region");
            else if (root.stepDone && root.step?.waitFor === "region") root.next();
        }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            const data = event.data;
            switch (event.name) {
            case "openwindow":
                root.saw(data.split(",")[2] === "org.velora.Settings" ? "settings" : "window");
                break;
            case "activewindowv2":
                // Settings already open: Super+I brings it forward instead of opening it
                if (HyprlandData.windowByAddress[`0x${data}`]?.class === "org.velora.Settings") root.saw("settings");
                root.saw("focus");
                break;
            case "workspacev2":
                root.saw(`workspace:${data.split(",")[0]}`);
                break;
            case "openlayer":
                if (data === "quickshell:cheatsheet") root.saw("cheatsheet");
                break;
            case "custom":
                if (data.startsWith("velora:")) root.saw(data.slice(7));
                else if (data.startsWith("gesture:") && data.split(":")[2] === "end") root.saw(`gesture:${data.split(":")[1]}`);
                break;
            }
        }
    }

    IpcHandler {
        target: "tour"
        function start(): void {
            root.start();
        }
        function stop(): void {
            root.stop();
        }
        function next(): void {
            root.next();
        }
    }

    LazyLoader {
        active: root.active

        component: PanelWindow {
            id: window
            screen: root.screen
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:tour"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None // Keys go to the desktop: that's the point
            // The whole screen, so its size never changes (resizing it every frame made the card stutter);
            // only the card takes input, the rest goes through
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            mask: Region {
                item: card
            }

            // Clear of the bar and the dock, in the corner the step doesn't use
            readonly property bool barBelow: Config.options.bar.bottom && !Config.options.bar.vertical
            readonly property real bottomGap: (window.barBelow ? (Config.options.bar.style?.thickness > 0 ? Config.options.bar.style.thickness : 40) + 12 : 0) + 24
            readonly property bool onLeft: root.step?.corner === "left" || (Config.options.bar.vertical && Config.options.bar.bottom)

            StyledRectangularShadow {
                target: card
            }
            Rectangle {
                id: card
                width: 400
                height: content.implicitHeight + 36
                x: window.onLeft ? 24 + (Config.options.bar.vertical && !Config.options.bar.bottom ? 56 : 0) : window.width - width - 24
                y: window.height - height - window.bottomGap
                radius: Appearance.rounding.windowRounding
                color: Appearance.colors.colLayer0
                border.width: root.stepDone ? 2 : 1
                border.color: root.stepDone ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
                Behavior on x { NumberAnimation { duration: 460; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasized } }
                Behavior on border.color { ColorAnimation { duration: 200 } }

                // Slides up into its corner
                opacity: 0
                transform: Translate { id: rise; y: 40 }
                Component.onCompleted: arrive.start()
                ParallelAnimation {
                    id: arrive
                    NumberAnimation { target: card; property: "opacity"; to: 1; duration: 300 }
                    NumberAnimation { target: rise; property: "y"; to: 0; duration: 520; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel }
                }

                ColumnLayout {
                    id: content
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 18
                    spacing: 12

                    // Progress: one segment per step
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        Repeater {
                            model: root.steps.length
                            delegate: Rectangle {
                                required property int index
                                Layout.fillWidth: true
                                implicitHeight: 4
                                radius: 2
                                color: index < root.index || root.finished || (index === root.index && root.stepDone)
                                    ? Appearance.colors.colPrimary
                                    : index === root.index ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.6) : Appearance.colors.colLayer2
                                Behavior on color { ColorAnimation { duration: 300 } }
                            }
                        }
                        RippleButton {
                            Layout.leftMargin: 6
                            implicitWidth: 28
                            implicitHeight: 28
                            buttonRadius: height / 2
                            onClicked: root.stop()
                            contentItem: MaterialSymbol {
                                horizontalAlignment: Text.AlignHCenter
                                text: "close"
                                iconSize: 18
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }

                    // The step, or the end
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: (root.finished ? finishColumn : stepColumn).implicitHeight

                        ColumnLayout {
                            id: stepColumn
                            width: parent.width
                            spacing: 10
                            visible: !root.finished
                            // A new step slides in from the right
                            property int shown: root.index
                            onShownChanged: swap.restart()
                            Connections {
                                target: root
                                function onIndexChanged() { stepColumn.shown = root.index; }
                            }
                            ParallelAnimation {
                                id: swap
                                NumberAnimation { target: stepColumn; property: "opacity"; from: 0; to: 1; duration: 260 }
                                NumberAnimation { target: slide; property: "x"; from: 28; to: 0; duration: 420; easing.type: Easing.OutCubic }
                            }
                            transform: Translate { id: slide }

                            StyledText {
                                Layout.fillWidth: true
                                text: root.step?.title ?? ""
                                font.family: Appearance.font.family.title
                                font.pixelSize: 22
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer0
                                wrapMode: Text.Wrap
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: root.step?.text ?? ""
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.small
                                wrapMode: Text.Wrap
                            }

                            // What to do: one line per task, the current one alive, done ones checked
                            Repeater {
                                model: root.step?.tasks ?? []
                                delegate: Rectangle {
                                    id: taskRow
                                    required property var modelData
                                    required property int index
                                    readonly property bool done: root.checked.includes(index)
                                    readonly property bool current: !done && index === root.checked.length
                                    Layout.fillWidth: true
                                    implicitHeight: taskLayout.implicitHeight + 20
                                    radius: Appearance.rounding.normal
                                    color: done ? Appearance.colors.colSecondaryContainer : current ? Appearance.colors.colLayer1 : "transparent"
                                    border.width: current ? 1 : 0
                                    border.color: Appearance.colors.colOutlineVariant
                                    opacity: done || current ? 1 : 0.5
                                    Behavior on color { ColorAnimation { duration: 260 } }

                                    RowLayout {
                                        id: taskLayout
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        spacing: 10

                                        // Waiting: a ring that breathes. Done: a check that pops
                                        Item {
                                            implicitWidth: 22
                                            implicitHeight: 22
                                            Rectangle {
                                                anchors.fill: parent
                                                radius: width / 2
                                                color: "transparent"
                                                border.width: 2
                                                border.color: Appearance.colors.colPrimary
                                                visible: !taskRow.done
                                                SequentialAnimation on opacity {
                                                    running: taskRow.current
                                                    loops: Animation.Infinite
                                                    NumberAnimation { to: 0.3; duration: 650; easing.type: Easing.InOutSine }
                                                    NumberAnimation { to: 1; duration: 650; easing.type: Easing.InOutSine }
                                                }
                                            }
                                            Rectangle {
                                                anchors.fill: parent
                                                radius: width / 2
                                                color: Appearance.colors.colPrimary
                                                scale: taskRow.done ? 1 : 0
                                                Behavior on scale { NumberAnimation { duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.6 } }
                                                MaterialSymbol {
                                                    anchors.centerIn: parent
                                                    text: "check"
                                                    iconSize: 16
                                                    color: Appearance.colors.colOnPrimary
                                                }
                                            }
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: taskRow.modelData.label
                                            wrapMode: Text.Wrap
                                            color: taskRow.done ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                        }
                                        // The keys to press, nudging to be pressed
                                        KeyCombo {
                                            id: combo
                                            visible: !!taskRow.modelData.combo
                                            mods: taskRow.modelData.combo?.mods ?? []
                                            key: taskRow.modelData.combo?.key ?? ""
                                            pixelSize: 15
                                            transformOrigin: Item.Center
                                            SequentialAnimation on scale {
                                                running: taskRow.current
                                                loops: Animation.Infinite
                                                PauseAnimation { duration: 900 }
                                                NumberAnimation { to: 0.9; duration: 110; easing.type: Easing.OutQuad }
                                                NumberAnimation { to: 1; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 3 }
                                            }
                                        }
                                        // A gesture: an arrow that keeps moving that way
                                        MaterialSymbol {
                                            visible: !!taskRow.modelData.gesture
                                            text: taskRow.modelData.gesture ?? ""
                                            iconSize: 26
                                            color: Appearance.colors.colPrimary
                                            transform: Translate { id: nudge }
                                            SequentialAnimation {
                                                running: taskRow.current && !!taskRow.modelData.gesture
                                                loops: Animation.Infinite
                                                NumberAnimation { target: nudge; property: "y"; to: taskRow.modelData.gesture === "swipe_up" ? -6 : 6; duration: 500; easing.type: Easing.OutCubic }
                                                NumberAnimation { target: nudge; property: "y"; to: 0; duration: 500; easing.type: Easing.InCubic }
                                            }
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.stepDone ? Translation.tr("Nicely done!") : `${root.index + 1} / ${root.steps.length}`
                                    color: root.stepDone ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: root.stepDone ? Font.DemiBold : Font.Normal
                                }
                                RippleButton {
                                    visible: root.index > 0
                                    implicitHeight: 32
                                    implicitWidth: backText.implicitWidth + 24
                                    buttonRadius: height / 2
                                    onClicked: root.back()
                                    contentItem: StyledText {
                                        id: backText
                                        horizontalAlignment: Text.AlignHCenter
                                        text: Translation.tr("Back")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                    }
                                }
                                RippleButton {
                                    implicitHeight: 32
                                    implicitWidth: skipText.implicitWidth + 24
                                    buttonRadius: height / 2
                                    colBackground: root.stepDone ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                                    onClicked: root.next()
                                    contentItem: StyledText {
                                        id: skipText
                                        horizontalAlignment: Text.AlignHCenter
                                        text: root.stepDone ? Translation.tr("Next") : Translation.tr("Skip")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: root.stepDone ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            id: finishColumn
                            width: parent.width
                            spacing: 10
                            visible: root.finished
                            StyledText {
                                text: Translation.tr("That's the basics")
                                font.family: Appearance.font.family.title
                                font.pixelSize: 22
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer0
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Everything else is in Settings and in the shortcut list (Super+/). You can take this tour again from Settings → About.")
                                wrapMode: Text.Wrap
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Item { Layout.fillWidth: true }
                                RippleButton {
                                    implicitHeight: 36
                                    implicitWidth: againText.implicitWidth + 28
                                    buttonRadius: height / 2
                                    onClicked: root.start()
                                    contentItem: StyledText {
                                        id: againText
                                        horizontalAlignment: Text.AlignHCenter
                                        text: Translation.tr("Again")
                                    }
                                }
                                RippleButton {
                                    implicitHeight: 36
                                    implicitWidth: closeText.implicitWidth + 32
                                    buttonRadius: height / 2
                                    colBackground: Appearance.colors.colPrimary
                                    colBackgroundHover: Appearance.colors.colPrimaryHover
                                    onClicked: root.stop()
                                    contentItem: StyledText {
                                        id: closeText
                                        horizontalAlignment: Text.AlignHCenter
                                        text: Translation.tr("Done")
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.colOnPrimary
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
