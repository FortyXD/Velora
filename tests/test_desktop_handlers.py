"""Exercise the file-manager MIME launch and local VPN import on a private desktop bus."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / 'tools/target/debug/velora-helper'


@unittest.skipUnless(all(shutil.which(tool) for tool in ('lua', 'gio', 'xdg-open', 'dbus-run-session')), 'desktop tools required')
class BrowserDownloadTests(unittest.TestCase):
    def test_download_opens_the_registered_application_with_its_local_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            config = home / 'config'
            config.mkdir()
            (config / 'hypr').symlink_to(ROOT / 'dots/.config/hypr', target_is_directory=True)
            apps = home / 'share/applications'
            apps.mkdir(parents=True)
            viewer = home / 'test viewer'
            viewer.write_text('#!/bin/sh\nprintf "%s" "$1" > "$OPENED_FILE"\n')
            viewer.chmod(0o755)
            (apps / 'spreadsheet.desktop').write_text(
                f'[Desktop Entry]\nType=Application\nName=Spreadsheet\nExec="{viewer}" %f\nMimeType=text/csv;\n')
            (config / 'mimeapps.list').write_text('[Default Applications]\ntext/csv=spreadsheet.desktop;\n')
            downloads = home / 'Downloads'
            downloads.mkdir()
            file = downloads / 'цены 100% #1.csv'
            file.write_text('name,price\napple,10\n')
            opened = home / 'opened'
            env = {**os.environ, 'HOME':tmp, 'XDG_CONFIG_HOME':str(config), 'XDG_DATA_HOME':str(apps.parent),
                   'XDG_CURRENT_DESKTOP':'Hyprland', 'PATH':f'{home}/bin:/usr/sbin/:/usr/bin:/bin', 'OPENED_FILE':str(opened), 'MM_NOTTTY':'1'}
            session = config / 'hypr/hyprland/env.lua'
            lua = 'hl = {env = function(k, v) if k == "PATH" then print(v) end end}; dofile(' + json.dumps(str(session)) + ')'
            env['PATH'] = subprocess.check_output(['lua', '-e', lua], env=env, text=True).strip()
            self.assertEqual(env['PATH'].split(':')[:2], [str(home / 'bin'), str(session.parent / 'xdg')])
            self.assertEqual(Path(shutil.which('xdg-open', path=env['PATH'])).resolve(),
                             (session.parent / 'xdg/xdg-open').resolve())
            for target in (str(file), file.as_uri()):
                opened.unlink(missing_ok=True)
                subprocess.run(['dbus-run-session', '--', 'xdg-open', target], env=env, cwd=downloads,
                               check=True, capture_output=True, timeout=10)
                until = time.monotonic() + 3
                while not opened.exists() and time.monotonic() < until:
                    time.sleep(.02)
                self.assertEqual(opened.read_text(), str(file))


@unittest.skipUnless(os.environ.get('VELORA_TEST_PREBUILT') and HELPER.exists(),
                     'requires the private desktop environment in tests/run_isolated.py')
class DesktopHandlersTests(unittest.TestCase):
    def test_video_opens_through_the_registered_mime_handler(self):
        if not all(shutil.which(name) for name in ('ffmpeg', 'mpv', 'gio', 'dbus-run-session')):
            self.skipTest('media and GIO tools are required')
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            bin_dir = home/'bin'
            bin_dir.mkdir()
            log = home/'playback'
            (bin_dir/'mpv').write_text("""#!/bin/sh
