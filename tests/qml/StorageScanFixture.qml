import QtQuick
import QtTest
import Quickshell
import qs.modules.common
import qs.modules.settings.storage

ShellRoot {
    id: root
    TestCase { id: input; when: false }
    FloatingWindow {
        implicitWidth: 720
        implicitHeight: 440
        visible: true
        color: Appearance.colors.colLayer2
        StorageExplorer {
            id: map
            anchors.centerIn: parent
            width: parent.width - 32
            mountPoints: []
            formatBytes: bytes => String(bytes)
            onWorkerChanged: if (worker) worker.environment = { VELORA_HELPER: Quickshell.env("TEST_SCAN_HELPER") }
        }
    }

    property int step: 0
    property bool capturing: false
    property var chartItem: null
    property bool sawReveal: false
    property bool sawZoomIn: false
    property bool sawZoomOut: false
    Connections {
        target: root.chartItem
        function onProgressChanged() {
            const chart = root.chartItem;
            if (!chart.origin || chart.progress < 0.12 || chart.progress > 0.8) return;
            if (chart.origin.id < 0 && !root.sawReveal && !root.capturing) {
                root.sawReveal = true;
                root.capture(chart, "reveal", () => {});
            } else if (chart.origin.focus) {
                root.sawZoomIn = chart.drawnSectors.some((s, i) => Math.abs(s.outer - chart.sectors[i].outer) > 1);
            } else if (chart.returnSector?.entry.id === 1) {
                root.sawZoomOut = true;
            }
        }
    }
    function check(ok, message) {
        if (!ok) { console.log("CHECK_FAIL", step, message); Qt.quit(); }
        return ok;
    }
    function capture(item, name, next) {
        capturing = true;
        check(item.grabToImage(result => {
            if (!check(result.saveToFile(Quickshell.env("TEST_SCAN_IMAGES") + "/" + name + ".png"), "save " + name)) return;
            capturing = false;
            next();
        }), "capture " + name);
    }
    Timer {
        interval: 180
        running: true
        repeat: true
        onTriggered: {
            if (root.capturing) return;
            const chart = input.findChild(map, "storageRings");
            const sweep = input.findChild(map, "storageScanIndicator");
            switch (root.step) {
            case 0:
                if (map.scanned !== 16) return;
                root.chartItem = chart;
                if (!root.check(sweep.visible && sweep.busy && !chart.visible && !map.current && !map.entries.length,
                                "partial directory data only updates the scan count")) return;
                root.capture(sweep, "first", () => map.worker.write("continue\n"));
                break;
            case 1:
                if (map.scanned !== 42) return;
                if (!root.check(!chart.visible && sweep.busy, "loading throughout the scan")) return;
                root.capture(sweep, "second", () => map.worker.write("finish\n"));
                break;
            case 2: {
                if (!map.current || chart.progress < 1) return;
                if (!root.check(root.sawReveal && chart.visible && !sweep.visible && chart.sectors.length === 4, "finished rings omit the subpixel slice")) return;
                if (!root.check(!chart.hit(chart.width / 2, chart.height / 2 - chart.hole - chart.band), "space between rings is not clickable")) return;
                root.capture(chart, "rings", () => map.activate(map.entries[0]));
                break;
            }
            case 3:
                if (!map.current || map.frame.id !== 1 || chart.progress < 1) return;
                if (!root.check(root.sawZoomIn, "the selected sector expands into the new map")) return;
                map.goUp();
                break;
            case 4:
                if (!map.current || map.frame.id !== 0 || chart.progress < 1) return;
                if (!root.check(root.sawZoomOut, "returning folds the map back into its sector")) return;
                Config.options.appearance.animationSpeed = 0;
                map.activate(map.entries[0]);
                break;
            case 5:
                if (!map.current || map.frame.id !== 1) return;
                if (!root.check(chart.progress === 1 && !chart.origin, "motion disabled shows the new view immediately")) return;
                map.startScan(map.scanPath);
                if (!root.check(sweep.visible && !chart.visible && !map.scanned, "rescan immediately replaces the previous chart")) return;
                break;
            case 6:
                if (map.scanned !== 16) return;
                map.worker.write("fail\n");
                break;
            case 7:
                if (!map.failed) return;
                if (!root.check(!sweep.busy && !chart.visible, "a failed scan stops the indicator")) return;
                console.log("DRIVER_PASS");
                Qt.quit();
            }
            root.step++;
        }
    }
    Timer { interval: 6000; running: true; onTriggered: { console.log("CHECK_FAIL timeout", root.step); Qt.quit(); } }
}
