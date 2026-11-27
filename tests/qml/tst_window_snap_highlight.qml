import QtQuick
import QtTest

TestCase {
    id: test
    name: "WindowSnapHighlight"
    when: windowShown
    width: 960
    height: 600

    readonly property rect leftTarget: Qt.rect(0, 0, 0.5, 1)
    readonly property rect corner: Qt.rect(0, 0, 0.5, 0.5)
    readonly property rect rightTarget: Qt.rect(0.5, 0, 0.5, 1)
    property bool fadedIn: false
    property bool fadedOut: false
    property bool changedSize: false

    WindowSnapHighlight {
        id: hint
        onOpacityChanged: {
            if (opacity <= 0 || opacity >= 1) return;
            if (requested) test.fadedIn = true;
            else test.fadedOut = true;
        }
        onHeightChanged: if (height > test.height / 2 && height < test.height) test.changedSize = true;
    }

    function test_follow_drag() {
        hint.show(leftTarget);
        compare(hint.bounds, leftTarget);
        tryCompare(hint, "opacity", 1);
        verify(fadedIn);
        hint.show(corner);
        tryCompare(hint, "height", height / 2);
        verify(changedSize);
        hint.requested = false;
        tryCompare(hint, "opacity", 0);
        verify(fadedOut);
        Appearance.animate = false;
        hint.show(rightTarget);
        compare(hint.x, width / 2);
        compare(hint.opacity, 1);
        hint.show(corner);
        compare(hint.height, height / 2);
        hint.requested = false;
        compare(hint.opacity, 0);
    }
}
