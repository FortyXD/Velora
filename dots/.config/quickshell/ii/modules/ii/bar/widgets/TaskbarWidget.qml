import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.bar
import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Quickshell

/**
 * Taskbar: pinned and running apps on the bar, as on Windows. A click opens an app, brings its
 * window forward or, on the window already in front, minimizes it (free windows); a middle
 * click opens another window; a right click has the app's menu. Shares its apps with the dock.
 */
Item {
    id: root
    property var host: null
    readonly property bool vertical: host?.vertical ?? false
    readonly property bool freeWindows: HyprlandSettings.windowMode === "floating"
    readonly property real buttonSize: 32

    implicitWidth: vertical ? buttonSize : row.implicitWidth
    implicitHeight: vertical ? row.implicitHeight : buttonSize

    function freeAction(name, address) {
        if (name === "minimize") FreeWindows.minimize(address);
        else FreeWindows.restore(address);
    }

    function addressOf(toplevel) {
        const address = toplevel?.HyprlandToplevel?.address ?? "";
        return address.startsWith("0x") ? address : (address.length > 0 ? `0x${address}` : "");
    }

    GridLayout {
        id: row
        anchors.centerIn: parent
        flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rowSpacing: 2
        columnSpacing: 2

        Repeater {
            model: ScriptModel {
                objectProp: "appId"
                values: TaskbarApps.apps
            }

            delegate: Item {
                id: app
                required property var modelData
                readonly property string appId: modelData.appId
                readonly property bool separator: appId === "SEPARATOR"
                readonly property var toplevels: modelData.toplevels ?? []
                readonly property int windowCount: toplevels.length
                readonly property bool active: toplevels.some(t => t.activated)
                readonly property bool minimized: windowCount > 0
                    && toplevels.every(t => (t.HyprlandToplevel?.workspace?.name ?? "").startsWith("special:"))
                property int lastFocused: -1

                implicitWidth: separator ? (root.vertical ? root.buttonSize : 9) : root.buttonSize
                implicitHeight: separator ? (root.vertical ? 9 : root.buttonSize) : root.buttonSize

                onActiveChanged: if (active) lastFocused = toplevels.findIndex(t => t.activated)

                Rectangle {
                    visible: app.separator
                    anchors.centerIn: parent
                    width: root.vertical ? parent.width * 0.5 : 1
                    height: root.vertical ? 1 : parent.height * 0.5
                    color: Appearance.colors.colOutlineVariant
                }

                RippleButton {
                    id: button
                    visible: !app.separator
                    anchors.fill: parent
                    buttonRadius: Appearance.rounding.small
                    toggled: app.active
                    colBackgroundToggled: Appearance.colors.colSecondaryContainer
                    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                    colRippleToggled: Appearance.colors.colSecondaryContainerActive
                    scale: down ? 0.88 : 1
                    Behavior on scale {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }

                    contentItem: Item {
                        Image {
                            anchors.centerIn: parent
                            width: 22
                            height: 22
                            source: app.separator ? "" : Quickshell.iconPath(TaskbarApps.iconFor(app.appId), "application-x-executable")
                            sourceSize.width: width * Screen.devicePixelRatio
                            sourceSize.height: height * Screen.devicePixelRatio
                            fillMode: Image.PreserveAspectFit
                            opacity: app.minimized ? 0.55 : 1
                        }
                    }

                    // Running: a short line; in front: a long one; minimized: a dot
                    Rectangle {
                        visible: app.windowCount > 0
                        anchors.horizontalCenter: root.vertical ? undefined : parent.horizontalCenter
                        anchors.verticalCenter: root.vertical ? parent.verticalCenter : undefined
                        anchors.bottom: root.vertical ? undefined : parent.bottom
                        anchors.left: root.vertical ? parent.left : undefined
                        anchors.bottomMargin: 1
                        anchors.leftMargin: 1
                        property real length: app.active ? 14 : app.minimized ? 3 : 7
                        width: root.vertical ? 3 : length
                        height: root.vertical ? length : 3
                        radius: 1.5
                        color: app.active ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.4)
                        Behavior on length {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                    }

                    onClicked: {
                        if (app.windowCount === 0) {
                            TaskbarApps.launch(app.appId, 0);
                            return;
                        }
                        const activeIndex = app.toplevels.findIndex(t => t.activated);
                        // The window in front, alone: out of the way, as on Windows
                        if (root.freeWindows && activeIndex >= 0 && app.windowCount === 1) {
                            root.freeAction("minimize", root.addressOf(app.toplevels[0]));
                            return;
                        }
                        const target = activeIndex >= 0 ? (activeIndex + 1) % app.windowCount
                            : (app.lastFocused >= 0 && app.lastFocused < app.windowCount ? app.lastFocused : app.windowCount - 1);
                        app.lastFocused = target;
                        const toplevel = app.toplevels[target];
                        if (root.freeWindows && (toplevel.HyprlandToplevel?.workspace?.name ?? "").startsWith("special:"))
                            root.freeAction("restore", root.addressOf(toplevel));
                        else
                            toplevel.activate();
                    }
                    altAction: () => app.openMenu()
                    middleClickAction: () => TaskbarApps.launch(app.appId, app.windowCount)

                    property bool hoverSettled: false
                    onHoveredChanged: if (!hovered) hoverSettled = false
                    Timer {
                        running: button.hovered
                        interval: 500
                        onTriggered: button.hoverSettled = true
                    }
                    BarToolTip {
                        shown: button.hoverSettled && !appMenu.visible
                        text: app.windowCount > 0 ? app.toplevels.map(t => t.title).join("\n") : TaskbarApps.displayName(app.appId)
                    }
                }

                function openMenu() {
                    let entries = [
                        { "text": Translation.tr("New window"), "icon": "add", "action": () => TaskbarApps.launch(app.appId, app.windowCount) },
                        { "text": TaskbarApps.isPinned(app.appId) ? Translation.tr("Unpin from the taskbar") : Translation.tr("Pin to the taskbar"),
                          "icon": "keep", "action": () => TaskbarApps.togglePin(app.appId) },
                    ];
                    if (app.windowCount > 0) {
                        entries.push({ "type": "separator" });
                        if (root.freeWindows) {
                            const toplevel = app.toplevels[Math.max(0, app.toplevels.findIndex(t => t.activated))];
                            const hidden = (toplevel.HyprlandToplevel?.workspace?.name ?? "").startsWith("special:");
                            entries.push({ "text": hidden ? Translation.tr("Restore") : Translation.tr("Minimize"),
                                "icon": hidden ? "open_in_new" : "minimize",
                                "action": () => root.freeAction(hidden ? "restore" : "minimize", root.addressOf(toplevel)) });
                        }
                        entries.push({ "text": app.windowCount > 1 ? Translation.tr("Close all windows") : Translation.tr("Close window"),
                            "icon": "close", "action": () => { for (const toplevel of app.toplevels) toplevel.close(); } });
                    }
                    const bottom = Config.options.bar.bottom;
                    const point = button.mapToItem(null, button.width / 2, root.vertical ? button.height / 2 : (bottom ? 0 : button.height));
                    appMenu.openEdge = root.vertical ? (bottom ? Edges.Left : Edges.Right) : (bottom ? Edges.Top : Edges.Bottom);
                    appMenu.openAt(button.QsWindow.window, point.x, point.y, entries);
                }
                ContextMenuPopup {
                    id: appMenu
                }
            }
        }
    }
}
