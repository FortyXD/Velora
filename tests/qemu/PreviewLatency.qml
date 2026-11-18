import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common
import qs.modules.ii.bar
import qs.modules.ii.dock
import qs.modules.ii.windowSwitcher
import qs.modules.waffle.bar.tasks

ShellRoot {
    id: root
    readonly property var clients: HyprlandData.windowList.filter(c => c.class === "velora-latency")
    readonly property var handles: ToplevelManager.toplevels.values.filter(t => t.appId === "velora-latency")
    readonly property var surfaces: ["switcher", "dock", "workspace", "waffle"]
    property int phase: 0
    property bool measuring: false
    property double nextOpen: 0
    property string selected: ""
    readonly property string surface: surfaces[Math.floor(phase / 2)] ?? ""

    PanelWindow {
        id: bar
        anchors { top: true; left: true; right: true }
        implicitHeight: 30
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        Item {
            id: tile
            width: 48; height: 30
            property bool containsMouse: false
            property int windowCount: root.handles.length
            property var toplevels: root.handles
            property real baseCenter: 24
        }
        WorkspacePreviewPopup {
            id: workspace
            hoverTarget: tile
            panelHovered: true
            workspaceId: root.clients[0]?.workspace.id ?? 0
        }
    }
    DockContext { id: context }
    DockPreviews { id: dock; dock: context; dockWindow: bar; rowX: 0; bottomY: 0 }
    WindowSwitcher { id: switcher }
    TaskPreview { id: waffle; anchor.window: bar; tasksHovered: true }
    Timer { id: waffleDwell; interval: 400; onTriggered: waffle.show(tile, tile) }

    function openSurface() {
        root.selected = "";
        PreviewTiming.frames = ({});
        PreviewTiming.start = Date.now();
        root.measuring = true;
        switch (root.surface) {
        case "switcher":
            switcher.step(1);
            root.selected = String(switcher.windows[switcher.index]?.stableId ?? "");
            break;
        case "dock": context.hoveredTile = tile; break;
        case "workspace": tile.containsMouse = true; break;
        case "waffle":
            if (typeof waffle.prepare === "function") waffle.prepare(tile, tile);
            waffleDwell.start();
            break;
        }
    }
    function closeSurface() {
        switcher.close();
        context.hoveredTile = null;
        dock.dismiss();
        tile.containsMouse = false;
        waffle.close();
    }
    Timer {
        interval: 12; repeat: true; running: true
        onTriggered: {
            if (!Config.ready || root.clients.length !== Number(Quickshell.env("LATENCY_WINDOWS")) || root.handles.length !== root.clients.length) return;
            if (!root.measuring) {
                if (Date.now() < root.nextOpen) return;
                GlobalStates.screenLocked = false;
                root.openSurface();
                return;
            }
            const times = root.clients.map(c => PreviewTiming.frames[c.stableId]);
            if (!times.every(t => t !== undefined)) {
                if (Date.now() - PreviewTiming.start > 6000) {
                    console.error("LATENCY_TIMEOUT", root.surface, JSON.stringify(PreviewTiming.frames));
                    Qt.exit(2);
                }
                return;
            }
            console.log("LATENCY_RESULT", JSON.stringify({surface:root.surface, warm:root.phase % 2 === 1,
                first:Math.min(...times), selected:PreviewTiming.frames[root.selected], all:Math.max(...times)}));
            root.closeSurface();
            root.measuring = false;
            root.phase++;
            if (root.phase === root.surfaces.length * 2) { Qt.quit(); return; }
            // A cold case also starts a new Python worker. A warm one reopens
            // after all delegates and the prior popup's exit animation are gone.
            if (root.phase % 2 === 0) GlobalStates.screenLocked = true;
            root.nextOpen = Date.now() + (root.phase % 2 === 0 ? 3200 : 500);
        }
    }
}
