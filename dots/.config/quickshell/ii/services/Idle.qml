pragma Singleton
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/** Keeps hypridle from locking, blanking or suspending the session on idle. */
Singleton {
    id: root

    property bool inhibit: false
    property bool active: false
    property bool loaded: false
    property bool restored: false
    property bool changedBeforeReady: false

    // Start with the main shell, even if no keep-awake button is visible.
    // Settings previews must not acquire their own inhibitor or rewrite state.
    function load() {
        root.loaded = true;
        Qt.callLater(root.restore);
    }

    function restore() {
        if (!root.loaded || !Persistent.ready || root.restored) return;
        if (!root.changedBeforeReady)
            root.inhibit = Persistent.states.idle.inhibit;
        root.restored = true;
        Persistent.states.idle.inhibit = root.inhibit;
        root.reconcile();
    }

    Connections {
        target: Persistent
        function onReadyChanged() {
            // Let Persistent finish comparing the compositor session signatures.
            Qt.callLater(root.restore);
        }
    }

    function toggleInhibit(active = null) {
        root.inhibit = active !== null ? active : !root.inhibit;
        if (!root.restored) root.changedBeforeReady = true;
        if (root.loaded && Persistent.ready)
            Persistent.states.idle.inhibit = root.inhibit;
        root.reconcile();
    }

    function reconcile() {
        if (!root.loaded || !root.inhibit) {
            root.active = false;
            // EOF lets the child exit and release the lock, including on shell exit.
            inhibitor.stdinEnabled = false;
            return;
        }
        if (!inhibitor.running) {
            inhibitor.stdinEnabled = true;
            inhibitor.running = true;
        }
    }

    // A Wayland inhibitor on a transparent layer can be ignored by Hyprland.
    // hypridle also honors logind's idle inhibitors, independently of surfaces.
    // Only inhibit idle: explicit suspend and lid handling keep their usual behavior.
    Process {
        id: inhibitor
        command: ["systemd-inhibit", "--what=idle", "--mode=block", "--who=Velora",
            "--why=Keep system awake", "--", "sh", "-c", "printf 'ready\\n'; exec cat >/dev/null"]
        stdout: SplitParser {
            onRead: line => {
                if (line === "ready" && root.inhibit && inhibitor.stdinEnabled)
                    root.active = true;
            }
        }
        stderr: SplitParser { onRead: line => console.warn("[Idle]", line) }
        onExited: root.active = false
    }

    // Also covers failed starts and a lost helper without resetting the user's choice.
    Timer {
        interval: 2000
        repeat: true
        running: root.loaded && root.inhibit && !inhibitor.running
        onTriggered: root.reconcile()
    }

    IpcHandler {
        target: "idleInhibitor"
        function set(enabled: bool): void { root.toggleInhibit(enabled); }
        function status(): string {
            return JSON.stringify({ requested: root.inhibit, active: root.active, restored: root.restored });
        }
    }
}
