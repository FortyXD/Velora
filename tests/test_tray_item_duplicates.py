"""Tray slots must survive an app re-registering its StatusNotifierItem.

An app registers its tray item under a D-Bus name and re-registers it under a fresh name
whenever the tray watcher or host changes - a shell reload, or a second watcher taking
over. Quickshell keys its items by that name and keeps the registrations whose name has
since vanished, so Telegram can occupy nine slots after eight reloads, eight of them
frozen at the icon they were registered with.

The rule lives in UniqueTrayItems and is checked three ways: as pure logic in the real
Quickshell runtime, against a real SystemTray backend fed with nine fake registrations on
a private session bus, and as wiring, since any surface that reads the raw registrations
would show the stale slots again. Nothing here reaches this machine's compositor or bus.
"""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time
import unittest

PROJECT = Path(__file__).resolve().parents[1]
SHELL = PROJECT / 'dots/.config/quickshell/ii'
HELPER = SHELL / 'modules/common/functions/UniqueTrayItems.qml'
QUICKSHELL = shutil.which('qs') or shutil.which('quickshell')
DBUS_DAEMON = shutil.which('dbus-daemon')
try:
    import dbus  # noqa: F401  (only needed for the private-bus test)
    HAS_DBUS = True
except ImportError:
    HAS_DBUS = False

# One connection per registration: that is how Telegram's stale items look to the host,
# each under its own unique name, all reporting the same Id.
FAKE_TRAY_APP = '''import sys, time
import dbus, dbus.service, dbus.mainloop.glib
from gi.repository import GLib
dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
count = int(sys.argv[1])
session = dbus.SessionBus()
for _ in range(400):
    if session.get_object('org.freedesktop.DBus', '/org/freedesktop/DBus').NameHasOwner(
            'org.kde.StatusNotifierWatcher', dbus_interface='org.freedesktop.DBus'):
        break
    time.sleep(0.05)
else:
    print('NO_WATCHER', file=sys.stderr)
    sys.exit(5)
kept = []
for n in range(count):
    bus = dbus.SessionBus(private=True)
    props = {
        'Id': dbus.String('TelegramDesktop'),
        'Title': dbus.String('Telegram'),
        'Status': dbus.String('Active'),
        'Category': dbus.String('ApplicationStatus'),
        'IconName': dbus.String('telegram'),
        'ItemIsMenu': dbus.Boolean(False),
        'IconPixmap': dbus.Array([], signature='(iiay)'),
    }
    class Item(dbus.service.Object):
        @dbus.service.method('org.freedesktop.DBus.Properties', in_signature='ss', out_signature='v')
        def Get(self, interface, prop): return props.get(prop, dbus.String(''))
        @dbus.service.method('org.freedesktop.DBus.Properties', in_signature='s', out_signature='a{sv}')
        def GetAll(self, interface): return props
        @dbus.service.signal('org.freedesktop.DBus.Properties', signature='sa{sv}as')
        def PropertiesChanged(self, interface, changed, invalidated): pass
        @dbus.service.method('org.kde.StatusNotifierItem', in_signature='ii', out_signature='')
        def Activate(self, x, y): pass
        @dbus.service.method('org.kde.StatusNotifierItem', in_signature='ii', out_signature='')
        def SecondaryActivate(self, x, y): pass
        @dbus.service.method('org.kde.StatusNotifierItem', in_signature='ii', out_signature='')
        def ContextMenu(self, x, y): pass
        @dbus.service.method('org.kde.StatusNotifierItem', in_signature='is', out_signature='')
        def Scroll(self, delta, orientation): pass
    item = Item(bus, '/StatusNotifierItem')
    bus.get_object('org.kde.StatusNotifierWatcher', '/StatusNotifierWatcher').RegisterStatusNotifierItem(
        dbus.String(bus.get_unique_name()), dbus_interface='org.kde.StatusNotifierWatcher')
    kept.append((bus, item))
GLib.MainLoop().run()
'''


def isolated_env(root, bus=None):
    """A Quickshell run that cannot reach this machine's compositor or session bus."""
    env = {key: value for key, value in os.environ.items()
           if key not in ('HYPRLAND_INSTANCE_SIGNATURE', 'WAYLAND_DISPLAY', 'DISPLAY', 'XDG_SESSION_ID')}
    for variable, directory in (('HOME', 'home'), ('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache'),
                                ('XDG_STATE_HOME', 'state'), ('XDG_DATA_HOME', 'data'),
                                ('XDG_RUNTIME_DIR', 'runtime')):
        path = root / directory
        path.mkdir(parents=True, exist_ok=True)
        env[variable] = str(path)
    env.update(DBUS_SESSION_BUS_ADDRESS=bus or 'unix:path=/nonexistent', QT_QPA_PLATFORM='offscreen',
               QT_QUICK_BACKEND='software', QT_QPA_PLATFORMTHEME='generic')
    return env


