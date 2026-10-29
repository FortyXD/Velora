import QtQuick
import QtTest

Item {
    width: 200
    height: 160

    StatusIcon {
        id: icon
        anchors.centerIn: parent
        text: "wifi"
        iconSize: 32
    }

    TestCase {
        name: "StatusIcon"
        when: windowShown

        function init() {
            icon.busy = false;
            icon.visible = true;
            icon.text = "wifi";
        }

        function ring() { return findChild(icon, "statusBusyRing"); }
        function glyph() { return findChild(icon, "statusGlyph"); }

        function test_idle_is_upright() {
            compare(icon.rotation, 0);
            compare(glyph().rotation, 0);
            compare(ring().visible, false);
        }

        function test_connect_then_change_glyph() {
            icon.busy = true;
            tryVerify(() => ring().rotation > 0, 1000);
            compare(glyph().rotation, 0);
            icon.text = "lock";
            icon.busy = false;
            tryCompare(ring(), "rotation", 0);
            compare(glyph().text, "lock");
            compare(glyph().rotation, 0);
            compare(ring().visible, false);
        }

        function test_hidden_icon_stops_animation() {
            icon.busy = true;
            tryVerify(() => ring().rotation > 0, 1000);
            icon.visible = false;
            tryCompare(ring(), "rotation", 0);
            wait(80);
            compare(ring().rotation, 0);
            icon.visible = true;
            tryVerify(() => ring().rotation > 0, 1000);
            compare(glyph().rotation, 0);
        }

        function test_repeated_connect_disconnect() {
            for (let i = 0; i < 4; ++i) {
                icon.busy = true;
                tryVerify(() => ring().rotation > 0, 1000);
                icon.busy = false;
                tryCompare(ring(), "rotation", 0);
                compare(glyph().rotation, 0);
            }
        }
    }
}
