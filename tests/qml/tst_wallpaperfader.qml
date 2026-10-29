import QtQuick
import QtTest

Item {
    id: viewport
    width: 200
    height: 140

    WallpaperFader { id: fader; anchors.fill: parent; duration: 120 }
    SignalSpy { id: finished; target: fader; signalName: "finished" }

    TestCase {
        name: "WallpaperFader"
        when: windowShown

        function init() {
            viewport.width = 200;
            viewport.height = 140;
            fader.zoom = 1;
            fader.clear();
            wait(1);
            finished.clear();
            fader.duration = 120;
            fader.show(Qt.resolvedUrl("red.svg").toString(), 400, 200);
            tryVerify(() => fader.ready);
            tryCompare(finished, "count", 1);
        }

        function test_different_aspect_keeps_previous_geometry() {
            const previous = fader.current;
            const geometry = [previous.x, previous.y, previous.width, previous.height];
            fader.show(Qt.resolvedUrl("blue.svg").toString(), 120, 500);
            tryVerify(() => fader.current !== previous);
            compare([previous.x, previous.y, previous.width, previous.height], geometry);
            compare(previous.status, Image.Ready);
            tryCompare(finished, "count", 2);
            tryCompare(fader.pictures(), "length", 1);
            compare(fader.current.scale, 1);
        }

        function test_each_layer_covers_resized_viewport() {
            fader.preload(Qt.resolvedUrl("blue.svg").toString(), 120, 500);
            tryVerify(() => fader.preloaded.status === Image.Ready);
            const current = fader.current;
            const ahead = fader.preloaded;
            for (const size of [[344, 144], [151, 101], [108, 192]]) {
                viewport.width = size[0];
                viewport.height = size[1];
                for (const picture of [current, ahead]) {
                    verify(picture.width + 0.001 >= fader.width);
                    verify(picture.height + 0.001 >= fader.height);
                    fuzzyCompare(picture.width / picture.height, picture.imageWidth / picture.imageHeight, 0.000001);
                }
            }
            fader.zoom = NaN;
            verify(isFinite(current.width) && current.width >= fader.width);
            fader.show(ahead.path, 120, 500);
            tryCompare(finished, "count", 2);
            compare(fader.current, ahead);
        }

        function test_blends_pixels_without_black_frame() {
            fader.duration = 500;
            fader.show(Qt.resolvedUrl("blue.svg").toString(), 400, 200);
            tryVerify(() => fader.current.opacity > 0.2 && fader.current.opacity < 0.8);
            const frame = grabImage(fader);
            verify(frame.red(100, 70) > 30);
            verify(frame.blue(100, 70) > 30);
            compare(frame.green(100, 70), 0);
            tryCompare(finished, "count", 2);
        }

        function test_latest_request_wins() {
            fader.show(Qt.resolvedUrl("blue.svg").toString(), 120, 500);
            fader.cancelPending();
            fader.show(Qt.resolvedUrl("green.svg").toString(), 400, 200);
            tryVerify(() => fader.current.path.endsWith("green.svg"));
            tryCompare(finished, "count", 2);
            tryCompare(fader.pictures(), "length", 1);
            compare(grabImage(fader).green(100, 70), 255);
        }

        function test_failed_picture_keeps_previous() {
            const previous = fader.current;
            fader.show(Qt.resolvedUrl("missing.svg").toString(), 400, 200);
            tryCompare(fader, "incoming", null);
            compare(fader.current, previous);
            compare(fader.current.opacity, 1);
            verify(fader.ready);
        }

        function test_motion_disabled() {
            fader.duration = 0;
            fader.show(Qt.resolvedUrl("blue.svg").toString(), 400, 200);
            tryCompare(finished, "count", 2);
            compare(fader.current.opacity, 1);
        }

        function test_all_screens_and_stale_completion() {
            WallpaperTransition.begin("one", "old");
            WallpaperTransition.begin("two", "new");
            WallpaperTransition.begin("one", "new");
            WallpaperTransition.finish("one", "old");
            verify(WallpaperTransition.changing);
            WallpaperTransition.present("one", "new");
            WallpaperTransition.finish("one", "new");
            verify(WallpaperTransition.changing);
            WallpaperTransition.finish("two", "new");
            verify(!WallpaperTransition.changing);
            WallpaperTransition.remove("one");
            WallpaperTransition.remove("two");
        }
    }

    TestCase {
        name: "WallpaperColors"
        when: windowShown

        function palette(color) { return JSON.stringify({background: "#000000", primary: color}); }
        function init() {
            WallpaperTransition.screens = {};
            MaterialThemeLoader.initialized = false;
            MaterialThemeLoader.pendingColors = "";
            MaterialThemeLoader.wallpaperChange = false;
            ThemeTransition.runs = 0;
            ThemeTransition.deferred = false;
            ThemeTransition.changes = [];
            MaterialThemeLoader.queueColors(palette("#ff0000"));
        }
        function test_colors_blend_during_wallpaper_fade_without_capture() {
            WallpaperTransition.begin("one", "new");
            WallpaperTransition.begin("two", "new");
            MaterialThemeLoader.queueColors(palette("#0000ff"));
            wait(120);
            compare(Appearance.m3colors.m3primary, Qt.color("red"));
            WallpaperTransition.present("one", "new", 500);
            wait(100);
            compare(Appearance.m3colors.m3primary, Qt.color("red"));
            WallpaperTransition.present("two", "new", 500);
            wait(180);
            const intermediate = Appearance.m3colors.m3primary;
            verify(intermediate.r > 0.1 && intermediate.r < 0.9);
            verify(intermediate.b > 0.1 && intermediate.b < 0.9);
            verify(WallpaperTransition.changing);
            tryCompare(Appearance.m3colors, "m3primary", Qt.color("blue"));
            compare(ThemeTransition.runs, 0);
            WallpaperTransition.finish("one", "new");
            WallpaperTransition.finish("two", "new");
        }
        function test_partial_write_preserves_palette() {
            MaterialThemeLoader.queueColors('{"background":');
            wait(120);
            compare(Appearance.m3colors.m3primary, Qt.color("red"));
        }
        function test_regular_theme_keeps_its_transition() {
            MaterialThemeLoader.queueColors(palette("#0000ff"));
            tryCompare(ThemeTransition, "runs", 1);
            tryCompare(Appearance.m3colors, "m3primary", Qt.color("blue"));
        }
        function test_stale_captured_theme_cannot_overwrite_newer_colors() {
            ThemeTransition.deferred = true;
            MaterialThemeLoader.queueColors(palette("#0000ff"));
            tryCompare(ThemeTransition, "runs", 1);
            MaterialThemeLoader.queueColors(palette("#00ff00"));
            tryCompare(ThemeTransition, "runs", 2);
            ThemeTransition.flush();
            tryCompare(Appearance.m3colors, "m3primary", Qt.color("#00ff00"));
        }
    }
}
