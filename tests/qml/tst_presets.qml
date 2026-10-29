import QtQuick
import QtTest

Item {
    width: 120
    height: 80
    SignalSpy { id: applied; target: Presets; signalName: "applied" }

    TestCase {
        name: "PresetPreparation"
        when: windowShown

        function preset(id, wallpaper) {
            return { id: id, name: id, kind: "user", dir: "/presets",
                bar: {config: {bar: {marker: id}}},
                theme: {config: {}, mode: "dark", accent: "#112233"},
                wallpaperAnimations: {config: {}, wallpaper: wallpaper} };
        }
        function finishProcess(object, code) {
            object.running = false;
            object.exited(code, 0);
        }
        function backup() { return findChild(Presets, "backupProc"); }
        function download() { return findChild(Presets, "downloadProc"); }
        // switchwall --prepare prints the prepared request as its last line
        function finishPrepare(wallpaper) {
            tryVerify(() => findChild(Presets, "themePrepareJob") !== null);
            const job = findChild(Presets, "themePrepareJob");
            verify(job.command.includes("--prepare"));
            job.stdout.text = "noise\n" + JSON.stringify({ request: "/cache/request.env", staged: true, wallpaper: wallpaper,
                thumbnail: "", keepShader: false, accent: "#112233" });
            job.stdout.streamFinished();
            return job;
        }
        function init() {
            Presets.applyCount++;
            Presets.applying = false;
            Presets.pending = null;
            Presets.activeTransition = 0;
            Config.patches = [];
            ThemeTransition.holds = [];
            ThemeTransition.runs = 0;
            ThemeTransition.captures = 0;
            ThemeTransition.phase = "idle";
            Presets.postRequest = "";
            Quickshell.detached = [];
            WallpaperTransition.screens = {};
            WallpaperTransition.preloaded = {};
            MaterialThemeLoader.pendingColors = "";
            applied.clear();
        }

        function test_onboarding_preview_keeps_card_and_palette_animations_live() {
            Presets.presets = [preset("vertical", "/pictures/new.jpg")];
            const number = findChild(Presets, "presetsIpc").applyForOnboarding("vertical", "theme", "", "");
            compare(number, Presets.applyCount);
            verify(ThemeTransition.captureInhibited);
            finishProcess(backup(), 0);
            finishPrepare("");
            compare(Config.patches.length, 1);
            compare(ThemeTransition.captures, 0);
            let paletteChanged = false;
            ThemeTransition.run(() => { paletteChanged = true; });
            verify(paletteChanged);
            compare(ThemeTransition.captures, 0);
            finishProcess(findChild(Presets, "themeCommitJob"), 0);
            tryCompare(Presets, "applying", false);
            verify(!ThemeTransition.captureInhibited);
            compare(Presets.postRequest, "");
            verify(Quickshell.detached.some(command => command.includes("--post")));
            // Regular preset changes regain the full transition after setup's preview finishes.
            ThemeTransition.run(() => {});
            compare(ThemeTransition.captures, 1);
        }

        function test_regular_preset_supersedes_onboarding_capture_inhibition() {
            Presets.presets = [preset("vertical", ""), preset("regular", "")];
            Presets.apply("vertical", ["theme"], "", "", true);
            verify(ThemeTransition.captureInhibited);
            Presets.apply("regular", ["theme"]);
            verify(!ThemeTransition.captureInhibited);
        }

        function test_autumn_uses_its_scheme_while_preparing() {
            const autumn = preset("autumn", "");
            autumn.theme = { config: {appearance: {palette: {type:"scheme-content"}}}, mode:"dark", accent:"#FF6D00" };
            const args = Presets.themeArgs(autumn, ["theme"], "");
            compare(args[args.indexOf("--type") + 1], "scheme-content");
            compare(args[args.indexOf("--color") + 1], "#FF6D00");
            compare(args[args.indexOf("--mode") + 1], "dark");
        }

        function test_changing_mode_on_repeat_keeps_the_current_accent() {
            Presets.presets = [preset("layout", "")];
            Presets.apply("layout", ["theme"], "current", "light");
            const theme = Presets.pending.preset.theme;
            compare(theme.mode, "light");
            compare(theme.accent, "#abcdef");
            verify(theme.config === undefined);
        }

        function test_remote_wallpaper_is_prepared_before_capturing_or_restyling() {
            Presets.presets = [preset("remote", "https://example.invalid/remote.jpg")];
            Presets.apply("remote");
            finishProcess(backup(), 0);
            verify(download().running);
            compare(Config.patches.length, 0);
            compare(ThemeTransition.runs, 0);
            finishProcess(download(), 0);
            // The palette is generated while the screen is still live
            compare(ThemeTransition.runs, 0);
            const prepare = findChild(Presets, "themePrepareJob");
            verify(prepare.command.includes("/pictures/Wallpapers/Presets/remote.jpg"));
            finishPrepare("/pictures/Wallpapers/Presets/remote.jpg");
            compare(ThemeTransition.runs, 1);
            compare(Config.patches.length, 1);
            compare(Config.patches[0].bar.marker, "remote");
            // Published by the shell in its one write, not by switchwall afterwards
            compare(Config.patches[0].background.wallpaperPath, "/pictures/Wallpapers/Presets/remote.jpg");
            compare(Config.patches[0].appearance.palette.accentColor, "#112233");
            tryVerify(() => findChild(Presets, "themeCommitJob") !== null);
            const job = findChild(Presets, "themeCommitJob");
            compare(job.command.slice(1), ["--commit", "/cache/request.env", "--no-publish", "--no-post"]);
            finishProcess(job, 0);
            tryCompare(Presets, "applying", false);
            compare(ThemeTransition.holds.length, 0);
            compare(Presets.postRequest, "/cache/request.env");
        }

        function test_capture_waits_for_the_new_picture_to_be_decoded() {
            Presets.presets = [preset("local", "/pictures/new.jpg")];
            WallpaperTransition.screens = { one: { path: "/pictures/old.jpg" }, two: { path: "/pictures/old.jpg" } };
            WallpaperTransition.preloaded = {};
            Presets.apply("local");
            finishProcess(backup(), 0);
            finishPrepare("/pictures/new.jpg");
            compare(ThemeTransition.runs, 0);
            WallpaperTransition.reportPreloaded("one", "/pictures/new.jpg");
            compare(ThemeTransition.runs, 0);
            WallpaperTransition.reportPreloaded("two", "/pictures/new.jpg");
            compare(ThemeTransition.runs, 1);
            finishProcess(findChild(Presets, "themeCommitJob"), 0);
            WallpaperTransition.screens = {};
            tryCompare(Presets, "applying", false);
        }

        function test_failed_preparation_still_applies_the_slow_way() {
            Presets.presets = [preset("local", "/pictures/new.jpg")];
            Presets.apply("local");
            finishProcess(backup(), 0);
            tryVerify(() => findChild(Presets, "themePrepareJob") !== null);
            finishProcess(findChild(Presets, "themePrepareJob"), 1);
            compare(ThemeTransition.runs, 1);
            tryVerify(() => findChild(Presets, "themeColorJob") !== null);
            finishProcess(findChild(Presets, "themeColorJob"), 0);
            tryCompare(Presets, "applying", false);
        }

        function test_release_waits_for_wallpaper_and_pending_palette() {
            Presets.presets = [preset("local", "/pictures/new.jpg")];
            Presets.apply("local");
            finishProcess(backup(), 0);
            finishPrepare("/pictures/new.jpg");
            WallpaperTransition.begin("one", "/pictures/new.jpg");
            WallpaperTransition.begin("two", "/pictures/new.jpg");
            MaterialThemeLoader.pendingColors = "still reading";
            tryVerify(() => findChild(Presets, "themeCommitJob") !== null);
            finishProcess(findChild(Presets, "themeCommitJob"), 0);
            WallpaperTransition.finish("one", "/pictures/new.jpg");
            wait(180);
            compare(ThemeTransition.holds.length, 1);
            WallpaperTransition.finish("two", "/pictures/new.jpg");
            wait(180);
            compare(ThemeTransition.holds.length, 1);
            MaterialThemeLoader.pendingColors = "";
            tryCompare(Presets, "applying", false);
            compare(ThemeTransition.holds.length, 0);
            compare(applied.count, 1);
        }

        function test_late_download_cannot_replace_a_newer_preset() {
            Presets.presets = [preset("old", "https://example.invalid/old.jpg"),
                {id: "new", bar: {config: {bar: {marker: "new"}}}}];
            Presets.apply("old");
            finishProcess(backup(), 0);
            Presets.apply("new");
            finishProcess(backup(), 0);
            finishProcess(download(), 0);
            compare(Config.patches.length, 1);
            compare(Config.patches[0].bar.marker, "new");
            compare(ThemeTransition.runs, 1);
            tryCompare(Presets, "applying", false);
        }

        function test_shader_uses_current_frame_and_waits_for_its_colors() {
            Presets.presets = [preset("shader", "shader:aurora")];
            Presets.apply("shader");
            finishProcess(backup(), 0);
            verify(ShaderWallpaper.framePending);
            ShaderWallpaper.frameSaved("/stale/other.png");
            verify(ShaderWallpaper.framePending);
            compare(ThemeTransition.holds.length, 1);
            ShaderWallpaper.frameSaved(ShaderWallpaper.framePath("aurora"));
            const job = findChild(ShaderWallpaper, "shaderColorJob");
            verify(job !== null);
            verify(job.command.includes("--keep-shader"));
            finishProcess(job, 0);
            tryCompare(Presets, "applying", false);
            compare(ThemeTransition.holds.length, 0);
        }
    }
}
