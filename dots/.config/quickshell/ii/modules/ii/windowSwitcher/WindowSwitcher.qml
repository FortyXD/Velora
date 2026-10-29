pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * Alt+Tab: windows in the order they were last used, with live previews. Tab steps, letting go of
 * Alt switches (hyprland/keybinds.lua sees the release and calls windowSwitcherCommit), Alt+Esc
 * cancels. A quick Alt+Tab swaps to the previous window without showing anything, as on Windows.
 * It never takes the keyboard: focus moving to it and back raced with the switch itself.
 */
Scope {
    id: root
    property bool active: false
    property bool shown: false
    property int index: 0
    property var windows: []
    property string screenName: "" // Where it opened; it stays there however the pointer moves

    // Most recently used first, kept from Hyprland's focus events as they happen; the window list's
    // own order is refreshed later, so two quick Alt+Tabs would see the old one
    property var recent: []
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.data.length === 0) return;
            const address = event.data.startsWith("0x") ? event.data : `0x${event.data}`;
            if (event.name === "activewindowv2") root.remember(address);
            else if (event.name === "closewindow") root.removeWindow(address);
        }
    }

    function remember(address) {
        // Seed the whole history before promoting a window. Remembering only the new focus
        // loses the previous window when another client query is still in flight.
        const fallback = HyprlandData.windowList.slice().sort((a, b) => historyRank(a) - historyRank(b));
        const ordered = [...root.recent, ...fallback.map(window => window.address)];
        root.recent = [address, ...ordered.filter((item, index) => item !== address && ordered.indexOf(item) === index)].slice(0, 64);
    }

    function historyRank(window) {
        const rank = window.focusHistoryID;
        return rank >= 0 ? rank : Number.MAX_SAFE_INTEGER;
    }

    function rank(window) {
        const position = root.recent.indexOf(window.address);
        return position >= 0 ? position : 64 + root.historyRank(window);
    }

    function removeWindow(address) {
        root.recent = root.recent.filter(item => item !== address);
        if (!root.active) return;
        const selected = root.windows[root.index]?.address;
        root.windows = root.windows.filter(window => window.address !== address);
        if (root.windows.length === 0) {
            root.close();
            return;
        }
        const selectedIndex = root.windows.findIndex(window => window.address === selected);
        root.index = selectedIndex >= 0 ? selectedIndex : Math.min(root.index, root.windows.length - 1);
    }

    function collect() {
        const current = Hyprland.activeToplevel?.address;
        if (current) root.remember(current.startsWith("0x") ? current : `0x${current}`);
        // Minimized windows (free windows) come last, like on Windows
        root.windows = HyprlandData.windowList
            .filter(window => window.mapped !== false && window.class !== "" && !(window.workspace?.name ?? "").startsWith("special:desktop"))
            .sort((a, b) => {
                const hiddenA = (a.workspace?.name ?? "").startsWith("special:"), hiddenB = (b.workspace?.name ?? "").startsWith("special:");
                return (hiddenA - hiddenB) || (root.rank(a) - root.rank(b));
            });
    }

    function step(delta) {
        if (!root.active) {
            root.collect();
            if (root.windows.length === 0) return;
            root.screenName = Hyprland.focusedMonitor?.name ?? "";
            root.active = true;
            root.index = root.windows.length > 1 ? (delta > 0 ? 1 : root.windows.length - 1) : 0;
            showDelay.restart();
            return;
        }
        root.shown = true;
        root.index = (root.index + delta + root.windows.length) % root.windows.length;
    }

    function commit() {
        if (!root.active) return;
        const window = root.windows[root.index];
        // Switch first: the picture goes a moment later, once the window is in front
        if (window) {
            root.activate(window);
            root.remember(window.address);
        }
        root.active = false;
        showDelay.stop();
        hideDelay.restart();
    }
    Timer {
        id: hideDelay
        interval: 60
        onTriggered: if (!root.active) root.shown = false
    }

    function close() {
        showDelay.stop();
        root.active = false;
        root.shown = false;
    }

    function activate(window) {
        const target = `address:${window.address}`;
        if ((window.workspace?.name ?? "").startsWith("special:")) {
            const workspace = HyprlandData.activeWorkspace?.id ?? 1;
            Hyprland.dispatch(`hl.dsp.window.move({ workspace = "${workspace}", follow = false, window = "${target}" })`);
        }
        Hyprland.dispatch(`hl.dsp.focus({ window = "${target}" })`);
        if (window.floating) Hyprland.dispatch(`hl.dsp.window.alter_zorder({ mode = "top", window = "${target}" })`);
    }

    function toplevelFor(address) {
        return ToplevelManager.toplevels.values.find(toplevel => `0x${toplevel.HyprlandToplevel?.address}` === address) ?? null;
    }

    Timer {
        id: showDelay
        interval: 140 // Shorter than this, Alt+Tab was a quick swap
        onTriggered: root.shown = root.active
    }
    // Never keeps the keyboard if the release of Alt went missing
    Timer {
        id: safety
        running: root.active
        interval: 8000
        onTriggered: root.close()
    }
    onIndexChanged: if (root.active) safety.restart()

    GlobalShortcut {
        name: "windowSwitcherNext"
        description: "Window switcher: next window"
        onPressed: root.step(1)
    }
    GlobalShortcut {
        name: "windowSwitcherPrevious"
        description: "Window switcher: previous window"
        onPressed: root.step(-1)
    }
    GlobalShortcut {
        name: "windowSwitcherCancel"
        description: "Window switcher: close without switching"
        onPressed: root.close()
    }
    GlobalShortcut {
        name: "windowSwitcherCommit"
        description: "Window switcher: switch to the selected window"
        onPressed: root.commit()
    }

    LazyLoader {
        active: root.shown

        component: PanelWindow {
            id: window
            screen: Quickshell.screens.find(screen => screen.name === root.screenName) ?? Quickshell.screens[0]
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:windowSwitcher"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            mask: Region {
                item: card
            }

            readonly property real tileWidth: 228
            readonly property real previewHeight: 136
            readonly property int columns: Math.max(1, Math.min(root.windows.length, Math.floor((window.width * 0.86 - 32) / (tileWidth + 10))))

            StyledRectangularShadow {
                target: card
            }
            Rectangle {
                id: card
                anchors.centerIn: parent
                width: grid.implicitWidth + 32
                height: grid.implicitHeight + 32
                radius: Appearance.rounding.windowRounding
                color: Appearance.colors.colLayer0
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                focus: true

                // Pops in instead of appearing
                scale: 0.94
                opacity: 0
                Component.onCompleted: {
                    scale = 1;
                    opacity = 1;
                }
                Behavior on scale {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) root.close();
                    else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) root.step(1);
                    else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab) root.step(-1);
                    else if (event.key === Qt.Key_Down) root.step(window.columns);
                    else if (event.key === Qt.Key_Up) root.step(-window.columns);
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.commit();
                    else return;
                    event.accepted = true;
                }

                GridLayout {
                    id: grid
                    x: 16
                    y: 16
                    columns: window.columns
                    rowSpacing: 10
                    columnSpacing: 10

                    Repeater {
                        id: tiles
                        model: root.windows

                        delegate: WindowSwitcherTile {
                            id: tile
                            required property var modelData
                            required property int index
                            readonly property bool minimized: (modelData.workspace?.name ?? "").startsWith("special:")
                            implicitWidth: window.tileWidth
                            implicitHeight: column.implicitHeight
                            selected: root.index === tile.index
                            // A stationary cursor under the appearing card must not replace
                            // the keyboard's selection. Clicking still selects any preview.
                            onClicked: {
                                root.index = tile.index;
                                root.commit();
                            }

                            ColumnLayout {
                                id: column
                                width: parent.width
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 4
                                    Layout.rightMargin: 4
                                    spacing: 6
                                    Image {
                                        Layout.preferredWidth: 18
                                        Layout.preferredHeight: 18
                                        source: Quickshell.iconPath(TaskbarApps.iconFor(tile.modelData.class), "application-x-executable")
                                        sourceSize.width: 18 * Screen.devicePixelRatio
                                        sourceSize.height: 18 * Screen.devicePixelRatio
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: tile.modelData.title || tile.modelData.class
                                        elide: Text.ElideRight
                                        color: Appearance.colors.colOnLayer0
                                        font.pixelSize: Appearance.font.pixelSize.small
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: window.previewHeight
                                    radius: Appearance.rounding.small
                                    color: Appearance.colors.colLayer1
                                    clip: true
                                    ScreencopyView {
                                        id: preview
                                        anchors.centerIn: parent
                                        captureSource: tile.minimized ? null : root.toplevelFor(tile.modelData.address)
                                        live: !PowerSaving.cutLivePreviews
                                        constraintSize: Qt.size(parent.width, parent.height)
                                    }
                                    // No picture of a minimized window: its icon instead
                                    Image {
                                        visible: !preview.hasContent
                                        anchors.centerIn: parent
                                        width: 48
                                        height: 48
                                        opacity: tile.minimized ? 0.6 : 1
                                        source: Quickshell.iconPath(TaskbarApps.iconFor(tile.modelData.class), "application-x-executable")
                                        sourceSize.width: 48 * Screen.devicePixelRatio
                                        sourceSize.height: 48 * Screen.devicePixelRatio
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
