import QtQuick
import QtTest

Item {
    width: 120
    height: 80
    property int changes: 0
    property int retainedToken: 0
    SignalSpy { id: reveals; target: ThemeTransition; signalName: "revealRequested" }

    TestCase {
        name: "ThemeTransition"
        when: windowShown

        function init() {
            ThemeTransition.overlays = 2;
            ThemeTransition.captureInhibited = false;
            Appearance.animationSpeed = 1;
            changes = 0;
            retainedToken = 0;
            reveals.clear();
        }
        function acknowledge() {
            ThemeTransition.reportCaptured(ThemeTransition.generation, "left");
            ThemeTransition.reportCaptured(ThemeTransition.generation, "right");
        }
        function cleanup() {
            acknowledge();
            for (const token of ThemeTransition.holds.slice()) ThemeTransition.release(token);
            tryCompare(ThemeTransition, "phase", "idle", 2000);
        }

        function test_preset_waits_for_asynchronous_colors_and_wallpaper() {
            const token = ThemeTransition.run(value => { changes++; retainedToken = value; }, true);
            compare(changes, 0);
            ThemeTransition.reportCaptured(ThemeTransition.generation, "left");
            compare(changes, 0);
            ThemeTransition.reportCaptured(ThemeTransition.generation, "right");
            compare(changes, 1);
            compare(retainedToken, token);
            wait(220);
            compare(reveals.count, 0);
            compare(ThemeTransition.phase, "holding");
            ThemeTransition.release(token);
            tryCompare(reveals, "count", 1);
            compare(ThemeTransition.phase, "revealing");
        }

        function test_duplicate_and_stale_captures_do_not_uncover_the_scene() {
            ThemeTransition.run(() => { changes++; }, true);
            const generation = ThemeTransition.generation;
            ThemeTransition.reportCaptured(generation - 1, "right");
            ThemeTransition.reportCaptured(generation, "left");
            ThemeTransition.reportCaptured(generation, "left");
            compare(changes, 0);
            compare(ThemeTransition.phase, "capturing");
            ThemeTransition.reportCaptured(generation, "right");
            compare(changes, 1);
        }

        function test_newer_preset_keeps_its_own_readiness_token() {
            const first = ThemeTransition.run(() => { changes++; }, true);
            acknowledge();
            const second = ThemeTransition.run(() => { changes++; }, true);
            compare(changes, 2);
            ThemeTransition.release(first);
            wait(150);
            compare(reveals.count, 0);
            ThemeTransition.release(first); // Late completion of the old job is harmless.
            compare(ThemeTransition.holds.length, 1);
            ThemeTransition.release(second);
            tryCompare(reveals, "count", 1);
        }

        function test_failed_change_releases_its_snapshot() {
            ThemeTransition.run(() => { throw new Error("simulated failed preset"); }, true);
            acknowledge();
            compare(ThemeTransition.holds.length, 0);
            tryCompare(reveals, "count", 1);
        }

        function test_without_capture_or_with_motion_disabled_changes_apply_immediately() {
            ThemeTransition.overlays = 0;
            compare(ThemeTransition.run(() => { changes++; }, true), 0);
            compare(changes, 1);
            ThemeTransition.overlays = 2;
            Appearance.animationSpeed = 0;
            ThemeTransition.run(() => { changes++; }, true);
            compare(changes, 2);
            compare(ThemeTransition.phase, "idle");
        }

        function test_interactive_preview_runs_without_freezing_an_animated_frame() {
            const generation = ThemeTransition.generation;
            ThemeTransition.captureInhibited = true;
            compare(ThemeTransition.run(() => { changes++; }, true), 0);
            compare(changes, 1);
            compare(ThemeTransition.phase, "idle");
            compare(ThemeTransition.generation, generation);
            compare(reveals.count, 0);
            ThemeTransition.captureInhibited = false;
            ThemeTransition.run(() => { changes++; });
            compare(ThemeTransition.phase, "capturing");
            acknowledge();
            compare(changes, 2);
        }

        function test_interruption_during_reveal_starts_a_new_capture() {
            ThemeTransition.run(() => { changes++; });
            acknowledge();
            tryCompare(ThemeTransition, "phase", "revealing");
            const previous = ThemeTransition.generation;
            const token = ThemeTransition.run(() => { changes++; }, true);
            verify(ThemeTransition.generation > previous);
            ThemeTransition.reportCaptured(previous, "left");
            compare(changes, 1);
            acknowledge();
            compare(changes, 2);
            ThemeTransition.release(token);
        }
    }
}