def import_production_service(root):
    """Expose the real UniqueTrayItems and TrayService as qs.* modules inside `root`."""
    functions = root / 'modules/common/functions'
    functions.mkdir(parents=True, exist_ok=True)
    shutil.copy2(HELPER, functions / 'UniqueTrayItems.qml')
    (functions / 'qmldir').write_text('module qs.modules.common.functions\n'
                                      'singleton UniqueTrayItems 1.0 UniqueTrayItems.qml\n')
    common = root / 'modules/common'
    (common / 'qmldir').write_text('module qs.modules.common\n')
    return functions


def run_shell(root, body):
    (root / 'shell.qml').write_text('import QtQuick\nimport Quickshell\nimport qs.modules.common.functions\n'
                                    'ShellRoot {\n' + body + '\n}')
    result = subprocess.run([QUICKSHELL, '-p', str(root / 'shell.qml'), '--no-color'],
                            env=isolated_env(root), capture_output=True, text=True, timeout=20)
    output = result.stdout + result.stderr
    assert 'DEDUP_FAIL' not in output, output
    for noise in ('TypeError', 'ReferenceError'):
        assert noise not in output, output
    return result, output


class UniqueTrayItemRuleTests(unittest.TestCase):
    @unittest.skipUnless(QUICKSHELL, 'Quickshell is not installed')
    def test_repeated_registrations_collapse_to_the_newest(self):
        with tempfile.TemporaryDirectory(prefix='velora-tray-dedup-') as directory:
            root = Path(directory)
            import_production_service(root)
            result, output = run_shell(root, '''Timer { running: true; repeat: false; onTriggered: {
  // Eight stale registrations of one Telegram item, then the live one, plus a bystander.
  // `slot` stands for the D-Bus name: one per registration.
  const registrations = [];
  for (let slot = 0; slot < 8; slot++)
    registrations.push({ id: "TelegramDesktop", title: "Telegram", slot: slot });
  registrations.push({ id: "Fcitx", title: "Fcitx", slot: 8 });
  registrations.push({ id: "TelegramDesktop", title: "Telegram", slot: 9 });
  const unique = UniqueTrayItems.of(registrations);
  if (unique.length !== 2) { console.error("DEDUP_FAIL slots", unique.length); Qt.exit(2); }
  // First-appearance order is kept so the bar does not reshuffle on every reload, and the
  // newest registration wins because it is the one that keeps updating its icon.
  if (unique[0].id !== "Fcitx" || unique[1].id !== "TelegramDesktop") { console.error("DEDUP_FAIL order"); Qt.exit(3); }
  if (unique[1].slot !== 9) { console.error("DEDUP_FAIL newest", unique[1].slot); Qt.exit(4); }
  Qt.quit();
} }''')
            self.assertEqual(result.returncode, 0, output)

    @unittest.skipUnless(QUICKSHELL, 'Quickshell is not installed')
    def test_distinct_items_and_missing_identity_are_untouched(self):
        with tempfile.TemporaryDirectory(prefix='velora-tray-identity-') as directory:
            root = Path(directory)
            import_production_service(root)
            result, output = run_shell(root, '''Timer { running: true; repeat: false; onTriggered: {
  // Different apps stay separate even when they share a title.
  const apps = UniqueTrayItems.of([
    { id: "NextDNS", title: "NextDNS", slot: 0 },
    { id: "gdrive", title: "NextDNS", slot: 1 },
    { id: "paradox", title: "Parallels", slot: 2 }]);
  if (apps.length !== 3) { console.error("DEDUP_FAIL apps", apps.length); Qt.exit(2); }
  // An app that reports no id falls back to its title...
  const titled = UniqueTrayItems.of([
    { id: "", title: "Telegram", slot: 0 }, { id: "", title: "Telegram", slot: 1 }]);
  if (titled.length !== 1 || titled[0].slot !== 1) { console.error("DEDUP_FAIL title", titled.length); Qt.exit(3); }
  // ...and one that reports neither is never folded into somebody else.
  const nameless = UniqueTrayItems.of([
    { id: "", title: "", slot: 0 }, { id: "", title: "", slot: 1 }]);
  if (nameless.length !== 2) { console.error("DEDUP_FAIL nameless", nameless.length); Qt.exit(4); }
  if (UniqueTrayItems.of([]).length !== 0) { console.error("DEDUP_FAIL empty"); Qt.exit(5); }
  Qt.quit();
} }''')
            self.assertEqual(result.returncode, 0, output)


