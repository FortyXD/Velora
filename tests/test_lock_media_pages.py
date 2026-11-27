"""Exercise the lock backdrop and status indicator in a private Quickshell window."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import test_connectivity_pages as pages


DRIVER = r'''
import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.ii.lock
import qs.modules.ii.bar.widgets

ShellRoot {
    id: root
    property int ticks: 0
    property int firstFrame: -1
    property bool animated: false
    property var sink: null
    property int videoFrames: 0
    property bool updateSeen: false
    property bool updateCleared: false
    FloatingWindow {
        visible: true; implicitWidth: 280; implicitHeight: 160
        LockBackdrop { id: backdrop; anchors.fill: parent; playVideo: true }
        VeloraUpdateDot { id: dot }
    }
    function find(item, matches) {
        if (matches(item)) return item;
        for (const child of item.children ?? []) {
            const found = find(child, matches);
            if (found) return found;
        }
        return null;
    }
    Connections {
        target: root.sink
        ignoreUnknownSignals: true
        function onVideoFrameChanged() { root.videoFrames++; }
    }
    Process {
        id: publishUpdate
        property bool available: true
        command: ["python3", "-c",
            "import json, os, pathlib, sys; folder = pathlib.Path(os.environ['XDG_STATE_HOME']) / 'velora'; folder.mkdir(parents=True, exist_ok=True); tmp = folder / 'test-update'; tmp.write_text(json.dumps({'available': sys.argv[1] == 'yes'})); tmp.replace(folder / 'update.json')",
            available ? "yes" : "no"]
    }
    Timer {
        interval: 50; repeat: true; running: true
        onTriggered: {
            if (!Config.ready) return;
            if (++root.ticks === 24) {
                Config.options.powerSaving.override = "off";
                Config.options.lock.animatedWallpaper = true;
                Config.options.lock.backgroundPath = GIF_PATH;
                publishUpdate.running = true;
            }
            if (!root.animated) {
                const image = root.find(backdrop, item => item.playing !== undefined && item.frameCount === 2);
                if (image) {
                    if (root.firstFrame < 0) root.firstFrame = image.currentFrame;
                    if (image.currentFrame !== root.firstFrame) {
                        root.animated = true;
                        Config.options.lock.backgroundPath = VIDEO_PATH;
                    }
                }
            } else if (!root.sink) {
                root.sink = root.find(backdrop, item => !!item.videoSink)?.videoSink ?? null;
            }
            if (dot.visible && !root.updateSeen && root.ticks > 24) {
                root.updateSeen = true;
                publishUpdate.available = false;
                publishUpdate.running = true;
            } else if (root.updateSeen && !dot.visible) root.updateCleared = true;
            if (root.animated && root.videoFrames > 12 && root.updateCleared) {
                console.log("DRIVER_PASS"); Qt.quit();
            } else if (root.ticks > 400) {
                console.log("DRIVER_FAIL", root.animated, root.videoFrames, root.updateSeen, root.updateCleared);
                Qt.quit();
            }
        }
    }
}
'''


@unittest.skipUnless((pages.QS and pages.CARGO and pages.DBUS and shutil.which("ffmpeg")) or pages.REQUIRED,
                     "needs Quickshell, D-Bus, cargo and FFmpeg")
class LockMediaPagesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        pages.SettingsPagesTests.setUpClass()

    def test_animated_files_and_first_update(self):
        from PIL import Image

        with tempfile.TemporaryDirectory() as directory:
            gif = Path(directory) / "Два кадра # 100%.GIF"
            video = Path(directory) / "Сцена # 2.mp4"
            Image.new("RGB", (32, 32), "red").save(
                gif, save_all=True, append_images=[Image.new("RGB", (32, 32), "blue")],
                duration=100, loop=0)
            subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-f", "lavfi", "-i",
                            "testsrc2=s=96x64:r=12", "-t", "0.6", "-c:v", "mpeg4",
                            "-threads", "1", str(video)], check=True, timeout=10)
            driver = DRIVER.replace("GIF_PATH", json.dumps(str(gif))).replace("VIDEO_PATH", json.dumps(str(video)))
            case = pages.SettingsPagesTests()
            output = case.run_driver(driver)
        self.assertIn("DRIVER_PASS", output, output[-6000:])
        case.assert_clean(output)
