"""A slow GeoClue activation must not hold up the first frame or freeze the shell."""
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time
import unittest
from native_helper import binary

from test_connectivity_pages import BUS_CONFIG, DBUS, QS, SHELL
from test_tray_item_duplicates import isolated_env


DRIVER = '''import QtQuick
import QtQuick.Window
import Quickshell
import qs.services
ShellRoot {
    id: root
    property bool fetch: Quickshell.env("WEATHER_TEST_FETCH") === "1"
    property string status: Weather.status
    property bool firstFrame: false
    Window {
        visible: true; width: 120; height: 40
        onFrameSwapped: if (!root.firstFrame) {
            root.firstFrame = true;
            console.log("WEATHER_FRAME " + Date.now());
        }
    }
    Component.onCompleted: if (fetch) Weather.load()
    Timer {
        running: true; repeat: true; interval: 25
        onTriggered: {
            if (!root.firstFrame) return;
            if (!root.fetch || Weather.place.source === Quickshell.env("WEATHER_TEST_SOURCE")) {
                console.log("WEATHER_DONE " + Weather.place.source, Weather.place.lat, Weather.place.lon);
                Qt.quit();
            }
        }
    }
    Timer { interval: 15000; running: true; onTriggered: Qt.quit() }
}
'''

LOCATION_SERVICE = '''#!/usr/bin/python3
import os
import gi
gi.require_version('Geoclue', '2.0')
from gi.repository import Gio, GLib, Geoclue

bus = Gio.DBusConnection.new_for_address_sync(os.environ['DBUS_STARTER_ADDRESS'],
    Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)
base = '/org/freedesktop/GeoClue2'
client_path, fix_path = base + '/Client/1', base + '/Location/1'
manager = Geoclue.ManagerSkeleton.new()
manager.props.available_accuracy_level = 8
client = Geoclue.ClientSkeleton.new()
client.props.location = '/'
fix = Geoclue.LocationSkeleton.new()
fix.props.latitude, fix.props.longitude = 10.25, 20.75
fix.props.accuracy = 50.0
fix.props.timestamp = GLib.Variant('(tt)', (1000, 0))

def start(obj, call):
    obj.complete_start(call)
    obj.props.active = True
    obj.props.location = fix_path
    obj.emit_location_updated('/', fix_path)
    return True

for method in ('create', 'get'):
    def give(obj, call, method=method):
        getattr(obj, 'complete_' + method + '_client')(call, client_path)
        return True
    manager.connect('handle-' + method + '-client', give)
client.connect('handle-start', start)
for obj, path in ((manager, base + '/Manager'), (client, client_path), (fix, fix_path)):
    obj.export(bus, path)
Gio.bus_own_name_on_connection(bus, 'org.freedesktop.GeoClue2', Gio.BusNameOwnerFlags.NONE, None, None)
loop = GLib.MainLoop()
bus.connect('closed', lambda *args: loop.quit())
loop.run()
'''


@unittest.skipUnless(QS and DBUS, 'requires Quickshell and a private D-Bus')
class WeatherStartupTests(unittest.TestCase):
    def run_shell(self, fetch, *, source='saved'):
        with tempfile.TemporaryDirectory(prefix='velora-weather-') as directory:
            root = Path(directory)
            env = isolated_env(root)
            (root / 'runtime').chmod(0o700)
            env.update(WEATHER_TEST_FETCH=str(int(fetch)), WEATHER_TEST_SOURCE=source, QSG_RENDER_LOOP='basic')
            shell = root / 'shell'
            shell.mkdir()
            for name in ('services', 'modules', 'scripts', 'GlobalStates.qml'):
                (shell / name).symlink_to(SHELL / name)
            (shell / 'shell.qml').write_text(DRIVER)
            settings = root / 'config/velora'
            settings.mkdir()
            (settings / 'config.json').write_text(json.dumps({'bar': {'weather': {
                'enable': True, 'enableGPS': source != 'city', 'city': 'Test City'
            }}}))
            saved = root / 'state/quickshell/user'
            saved.mkdir(parents=True)
            (saved / 'weather.json').write_text(json.dumps({
                'version': 1, 'lastGps': {'lat': 10, 'lon': 20, 'name': 'Test City', 'time': 1},
                'geocoded': {'query': 'Test City', 'lat': 30, 'lon': 40, 'name': 'Test City'}
            }))

            # The private bus will wait for this unresponsive service. Record every activation.
            services = root / 'bus-services'
            services.mkdir()
            marker = root / 'activations'
            backend = root / 'slow-service'
            backend.write_text(LOCATION_SERVICE if source == 'gps' else
                               f'#!/bin/sh\necho attempt >> "{marker}"\nsleep 3\ndate +%s%3N >> "{marker}"\nexit 1\n')
            backend.chmod(0o755)
            (services / 'org.freedesktop.GeoClue2.service').write_text(
                f'[D-BUS Service]\nName=org.freedesktop.GeoClue2\nExec={backend}\n')
            config = root / 'bus.conf'
            config.write_text(BUS_CONFIG.replace('</busconfig>', f'<servicedir>{services}</servicedir></busconfig>'))
            tools = root / 'bin'
            tools.mkdir()
            (tools / 'curl').symlink_to(shutil.which('false'))
            env['VELORA_HELPER'] = binary()
            env['PATH'] = f"{tools}:{env['PATH']}"
            with subprocess.Popen([DBUS, f'--config-file={config}', '--nofork', '--print-address'],
                                  stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True) as bus:
                try:
                    address = bus.stdout.readline().strip()
                    env.update(DBUS_SESSION_BUS_ADDRESS=address, DBUS_SYSTEM_BUS_ADDRESS=address)
                    started = time.time_ns() // 1_000_000
                    result = subprocess.run([QS, '-p', str(shell / 'shell.qml'), '--no-color', '--log-times'],
                                            env=env, capture_output=True, text=True, timeout=20)
                finally:
                    bus.terminate()
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('WEATHER_DONE', output, output)
            events = marker.read_text().splitlines() if marker.exists() else []
            frame = int(re.search(r'WEATHER_FRAME (\d+)', output)[1])
            print(f'Weather first frame ({source if fetch else "cache reader"}): {frame - started} ms')
            return events, frame, output

    def test_cache_reader_never_activates_location(self):
        activated, _, _ = self.run_shell(False)
        self.assertFalse(activated, 'just displaying weather started the location service')

    def test_first_frame_precedes_stalled_gps_and_falls_back_to_saved_location(self):
        events, frame, output = self.run_shell(True)
        first_reply = next(int(event) for event in events if event.isdigit())
        self.assertLess(frame, first_reply, output)
        self.assertIn('WEATHER_DONE saved', output)

    def test_valid_worker_result_is_used(self):
        if subprocess.run(['/usr/bin/python3', '-I', '-c', 'import gi; gi.require_version("Geoclue", "2.0")'],
                          capture_output=True).returncode:
            self.skipTest('requires the GeoClue GI bindings')
        _, _, output = self.run_shell(True, source='gps')
        self.assertIn('WEATHER_DONE gps 10.25 20.75', output)

    def test_manual_city_does_not_request_gps(self):
        events, _, output = self.run_shell(True, source='city')
        self.assertFalse(events)
        self.assertIn('WEATHER_DONE city', output)
