import QtQuick
import QtTest

Item {
    id: scene
    width: 1200
    height: 900

    OnboardingFlow {
        id: flow
    }
    Component { id: viewComponent; OnboardingView { width:1200; height:900 } }
    Component { id: displayComponent; DisplayPage { width:1000; height:700 } }
    Component { id: appearanceComponent; AppearancePage { width:1000; height:700 } }
    SignalSpy { id: finished; target: flow; signalName: "finished" }

    TestCase {
        name: "OnboardingFlow"
        when: windowShown

        function test_network_step_follows_the_connectivity_seen_at_the_start() {
            flow.connectivityJudged = false;
            flow.online = true;
            Network.connectivity = "none";
            flow.judgeConnectivity();
            compare(flow.online, false);
            // Judged once: connecting during the assistant doesn't shift its steps
            Network.connectivity = "full";
            flow.judgeConnectivity();
            compare(flow.online, false);
            flow.connectivityJudged = false;
            flow.judgeConnectivity();
            compare(flow.online, true);
        }

        function init() {
            Quickshell.commands = [];
            flow.online = true;
            flow.loaded = true;
            flow.installState = "idle";
            flow.installer.running = false;
            flow.installer.writes = [];
            flow.preservePalette = false;
            flow.initializingTheme = false;
            flow.backupReady = true;
            flow.applyDone();
            flow.componentsLoaded = true;
            flow.appsChecked = true;
            flow.components = [];
            flow.apps = [];
            flow.missingApps = [];
            HyprlandMonitors.keep();
            HyprlandMonitors.overrides = {};
            HyprlandMonitors.monitors = [];
            HyprlandMonitors.ready = false;
            flow.displayChecked = false;
            flow.index = 0;
            flow.choices = { "look": "velora", "windows": "tiling", "wallpaper": "autumn", "components": [], "apps": [] };
            finished.clear();
        }
        function lastState() {
            return JSON.parse(flow.stateFile.written);
        }

        function test_steps_move_both_ways_and_are_saved() {
            flow.next();
            compare(flow.step, "language");
            compare(flow.direction, 1);
            compare(lastState().step, "language");
            flow.next();
            flow.back();
            compare(flow.step, "language");
            compare(flow.direction, -1);
            flow.go("done");
            compare(flow.step, "done");
            verify(flow.last);
        }

        function test_autumn_is_first_and_checked_even_when_palette_is_preserved() {
            const picture = id => ({ id:id, kind:"builtin", name:id, wallpaperPreview:"file:///unused-"+id,
                wallpaperAnimations:{wallpaper:"https://example.invalid/"+id+".jpg"} });
            Presets.presets = [picture("pastel"), picture("autumn"), picture("synthwave")];
            flow.preservePalette = true;
            const page = createTemporaryObject(appearanceComponent, scene, {flow:flow});
            compare(page.pictures.map(picture => picture.id), ["autumn", "pastel", "synthwave"]);
            compare(Presets.presets.map(picture => picture.id), ["pastel", "autumn", "synthwave"]);
            const autumn = findChild(page, "wallpaper-autumn");
            verify(autumn !== null);
            verify(autumn.selected);
            verify(!findChild(page, "wallpaper-pastel").selected);
            compare(flow.applying, "");
            autumn.clicked();
            verify(!flow.preservePalette);
            compare(flow.applying, "wallpaper");
        }

        function screen() {
            return {name:"eDP-1",width:1920,height:1080,refreshRate:60,scale:1,x:0,y:0,physicalWidth:300,
                availableModes:["1920x1080@60", "2560x1440@120"]};
        }

        function test_next_keeps_display_changes_after_the_rollback_deadline() {
            HyprlandMonitors.monitors = [screen()];
            HyprlandMonitors.ready = true;
            flow.go("display");
            const page = createTemporaryObject(displayComponent, scene, {flow:flow});
            verify(flow.displayChecked);
            page.change("eDP-1", {mode:"1920x1080@60",scale:1.25});
            verify(HyprlandMonitors.confirming);
            HyprlandMonitors.secondsLeft = 1;
            flow.next();
            verify(!HyprlandMonitors.confirming);
            verify(lastState().displayChecked);
            verify(!findChild(HyprlandMonitors, "countdown").running);
            wait(1100);
            compare(HyprlandMonitors.overrides["eDP-1"].scale, 1.25);
            const saved = JSON.parse(findChild(HyprlandMonitors, "jsonFile").written);
            compare(saved["eDP-1"].scale, 1.25);
            verify(findChild(HyprlandMonitors, "luaFile").written.includes("scale = 1.25"));
            flow.back();
            const revisited = createTemporaryObject(displayComponent, scene, {flow:flow});
            compare(HyprlandMonitors.overrides["eDP-1"].scale, 1.25);
            compare(HyprlandMonitors.overrides["eDP-1"].mode, "1920x1080@60");
            verify(!HyprlandMonitors.confirming);
        }

        function test_forward_jump_also_keeps_the_display_preview() {
            HyprlandMonitors.monitors = [screen()];
            flow.go("display");
            HyprlandMonitors.change("eDP-1", {scale:1.25});
            flow.go("appearance");
            verify(!HyprlandMonitors.confirming);
            compare(HyprlandMonitors.overrides["eDP-1"].scale, 1.25);
        }

        function test_enter_keeps_the_display_preview() {
            const view = createTemporaryObject(viewComponent, scene, {flow:flow});
            HyprlandMonitors.monitors = [screen()];
            HyprlandMonitors.ready = true;
            flow.go("display");
            HyprlandMonitors.change("eDP-1", {scale:1.25});
            tryCompare(findChild(view, "sheet"), "activeFocus", true);
            keyClick(Qt.Key_Return);
            compare(flow.step, "layout");
            verify(!HyprlandMonitors.confirming);
            compare(HyprlandMonitors.overrides["eDP-1"].scale, 1.25);
        }

        function test_late_monitor_read_does_not_change_displays_after_next() {
            flow.go("display");
            const page = createTemporaryObject(displayComponent, scene, {flow:flow});
            flow.next();
            HyprlandMonitors.monitors = [screen()];
            HyprlandMonitors.ready = true;
            verify(!flow.displayChecked);
            verify(!HyprlandMonitors.confirming);
            compare(Object.keys(HyprlandMonitors.overrides).length, 0);
        }

        function test_layout_events_update_immediately_including_variants() {
            HyprlandXkb.indexLayoutNames("! layout\n  us English (US)\n  ru Russian\n! variant\n  dvorak us: English (Dvorak)\n! option\n");
            HyprlandXkb.layoutCodes = ["us"];
            Hyprland.rawEvent({ name: "activelayout", data: "real-keyboard,Russian" });
            compare(HyprlandXkb.currentLayoutCode, "ru");
            Hyprland.rawEvent({ name: "activelayout", data: "real-keyboard,English (Dvorak)" });
            compare(HyprlandXkb.currentLayoutCode, "us");
            Hyprland.rawEvent({ name: "activelayout", data: "power-button,Russian" });
            compare(HyprlandXkb.currentLayoutCode, "us");
            Hyprland.rawEvent({ name: "activelayout", data: "real-keyboard,Russian" });
            compare(HyprlandXkb.currentLayoutCode, "ru");
        }

        function test_network_step_only_without_a_connection() {
            verify(!flow.steps.some(step => step.id === "network"));
            flow.online = false;
            verify(flow.steps.some(step => step.id === "network"));
        }

        function test_choosing_a_look_applies_its_preset_without_the_picture() {
            flow.applyLook("vertical");
            compare(flow.choices.look, "vertical");
            compare(flow.applying, "look");
            compare(flow.applyingId, "autumn");
            const request = findChild(flow, "presetApply-" + flow.applyRequest);
            compare(request.command.slice(5, 8), ["presets", "applyForOnboarding", "autumn"]);
            flow.applyWindows("floating");
            compare(Quickshell.commands[0].slice(-3), ["windowMode", "set", "floating"]);
        }

        function test_finishing_sets_how_windows_behave() {
            flow.finish(false);
            compare(Quickshell.commands[0].slice(-3), ["windowMode", "set", "tiling"]);
        }

        function test_a_resumed_setup_continues_where_it_stopped() {
            flow.loaded = false;
            flow.stateFile.content = JSON.stringify({ "completed": false, "step": "appearance", "displayChecked": true, "choices": { "look": "horizon" } });
            flow.stateFile.loaded();
            compare(flow.step, "appearance");
            compare(flow.choices.look, "horizon");
            verify(flow.displayChecked);
            verify(flow.loaded);
        }

        function test_a_finished_one_starts_over() {
            flow.loaded = false;
            flow.stateFile.content = JSON.stringify({ "completed": true, "step": "done", "choices": {} });
            flow.stateFile.loaded();
            compare(flow.step, "hello");
        }

        function test_skipping_remembers_it() {
            flow.skip();
            verify(lastState().skipped);
            compare(finished.count, 1);
            compare(finished.signalArguments[0][0], false);
        }

        function selectExtras() {
            flow.components = [{ id: "toolbox", installed: false, missingRepo: ["shared", "ocr"], missingAur: ["aur-tool"] }];
            flow.apps = [{ package: "shared", name: "Shared app" }];
            flow.missingApps = ["shared"];
            flow.choose("components", ["toolbox"]);
            flow.choose("apps", ["shared"]);
            flow.go("install");
        }

        function test_password_blocks_all_navigation() {
            selectExtras();
            flow.askPassword();
            for (const state of ["password", "wrongPassword", "checking", "running"]) {
                flow.installState = state;
                flow.next();
                flow.back();
                flow.go("done");
                flow.finish(true);
                flow.skip();
                compare(flow.step, "install", state);
                compare(finished.count, 0, state);
            }
            flow.installState = "wrongPassword";
            flow.cancelPassword();
            compare(flow.installState, "idle");
            flow.next();
            compare(flow.step, "done");
        }

        function test_install_waits_for_process_start_and_can_retry() {
            selectExtras();
            flow.askPassword();
            flow.install("secret");
            compare(flow.installState, "checking");
            compare(flow.installer.writes.length, 0);
            const args = flow.installer.command;
            compare(args[args.indexOf("--repo") + 1], "shared,ocr");
            compare(args[args.indexOf("--aur") + 1], "aur-tool");
            verify(!args.includes("secret"));
            flow.installer.started();
            compare(flow.installer.writes, ["secret\n"]);
            compare(flow.pendingPassword, "");
            verify(!flow.installer.stdinEnabled);
            flow.installer.running = false;
            flow.installer.exited(3, 0);
            compare(flow.installState, "wrongPassword");
            flow.install("retry");
            verify(flow.installer.stdinEnabled);
            flow.installer.started();
            compare(flow.installer.writes, ["secret\n", "retry\n"]);
            flow.installer.stdout.read("::phase repo");
            compare(flow.installState, "running");
            flow.installer.stderr.read("download failed");
            compare(flow.installLine, "download failed");
            flow.installer.running = false;
            flow.installer.exited(1, 0);
            compare(flow.installState, "failed");
        }

        function test_failed_process_start_leaves_checking() {
            selectExtras();
            flow.askPassword();
            flow.install("secret");
            flow.installer.running = false;
            tryCompare(flow, "installState", "failed");
            compare(flow.pendingPassword, "");
        }

        function test_enter_submits_password_without_leaving_the_step() {
            const view = createTemporaryObject(viewComponent, scene, {flow:flow});
            selectExtras();
            const field = findChild(view, "passwordField");
            verify(field !== null);
            tryCompare(field, "activeFocus", true);
            keyClick(Qt.Key_Return);
            compare(flow.installState, "password");
            compare(flow.step, "install");
            keyClick(Qt.Key_A);
            compare(field.text, "a");
            keyClick(Qt.Key_Return);
            compare(flow.installState, "checking");
            compare(flow.pendingPassword, "a");
            compare(flow.step, "install");
            keyClick(Qt.Key_Return);
            compare(flow.step, "install");
            flow.installer.started();
            flow.installer.running = false;
            flow.installer.exited(3, 0);
            tryCompare(field, "activeFocus", true);
            compare(field.text, "");
            keyClick(Qt.Key_B);
            keyClick(Qt.Key_Return);
            compare(flow.pendingPassword, "b");
            compare(flow.step, "install");
        }

        function test_escape_cancels_password_without_going_back() {
            const view = createTemporaryObject(viewComponent, scene, {flow:flow});
            selectExtras();
            const field = findChild(view, "passwordField");
            tryCompare(field, "activeFocus", true);
            keyClick(Qt.Key_Escape);
            compare(flow.installState, "idle");
            compare(flow.step, "install");
        }

        function test_completed_install_can_continue() {
            selectExtras();
            flow.askPassword();
            flow.install("secret");
            flow.installer.started();
            flow.installer.running = false;
            flow.installer.exited(0, 0);
            compare(flow.installState, "done");
            flow.next();
            compare(flow.step, "done");
            flow.finish(true);
            verify(lastState().completed);
            compare(finished.signalArguments[0][0], true);
        }

        function test_first_launch_prepares_autumn_before_showing() {
            flow.loaded = false;
            flow.stateFile.loadFailed();
            verify(flow.initializingTheme);
            verify(!flow.ready);
            compare(flow.applyingId, "autumn");
            flow.applyDone();
            verify(flow.ready);
            verify(MaterialThemeLoader.reloads > 0);
        }

        function test_repeat_keeps_the_users_palette() {
            flow.loaded = false;
            flow.stateFile.content = JSON.stringify({ completed: true, choices: { wallpaper: "pastel" } });
            flow.stateFile.loaded();
            verify(flow.preservePalette);
            verify(flow.ready);
            compare(flow.applying, "");
            flow.applyLook("horizon");
            verify(flow.preservePalette);
            flow.applyWallpaper("autumn");
            verify(!flow.preservePalette);
        }

        function test_nothing_to_install_opens_no_terminal() {
            flow.finish(false);
            verify(!Quickshell.commands.some(command => command[0] === "kitty"));
        }
    }
}