/usr/bin/mpv --no-config --vo=null --ao=null --frames=3 --no-idle --keep-open=no -- "$3" > "$PLAYBACK_LOG" 2>&1
""")
            (bin_dir/'mpv').chmod(0o755)
            env = dict(os.environ, HOME=tmp, XDG_CONFIG_HOME=str(home/'config'), XDG_DATA_HOME=str(home/'data'),
                       XDG_CACHE_HOME=str(home/'cache'), XDG_STATE_HOME=str(home/'state'),
                       XDG_CURRENT_DESKTOP='Hyprland', PATH=str(bin_dir)+':/usr/bin', PLAYBACK_LOG=str(log))
            movie = home/'two words.mp4'
            subprocess.run(['ffmpeg', '-loglevel', 'error', '-f', 'lavfi', '-i',
                            'testsrc2=size=64x48:rate=10:duration=0.5', '-c:v', 'libx264', str(movie)],
                           check=True, env=env, timeout=15)
            subprocess.run([HELPER, 'apps', 'sync'], check=True, env=env, capture_output=True, timeout=45)
            defaults = (home/'config/mimeapps.list').read_text()
            self.assertIn('video/mp4=mpv.desktop', defaults)
            subprocess.run(['dbus-run-session', '--', 'gio', 'open', movie.as_uri()],
                           check=True, env=env, capture_output=True, timeout=15)
            until = time.monotonic() + 6
            while time.monotonic() < until and (not log.exists() or 'Exiting...' not in log.read_text()):
                time.sleep(.05)
            self.assertTrue(log.exists(), 'GIO did not launch the video handler')
            self.assertIn('End of file', log.read_text())

    def test_helper_imports_a_profile_into_velora(self):
        with tempfile.TemporaryDirectory() as tmp:
            env = dict(os.environ, XDG_DATA_HOME=tmp, VELORA_SHELL_DIR=str(ROOT/'dots/.config/quickshell/ii'))
            result = subprocess.run([HELPER, 'vpn-import'], input='trojan://fixture@server.test:443#Lab\n',
                                    env=env, text=True, capture_output=True, check=True)
            profile = json.loads(result.stdout)['profiles'][0]
            self.assertEqual(profile['name'], 'Lab')
            self.assertNotIn('fixture', result.stdout)
            self.assertTrue((Path(tmp)/'velora/vpn/profiles.json').is_file())

    def test_server_ping_accepts_dns_and_ipv6_and_reports_latency(self):
        import test_connectivity_pages as pages
        if not pages.QS:
            self.skipTest('Quickshell is required')
        pages.SettingsPagesTests.setUpClass()
        driver = '''import QtQuick
import Quickshell
import qs.modules.settings.network
ShellRoot {
    FloatingWindow {
        visible: true; implicitWidth: 450; implicitHeight: 160
        VpnServerPing {
            id: ping; width: 430; suggestedHost: "127.0.0.1"
            onResultChanged: if (result.length) {
                console.log(/^[<]?[0-9.]+ ms$/.test(result) ? "DRIVER_PASS" : "CHECK_FAIL " + result);
                Qt.quit();
            }
        }
    }
    Timer {
        running: true; interval: 150
        onTriggered: {
            if (ping.pingHost("example.test:443") !== "example.test" || ping.pingHost("[2001:db8::1]:443") !== "2001:db8::1"
                || ping.pingHost("--help") !== "" || ping.pingHost("two hosts") !== "") { console.log("CHECK_FAIL address"); Qt.quit(); }
            else ping.start();
        }
    }
    Timer { running: true; interval: 8000; onTriggered: { console.log("CHECK_FAIL no ping result"); Qt.quit(); } }
 }'''
        # User namespaces deny raw ICMP. Exercise the real argv and output parser with an iputils reply.
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as tmp:
            ping = Path(tmp)/'ping'
            ping.write_text("#!/bin/sh\n[ \"$*\" = '-n -c 1 -W 2 -w 3 -- 127.0.0.1' ] || exit 2\n"
                            "echo '64 bytes from 127.0.0.1: icmp_seq=1 ttl=64 time=0.027 ms'\n")
            ping.chmod(0o755)
            with patch.dict(os.environ, PATH=tmp+':'+os.environ['PATH']):
                output = pages.SettingsPagesTests().run_driver(driver)
        self.assertIn('DRIVER_PASS', output, output[-4000:])

    def test_proxy_vpn_management_in_settings(self):
        import test_connectivity_pages as pages
        if not pages.QS:
            self.skipTest('Quickshell is required')
        pages.SettingsPagesTests.setUpClass()
        driver = '''import QtQuick
import Quickshell
import qs.modules.settings.network
ShellRoot {
    id: root
    property int step: 0
    function find(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children ?? []) {
            const result = find(child, name);
            if (result) return result;
        }
        return null;
    }
    FloatingWindow {
        visible: true; implicitWidth: 650; implicitHeight: 500
        ProxyVpnSection { id: section; width: 620 }
    }
    Timer {
        running: true; repeat: true; interval: 80
        onTriggered: {
            if (!section.loaded || section.busy || section.action) return;
            const field = root.find(section, "proxyVpnLink");
            if (root.step === 0) {
                field.text = "trojan://test-key@127.0.0.1:443#Local";
                root.step++; section.importLink();
            } else if (root.step === 1 && section.profiles.length === 1) {
                if (field.text !== "" || section.profiles[0].name !== "Local") {
                    console.log("CHECK_FAIL import"); Qt.quit(); return;
                }
                root.step++; section.run("remove", {id: section.profiles[0].id});
            } else if (root.step === 2 && section.profiles.length === 0) {
                root.step++; field.text = "bad://invalid"; section.importLink();
            } else if (root.step === 3 && section.errorText.length > 0) {
                console.log("DRIVER_PASS"); Qt.quit();
            }
        }
    }
    Timer { running: true; interval: 8000; onTriggered: { console.log("CHECK_FAIL stage " + root.step + " " + section.errorText); Qt.quit(); } }
}'''
        case = pages.SettingsPagesTests()
        output = case.run_driver(driver)
        self.assertIn('DRIVER_PASS', output, output[-4000:])
        case.assert_clean(output)
