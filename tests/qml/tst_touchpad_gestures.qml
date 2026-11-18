import QtQuick
import QtTest

TestCase {
    name: "TouchpadGestures"
    when: windowShown
    readonly property var overview: TouchpadGestures.overview
    readonly property var library: TouchpadGestures.library

    function send(action, phase, amount, direction = "") {
        Hyprland.rawEvent({ name: "custom", data: ["gesture", action, phase, amount, direction].join(":") });
    }

    function init() {
        Appearance.animate = false;
        TouchpadGestures.cancelGesture();
        GlobalStates.overviewOpen = false;
        GlobalStates.appLibraryOpen = false;
        overview.settle();
        library.settle();
        FreeWindows.calls = 0;
        Hyprland.commands = [];
        Appearance.animate = true;
    }

    function test_overview_tracks_holds_and_reverses() {
        send("overview", "begin", 0, "up");
        verify(overview.presenting);
        send("overview", "update", 0.52);
        compare(overview.progress, 0.52);
        compare(overview.offsetY, 0.48);
        wait(300);
        compare(overview.progress, 0.52);
        verify(!GlobalStates.overviewOpen);
        send("overview", "update", 0.12);
        fuzzyCompare(overview.progress, 0.12, 0.0001);
        send("overview", "end", 0.12);
        verify(overview.presenting);
        tryCompare(overview, "progress", 0);
        verify(!overview.presenting);

        send("overview", "begin", 0, "up");
        send("overview", "end", 0.42);
        verify(GlobalStates.overviewOpen);
        tryCompare(overview, "progress", 1);
        send("library", "begin", 0, "down");
        send("library", "update", 0.45);
        compare(overview.progress, 0.55);
        compare(overview.offsetY, 0.45);
        verify(!library.presenting);
        send("library", "cancel", 0.45);
        tryCompare(overview, "progress", 1);
        verify(GlobalStates.overviewOpen);
    }

    function test_all_apps_tracks_both_directions_and_pinch() {
        send("library", "begin", 0, "down");
        send("library", "update", 0.35);
        compare(library.progress, 0.35);
        compare(library.offsetY, -0.65);
        verify(!GlobalStates.appLibraryOpen);
        send("library", "end", 0.35);
        tryCompare(library, "progress", 1);
        verify(GlobalStates.appLibraryOpen);
        send("overview", "begin", 0, "up");
        send("overview", "update", 0.6);
        compare(library.progress, 0.4);
        compare(library.offsetY, -0.6);
        send("overview", "end", 0.6);
        tryCompare(library, "presenting", false);

        send("library", "begin", 0, "pinchin");
        send("library", "update", 0.25);
        compare(library.offsetY, 0);
        const pinchScale = library.scale;
        send("library", "update", 0.6);
        verify(library.scale < pinchScale);
        send("library", "end", 0.6);
        tryCompare(library, "progress", 1);
        send("desktop", "begin", 0, "pinchout");
        send("desktop", "end", 1);
        verify(!library.presenting);
        compare(FreeWindows.calls, 0);
    }

    function test_catch_settle_and_keyboard_interruption() {
        send("overview", "begin", 0, "up");
        send("overview", "end", 0.32);
        tryVerify(() => overview.progress > 0.32 && overview.progress < 1);
        const caught = overview.progress;
        send("library", "begin", 0, "down");
        compare(overview.progress, caught);
        wait(130);
        compare(overview.progress, caught);
        send("library", "update", 0.2);
        fuzzyCompare(overview.progress, caught - 0.2, 0.0001);
        GlobalStates.overviewOpen = false;
        send("library", "end", 0.05);
        tryCompare(overview, "presenting", false);
        verify(!GlobalStates.overviewOpen && !GlobalStates.appLibraryOpen);
    }

    function test_workspace_selection_waits_for_the_last_frame() {
        GlobalStates.overviewOpen = true;
        tryCompare(overview, "progress", 1);
        TouchpadGestures.leaveOverview("focus workspace 2");
        verify(overview.presenting);
        compare(Hyprland.commands.length, 0);
        tryCompare(overview, "presenting", false);
        compare(Hyprland.commands, ["focus workspace 2"]);

        Appearance.animate = false;
        GlobalStates.overviewOpen = true;
        TouchpadGestures.leaveOverview("move window");
        verify(!overview.presenting);
        compare(Hyprland.commands, ["focus workspace 2", "move window"]);
    }

    function test_external_workspace_change_cancels_selection_and_partial_gesture() {
        GlobalStates.overviewOpen = true;
        tryCompare(overview, "progress", 1);
        TouchpadGestures.leaveOverview("focus workspace 2");
        Hyprland.rawEvent({ name: "workspacev2", data: "3,3" });
        verify(!overview.presenting);
        compare(Hyprland.commands.length, 0);

        send("overview", "begin", 0, "up");
        send("overview", "update", 0.5);
        Hyprland.focusedWorkspaceChanged();
        verify(!overview.presenting);
        send("overview", "end", 1);
        verify(!GlobalStates.overviewOpen);
        GlobalStates.appLibraryOpen = true;
        Hyprland.focusedWorkspaceChanged();
        verify(GlobalStates.appLibraryOpen);
    }

    function test_reopening_the_chooser_discards_the_old_destination() {
        GlobalStates.overviewOpen = true;
        tryCompare(overview, "progress", 1);
        TouchpadGestures.leaveOverview("focus workspace 2");
        GlobalStates.overviewOpen = true;
        tryCompare(overview, "progress", 1);
        GlobalStates.overviewOpen = false;
        tryCompare(overview, "presenting", false);
        compare(Hyprland.commands.length, 0);
    }

    function test_reduced_motion_and_desktop_commit() {
        Appearance.animate = false;
        send("library", "begin", 0, "pinchin");
        send("library", "update", 0.4);
        compare(library.progress, 0.4);
        send("library", "cancel", 0.4);
        compare(library.progress, 0);
        GlobalStates.overviewOpen = true;
        compare(overview.progress, 1);
        GlobalStates.overviewOpen = false;
        compare(overview.progress, 0);

        send("desktop", "begin", 0, "pinchout");
        send("desktop", "update", 0.8);
        compare(TouchpadGestures.hintProgress, 0.8);
        send("desktop", "cancel", 0.8);
        compare(FreeWindows.calls, 0);
        send("desktop", "begin", 0, "pinchout");
        send("desktop", "end", 0.8);
        send("desktop", "end", 0.8);
        compare(FreeWindows.calls, 1);
    }

    function test_reopen_a_panel_sliding_out_in_the_same_direction_it_opened() {
        Appearance.animate = false;
        GlobalStates.appLibraryOpen = true;
        Appearance.animate = true;
        send("library", "begin", 0, "down");
        send("library", "end", 0.35);
        const caught = library.progress;
        const position = library.offsetY;
        verify(position > 0 && !GlobalStates.appLibraryOpen);
        send("overview", "begin", 0, "up");
        compare(library.offsetY, position);
        send("overview", "update", 0.2);
        fuzzyCompare(library.progress, caught + 0.2, 0.0001);
        verify(library.offsetY < position);
        send("overview", "end", 0.45);
        tryCompare(library, "progress", 1);
        verify(GlobalStates.appLibraryOpen && !GlobalStates.overviewOpen);
    }
}
