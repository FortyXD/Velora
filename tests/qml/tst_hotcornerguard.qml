import QtQuick
import QtTest

TestCase {
    name: "HotCornerActivationGuard"
    when: windowShown
    property int fires: 0
    Item { id: triggerArea; property bool containsMouse: false }
    QtObject { id: hotWindow; property var options: ({trigger: "hover"}) }
    Timer { id: dwellTimer; interval: 20; onTriggered: fires++ }

    HotCornerActivationGuard {
        id: guard
        screenWidth: 2000
        screenHeight: 1000
        size: 6
        // PRODUCTION_ALLOWED_HANDLER
    }

    function init() {
        triggerArea.containsMouse = false;
        hotWindow.options = {trigger: "hover"};
        dwellTimer.stop();
        fires = 0;
        guard.suppressed = false;
        guard.waitingForExit = false;
        guard.corner = "topRight";
        guard.circular = false;
        guard.screenX = 0;
        guard.screenY = 0;
        guard.screenWidth = 2000;
        guard.screenHeight = 1000;
        guard.size = 6;
    }

    function test_releaseInCornerStaysBlockedUntilExit() {
        guard.suppressed = true;
        triggerArea.containsMouse = true;
        verify(!guard.allowed);
        guard.resumeAt(1999, 0, true);
        guard.suppressed = false;
        verify(!guard.allowed);
        wait(200); // Not a cooldown that expires and opens a menu under the pointer.
        verify(!guard.allowed);
        compare(fires, 0);
        triggerArea.containsMouse = false;
        guard.pointerExited();
        verify(guard.allowed);
    }

    function test_otherCornersAreImmediatelyAvailable() {
        for (const corner of ["topLeft", "topRight", "bottomLeft", "bottomRight"]) {
            guard.corner = corner;
            guard.suppressed = true;
            guard.resumeAt(1000, 500, true);
            guard.suppressed = false;
            verify(guard.allowed, corner);
        }
    }

    function test_hideExitDuringSelectionDoesNotRearm() {
        guard.suppressed = true;
        guard.pointerExited();
        verify(guard.waitingForExit);
        guard.resumeAt(1999, 0, true);
        guard.suppressed = false;
        verify(!guard.allowed);
        guard.pointerExited();
        verify(guard.allowed);
    }

    function test_logicalGeometryWithNegativeMonitorOffset() {
        guard.screenX = -1200;
        guard.screenY = 800;
        guard.screenWidth = 1000; // Logical dimensions, not physical scaled pixels.
        guard.screenHeight = 600;
        const cases = [
            ["topLeft", -1200, 800], ["topRight", -201, 800],
            ["bottomLeft", -1200, 1399], ["bottomRight", -201, 1399]
        ];
        for (const row of cases) {
            guard.corner = row[0];
            guard.resumeAt(row[1], row[2], true);
            verify(!guard.allowed, row[0]);
            guard.pointerExited();
            verify(guard.allowed);
            guard.resumeAt(-700, 1100, true);
            verify(guard.allowed);
        }
        guard.corner = "bottomRight";
        guard.resumeAt(-200, 1400, true); // Right/bottom edges are exclusive.
        verify(guard.allowed);
    }

    function test_circleMatchesQuarterRadiusNotBoundingSquare() {
        guard.circular = true;
        guard.size = 12;
        for (const corner of ["topLeft", "topRight", "bottomLeft", "bottomRight"]) {
            guard.corner = corner;
            const cx = corner.endsWith("Left") ? 0 : 2000;
            const cy = corner.startsWith("top") ? 0 : 1000;
            const sx = corner.endsWith("Left") ? 1 : -1;
            const sy = corner.startsWith("top") ? 1 : -1;
            guard.resumeAt(cx + sx, cy + sy, true);
            verify(!guard.allowed, corner);
            guard.resumeAt(cx + sx * 10, cy + sy * 10, true);
            verify(guard.allowed, "bounding-square point outside circle: " + corner);
        }
    }

    function test_freshHoverDuringCursorCheckIsNotLost() {
        guard.suppressed = true;
        triggerArea.containsMouse = true; // A fresh entry while the query is pending.
        guard.resumeAt(1000, 500, true); // The sampled release point is not this corner.
        guard.suppressed = false;
        verify(guard.allowed);
        tryCompare(this, "fires", 1);
    }

    function test_clickModeDoesNotTurnIntoHover() {
        hotWindow.options = {trigger: "click"};
        guard.suppressed = true;
        triggerArea.containsMouse = true;
        guard.resumeAt(1000, 500, true);
        guard.suppressed = false;
        verify(guard.allowed);
        wait(40);
        compare(fires, 0);
    }

    function test_failedPositionIsSafeButRecoverable() {
        guard.resumeAt(0, 0, false);
        verify(!guard.allowed);
        guard.pointerExited();
        verify(guard.allowed);
        guard.suppressed = true;
        verify(!guard.allowed);
    }
}
