"""Exercise the disk map from its General settings entry, using a private home and volume."""
import json
import math
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from urllib.parse import unquote, urlsplit

import test_connectivity_pages as pages


@unittest.skipUnless((pages.QS and pages.CARGO and pages.DBUS) or pages.REQUIRED, 'needs the settings test runtime')
class StoragePageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        pages.SettingsPagesTests.setUpClass()

    def test_scan_animation_and_thin_sector_edges(self):
        from PIL import Image, ImageChops

        # Hold each frame until the UI has inspected it, independent of local disk speed.
        last_ring = [{'name': 'large', 'uri': 'file:///large', 'bytes': 599999999},
                     {'name': 'tiny', 'uri': 'file:///tiny', 'bytes': 1}]
        middle = [{'name': 'branch', 'id': 2, 'bytes': 600000000, 'children': last_ring},
                  {'name': 'file', 'uri': 'file:///file', 'bytes': 400000000}]
        frame = {'id': 0, 'parent': None, 'offset': 0, 'previousOffset': 0, 'path': '/', 'bytes': 1000000000,
                 'children': [{'name': 'whole', 'id': 1, 'bytes': 1000000000, 'children': middle}]}
        driver = (pages.PROJECT / 'tests/qml/StorageScanFixture.qml').read_text()
        with tempfile.TemporaryDirectory() as tmp:
            helper = Path(tmp) / 'scanner'
            child = dict(frame, id=1, parent=0, path='/whole', children=middle, scanned=64, done=True)
            messages = [dict(frame, scanned=16, done=False), dict(id=0, offset=0, scanned=42, done=False),
                        dict(frame, scanned=64, done=True), child]
            helper.with_suffix('.jsonl').write_text('\n'.join(map(json.dumps, messages)))
            helper.write_text("""#!/usr/bin/python3
from pathlib import Path
import json
import sys
first, second, root, child = Path(__file__).with_suffix('.jsonl').read_text().splitlines()
for update, expected in [(first, 'continue'), (second, 'finish')]:
    print(update, flush=True)
    if sys.stdin.readline().strip() != expected:
        sys.exit(1)
print(root, flush=True)
for request in sys.stdin:
    print([root, child][json.loads(request)[0]], flush=True)
""")
            helper.chmod(0o755)
            for scale in ('1', '1.5'):
                images = Path(tmp) / scale
                images.mkdir()
                env = {'TEST_SCAN_HELPER': str(helper), 'TEST_SCAN_IMAGES': str(images), 'QT_SCALE_FACTOR': scale}
                with self.subTest(scale=scale), patch.dict(os.environ, env):
                    case = pages.SettingsPagesTests()
                    output = case.run_driver(driver)
                    self.assertIn('DRIVER_PASS', output, output[-3500:])
                    case.assert_clean(output)
                    with Image.open(images / 'first.png') as first, Image.open(images / 'second.png') as second:
                        self.assertTrue(ImageChops.difference(first.convert('RGB'), second.convert('RGB')).getbbox(),
                                        'The sweep moves while waiting for the final scan')
                    with Image.open(images / 'rings.png') as rings:
                        with Image.open(images / 'reveal.png') as reveal:
                            self.assertTrue(ImageChops.difference(rings.convert('RGB'), reveal.convert('RGB')).getbbox(),
                                            'The newly scanned rings visibly unfold')
                        def pixel(radius, angle):
                            return rings.getpixel((round(rings.width * (0.5 + radius * math.sin(angle))),
                                                   round(rings.height * (0.5 - radius * math.cos(angle)))))

                        edge = 0.6 * math.tau
                        track = pixel(0.44, 0.8 * math.tau)
                        self.assertEqual(pixel(0.44, edge + 0.035), track, 'The tiny slice leaves no cap beyond its parent')
                        self.assertNotEqual(pixel(0.44, edge - 0.035), track, 'The outer sector meets its boundary')
                        self.assertEqual(pixel(0.26, 0), pixel(0.26, math.pi), 'A full ring has no seam')
                        self.assertNotEqual(pixel(0.26, 0), rings.getpixel((0, 0)), 'The full ring is painted')
                        self.assertEqual(pixel(0.16, 0), rings.getpixel((0, 0)), 'The hub stays hollow')

    def test_live_map_and_navigation(self):
        probe = r'''
    TestCase { id: input; when: false }
    property int stage: 0
    property var scanPid
    readonly property string volume: Quickshell.env("TEST_MAP_VOLUME")
    function check(ok, message) {
        if (!ok) { console.log("CHECK_FAIL", stage, message); Qt.quit(); }
        return ok;
    }
    function clickSector(chart, name) {
        const s = chart.drawnSectors.find(s => s.entry.name === name);
        if (!check(!!s, "missing sector " + name)) return false;
        const angle = (s.start + s.end) / 2 - Math.PI / 2;
        const radius = (s.inner + s.outer) / 2;
        const x = chart.width / 2 + radius * Math.cos(angle), y = chart.height / 2 + radius * Math.sin(angle);
        input.mouseMove(chart, x, y);
        if (!check(chart.hoveredSector?.entry.name === name, "hovered ring")) return false;
        input.mouseClick(chart, x, y);
        return true;
    }
    Timer {
        interval: 120; repeat: true; running: true
        onTriggered: {
            if (!Config.ready || !root.currentPageItem?.pageShown) return;
            const storage = pageRepeater.itemAt(root.pageIndex("storage"));
            const loader = storage.item && input.findChild(storage.item, "storageExplorerLoader");
            const map = loader?.item;
            const chart = map && input.findChild(map, "storageRings");
            switch (root.stage) {
            case 0:
                if (!storage.item) { storage.load(); return; }
                if (!root.check(!loader.active && !map, "preloaded storage does not scan")) return;
                input.mouseClick(input.findChild(root.currentPageItem, "general-storage"));
                break;
            case 1: {
                if (!map?.frame?.done) return;
                if (!root.check(map.frame.path === Quickshell.env("HOME"), "home scan started on entry")) return;
                const scope = input.findChild(map, "storageLocation");
                if (!scope.options.some(option => option.value === root.volume)) return;
                scope.selected(root.volume);
                break;
            }
            case 2:
                if (!map?.frame?.done || map.frame.path !== root.volume) return;
                if (chart.progress < 1) return;
                if (!root.check(chart.sectors.some(s => s.depth === 2) && !map.canGoUp, "three nested rings")) return;
                const colors = map.entries.map((entry, index) => String(chart.colorFor(entry, index)));
                if (!root.check(new Set(colors).size === colors.length, "distinct legend colors")) return;
                root.scanPid = map.worker.processId;
                if (!root.clickSector(chart, "Archive")) return;
                break;
            case 3:
                if (map?.frame?.path !== root.volume + "/Downloads/Archive") return;
                if (chart.progress < 1) return;
                if (!root.check(map.worker.processId === root.scanPid && map.canGoUp, "drill into cached subtree")) return;
                if (!root.clickSector(chart, "a file, #1%.bin")) return;
                input.mouseClick(chart, chart.width / 2, chart.height / 2);
                break;
            case 4:
                if (map?.frame?.path !== root.volume + "/Downloads") return;
                root.goBack();
                break;
            case 5:
                if (map?.frame?.path !== root.volume) return;
                const more = map.entries.find(entry => entry.more);
                if (!root.check(!!more, "small items grouped")) return;
                map.activate(more);
                break;
            case 6:
                if (!map?.frame?.offset) return;
                if (!root.check(map.worker.processId === root.scanPid && map.entries.length > 0, "small items can be explored")) return;
                root.goBack();
                break;
            case 7:
                if (map?.frame?.offset !== 0) return;
                root.width = root.minimumWidth;
                input.findChild(map, "storageRescan").click();
                break;
            case 8:
                if (!map?.frame?.done || map.worker.processId === root.scanPid) return;
                if (!root.check(chart.width > 0 && chart.width <= map.width, "chart fits narrow settings")) return;
                root.scanPid = map.worker.processId;
                root.goBack();
                break;
            case 9:
                if (!root.check(root.currentPageData.key === "general" && map?.worker.processId === root.scanPid,
                                "a completed tree is retained briefly")) return;
                input.mouseClick(input.findChild(root.currentPageItem, "general-storage"));
                break;
            case 10: {
                if (!root.check(map?.current && map.worker.processId === root.scanPid && map.frame.path === root.volume,
                                "reopening immediately reuses the finished scan")) return;
                root.goBack();
                const lifetime = input.findChild(storage.item, "storageResultLifetime");
                lifetime.interval = 80;
                break;
            }
            case 11:
                if (loader.active) return;
                if (!root.check(!map, "the hidden scan releases its tree after expiry")) return;
                input.mouseClick(input.findChild(root.currentPageItem, "general-storage"));
                break;
            case 12:
                if (!map?.current) return;
                map.startScan(map.scanPath);
                root.goBack();
                break;
            case 13:
                if (!root.check(root.currentPageData.key === "general" && !loader.active && !map,
                                "leaving an unfinished rescan stops its worker")) return;
                console.log("DRIVER_PASS"); Qt.quit();
            }
            root.stage++;
        }
    }
    Timer { interval: 22000; running: true; onTriggered: { console.log("CHECK_FAIL timeout", root.stage); Qt.quit(); } }
'''
        host = (pages.SHELL / 'settings.qml').read_text().replace('import QtQuick\n', 'import QtQuick\nimport QtTest\n', 1)
        host = host.replace('    id: root\n', '    id: root\n' + probe, 1)
        with tempfile.TemporaryDirectory() as tmp:
            fixture = Path(tmp)
            volume = fixture / 'Volume  with spaces'
            archive = volume / 'Downloads/Archive'
            archive.mkdir(parents=True)
            file = archive / 'a file, #1%.bin'
            file.write_bytes(b'x' * 65536)
            for n in range(9):
                (volume / f'Small {n}').mkdir()
            df = fixture / 'df'
            df.write_text('#!/bin/sh\ncase "$2" in --output=source,size,used,avail,target)\n'
                          'printf "Filesystem Size Used Avail Mounted on\\nfixture 1000000 65536 934464 %s\\n" "$TEST_MAP_VOLUME";;\n'
                          '*) exec /usr/bin/df "$@";; esac\n')
            df.chmod(0o755)
            busctl = fixture / 'busctl'
            busctl.write_text('#!/bin/sh\nif [ "$6" = ShowItems ]; then printf %s "$9" > "$TEST_MAP_REVEALED"; else exec /usr/bin/busctl "$@"; fi\n')
            busctl.chmod(0o755)
            revealed = fixture / 'revealed'
            with patch.dict(os.environ, {'PATH': f'{fixture}:{os.environ["PATH"]}',
                                         'TEST_MAP_VOLUME': str(volume), 'TEST_MAP_REVEALED': str(revealed)}):
                case = pages.SettingsPagesTests()
                output = case.run_driver(host, settings_page='general')
            self.assertIn('DRIVER_PASS', output, output[-6000:])
            location = urlsplit(revealed.read_text())
            self.assertEqual((location.scheme, unquote(location.path)), ('file', str(file)))
        storage_log = '\n'.join(line for line in output.splitlines() if any(
            name in line for name in ('StorageConfig.qml', 'StorageExplorer.qml', 'UsageRings.qml')))
        case.assert_clean(storage_log)
        self.assertNotRegex(storage_log, r'Binding loop|recursive rearrange')