class StaleRegistrationOnRealBackendTests(unittest.TestCase):
    @unittest.skipUnless(QUICKSHELL and DBUS_DAEMON and HAS_DBUS,
                         'Quickshell, dbus-daemon or dbus-python is not installed')
    def test_nine_registrations_of_one_item_take_one_slot(self):
        with tempfile.TemporaryDirectory(prefix='velora-tray-bus-') as directory:
            root = Path(directory)
            services = root / 'services'
            services.mkdir(parents=True)
            shutil.copy2(SHELL / 'services/TrayService.qml', services)
            (services / 'qmldir').write_text('module qs.services\nsingleton TrayService 1.0 TrayService.qml\n')
            common = root / 'modules/common'
            import_production_service(root)
            (common / 'Config.qml').write_text(
                'pragma Singleton\nimport QtQuick\nQtObject { property var options: ('
                '{"tray": {filterPassive: false, pinnedItems: [], invertPinnedItems: true}}) }')
            (common / 'qmldir').write_text('module qs.modules.common\nsingleton Config 1.0 Config.qml\n')
            (root / 'fake.py').write_text(FAKE_TRAY_APP)
            (root / 'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import qs.services
ShellRoot {
    property int polls: 0
    Timer { running: true; interval: 100; repeat: true; onTriggered: {
        const raw = SystemTray.items.values.length;
        const slots = TrayService.pinnedItems.length;
        if (raw < 9) {
            if (++polls > 80) { console.error("BUS_RESULT registrations=" + raw + " slots=" + slots); Qt.exit(3); }
            return;
        }
        console.log("BUS_RESULT registrations=" + raw + " slots=" + slots);
        Qt.exit(0);
    } }
}
''')
            socket = root / 'bus'
            daemon = subprocess.Popen(['dbus-daemon', '--session', '--nofork', f'--address=unix:path={socket}'],
                                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            for _ in range(60):
                if socket.exists():
                    break
                time.sleep(0.1)
            env = isolated_env(root, 'unix:path=' + str(socket))
            with open(root / 'shell.out', 'w') as log:
                shell = subprocess.Popen(['qs', '-p', str(root / 'shell.qml'), '--no-color'], env=env,
                                         stdout=log, stderr=subprocess.STDOUT)
                time.sleep(1.5)  # Quickshell has to own the watcher before the items arrive
                fake = subprocess.Popen(['python3', str(root / 'fake.py'), '9'], env=env,
                                        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
                try:
                    code = shell.wait(timeout=45)
                finally:
                    for process in (shell, fake, daemon):
                        process.terminate()
                    for process in (shell, fake, daemon):
                        try:
                            process.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            process.kill()
                output = (root / 'shell.out').read_text()
                fake_error = (fake.stderr.read() or '')[:300]
                fake.stderr.close()
                match = re.search(r'registrations=(\d+) slots=(\d+)', output)
                self.assertTrue(match, output + fake_error)
                self.assertEqual((int(match.group(1)), int(match.group(2))), (9, 1),
                                 'Quickshell reported 9 registrations of one item; the bar must take one slot')
                self.assertEqual(code, 0, output + fake_error)
                for noise in ('TypeError', 'ReferenceError'):
                    self.assertNotIn(noise, output)


class TrayWiringTests(unittest.TestCase):
    def test_only_the_service_reads_raw_registrations(self):
        readers = sorted(str(path.relative_to(SHELL))
                         for path in SHELL.rglob('*.qml')
                         if 'SystemTray.items' in path.read_text())
        self.assertEqual(readers, ['services/TrayService.qml'],
                         'a tray surface reads raw registrations and will show stale slots again')

    def test_tray_surfaces_use_the_collapsed_list(self):
        service = (SHELL / 'services/TrayService.qml').read_text()
        self.assertIn('UniqueTrayItems.of(SystemTray.items.values)', service)
        self.assertIn('root.items.filter(', service)
        self.assertIn('visible: root.showSeparator && TrayService.items.length > 0',
                      (SHELL / 'modules/ii/bar/SysTray.qml').read_text())
        lock = (SHELL / 'modules/ii/lock/LockUserChip.qml').read_text()
        self.assertIn('pinnedItems: TrayService.items.filter(i => i.id == "Fcitx")', lock)
        self.assertNotIn('import Quickshell.Services.SystemTray', lock)


if __name__ == '__main__':
    unittest.main()
