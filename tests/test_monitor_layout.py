"""Presence reaction: the shell owns it, and the safe built-in really reaches the files.

The production service runs inside Quickshell against a private config directory, driven by
synthetic hyprctl data. Nothing here touches the live desktop configuration.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[1]
SHELL = PROJECT / 'dots/.config/quickshell/ii'
SERVICE = SHELL / 'services/HyprlandMonitors.qml'
QUICKSHELL = shutil.which('quickshell')

# Hyprland reports an enabled output in scaled pixels and a disabled one in mode pixels.
LAPTOP_ENABLED = {"name": "eDP-1", "disabled": False, "width": 1512, "height": 1008,
                  "x": 0, "y": 1440, "scale": 1.6666666, "transform": 0, "refreshRate": 60.0,
                  "availableModes": ["2520x1680@120.00Hz", "2520x1680@60.00Hz"]}
LAPTOP_DISABLED = {"name": "eDP-1", "disabled": True, "width": 2520, "height": 1680,
                   "x": 535, "y": 1440, "scale": 1.6666666, "transform": 0, "refreshRate": 60.0,
                   "availableModes": ["2520x1680@120.00Hz", "2520x1680@60.00Hz"]}
# What Hyprland keeps in the list after the cable is pulled: still there, switched off.
EXTERNAL_UNPLUGGED = {**{"name": "HDMI-A-1", "disabled": True, "width": 2560, "height": 1440,
                         "x": 0, "y": 0, "scale": 1, "transform": 0, "refreshRate": 59.951,
                         "availableModes": ["2560x1440@59.95Hz"]}}
EXTERNAL = {"name": "HDMI-A-1", "disabled": False, "width": 2560, "height": 1440,
            "x": 0, "y": 0, "scale": 1, "transform": 0, "refreshRate": 59.951,
            "availableModes": ["2560x1440@59.95Hz", "1920x1080@60.00Hz"]}
# What Hyprland creates when no real output is enabled: a virtual screen, not a display.
FALLBACK = {"name": "FALLBACK", "disabled": False, "width": 1920, "height": 1080,
            "x": 0, "y": 0, "scale": 1, "transform": 0, "refreshRate": 60.0,
            "availableModes": ["1920x1080@60.00Hz"]}
EXTERNAL_ROTATED = {"name": "DP-1", "disabled": False, "width": 810, "height": 1440,
                    "x": 0, "y": 0, "scale": 2, "transform": 1, "refreshRate": 59.951,
                    "availableModes": ["2560x1440@59.95Hz"]}
EXTERNAL_INTENT = {"mode": "2560x1440@59.95", "position": "0x0", "scale": 1, "transform": 0,
                   "disabled": False}
LAPTOP_INTENT = {"mode": "2520x1680@60.00", "position": "535x1440", "scale": 1.666667,
                 "transform": 0, "disabled": True}

REACTION_QML = """import QtQuick
import Quickshell
import qs.services
ShellRoot {
 id: scene
 readonly property var data: __DATA__
 readonly property var svc: HyprlandMonitors
 property int index: 0
 function fail(code, label) { console.error("TEST " + label); Qt.exit(code); }
 function step() {
  if (index >= data.phases.length) { Qt.quit(); return; }
  svc.monitors = data.phases[index];
  svc.syncFallback();
  index++;
  nextTimer.restart();
 }
 Timer { running: true; interval: 250; onTriggered: {
  svc.watch();                       // the shell owns the reaction
  scene.svc.ready = true;
  svc.overrides = data.overrides;
  step();
 } }
 Timer { id: nextTimer; interval: 600; onTriggered: scene.step() }
}
"""


def isolated_env(root):
    env = {**os.environ, 'QT_QPA_PLATFORM': 'offscreen', 'QT_QUICK_BACKEND': 'software',
           'QT_QPA_PLATFORMTHEME': 'generic', 'QT_LOGGING_TO_CONSOLE': '1',
           'QT_LOGGING_RULES': '*.warning=true;*.critical=true'}
    for variable, directory in (('HOME', 'home'), ('XDG_CONFIG_HOME', 'config-xdg'),
                                ('XDG_CACHE_HOME', 'cache'), ('XDG_STATE_HOME', 'xdg-state'),
                                ('XDG_DATA_HOME', 'data'), ('XDG_RUNTIME_DIR', 'runtime')):
        path = root / directory
        path.mkdir(mode=0o700, exist_ok=True)
        env[variable] = str(path)
    env.pop('WAYLAND_DISPLAY', None)
    env.pop('DISPLAY', None)
    env['DBUS_SESSION_BUS_ADDRESS'] = 'unix:path=' + str(root / 'absent-bus')
    return env


def write(root, name, text):
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def build_harness(root, intent):
    config = root / 'config'
    (config / 'hypr/custom').mkdir(parents=True)
    (config / 'hypr/custom/monitors.json').write_text(json.dumps(intent, indent=4) + '\n')
    (config / 'hypr/custom/monitors.lua').write_text('')
    (root / 'services').mkdir(exist_ok=True)
    shutil.copy2(SERVICE, root / 'services/HyprlandMonitors.qml')
    write(root, 'modules/common/qmldir', 'module qs.modules.common\nsingleton Config 1.0 Config.qml\n'
          'singleton Directories 1.0 Directories.qml\n')
    write(root, 'modules/common/Config.qml', 'pragma Singleton\nimport QtQuick\n'
          'QtObject { property bool ready: true; property var options: ({}) }\n')
    write(root, 'modules/common/Directories.qml', 'pragma Singleton\nimport QtQuick\nQtObject { property string config: '
          + json.dumps('file://' + str(config)) + ' }\n')
    write(root, 'modules/common/functions/qmldir', 'module qs.modules.common.functions\n'
          'singleton FileUtils 1.0 FileUtils.qml\nsingleton HyprlandSettings 1.0 HyprlandSettings.qml\n')
    write(root, 'modules/common/functions/FileUtils.qml', 'pragma Singleton\nimport QtQuick\n'
          'QtObject { function trimFileProtocol(s) { return String(s).replace("file://", ""); } }\n')
    write(root, 'modules/common/functions/HyprlandSettings.qml', 'pragma Singleton\nimport QtQuick\n'
          'QtObject { property var reloadCommand: ["/bin/true"] }\n')
    write(root, 'services/qmldir', 'module qs.services\nsingleton HyprlandMonitors 1.0 HyprlandMonitors.qml\n')


class MonitorLayoutTests(unittest.TestCase):
    def run_reaction(self, phases, intent):
        with tempfile.TemporaryDirectory(prefix='velora-monitor-reaction-') as name:
            root = Path(name)
            build_harness(root, intent)
            fixture = json.dumps({'phases': phases, 'overrides': intent})
            write(root, 'shell.qml', REACTION_QML.replace('__DATA__', fixture))
            result = subprocess.run([QUICKSHELL, '-p', str(root / 'shell.qml')], env=isolated_env(root),
                                    capture_output=True, text=True, timeout=25)
            output = result.stdout + result.stderr
            self.assertNotIn('TEST ', output, output)
            self.assertEqual(result.returncode, 0, output)
            for noise in ('TypeError', 'ReferenceError'):
                self.assertNotIn(noise, output, output)
            lua = (root / 'config/hypr/custom/monitors.lua').read_text()
            saved = json.loads((root / 'config/hypr/custom/monitors.json').read_text())
            return lua, saved

    def test_shell_owns_the_presence_reaction(self):
        shell = (SHELL / 'shell.qml').read_text()
        self.assertIn('HyprlandMonitors.watch()', shell)
        owners = [str(path.relative_to(SHELL)) for path in SHELL.rglob('*.qml')
                  if 'HyprlandMonitors.watch()' in path.read_text()]
        self.assertEqual(owners, ['shell.qml'])
        service = SERVICE.read_text()
        self.assertIn('function syncFallback() {', service)
        self.assertIn('if (!root.watching || root.fallbackActive === root.fallbackWritten) return;', service)
        # Hyprland's virtual output must not be mistaken for a lit screen.
        self.assertIn('readonly property var displays: monitors.filter(monitor => monitor.name !== root.virtualOutput)', service)
        self.assertIn('root.monitors = JSON.parse(monitorsCollector.text);', service)
        self.assertIn('readonly property var litOutputs: root.displays.filter(monitor => !monitor.disabled)', service)
        self.assertIn('return root.displays.find(monitor => monitor.name === name) ?? null;', service)
        self.assertIn('readonly property bool nothingLit: root.ready && litWanted.length === 0', service)
        self.assertIn('root.syncFallback();', service.split('stdout: StdioCollector')[1][:600])

    def test_settings_page_uses_the_effective_state(self):
        page = (SHELL / 'modules/settings/DisplaysConfig.qml').read_text()
        self.assertNotIn('HyprlandMonitors.spec(', page)
        self.assertIn('HyprlandMonitors.effectiveSpec(', page)
        self.assertIn('boxes.length > 0 ? Math.min(...boxes.map(b => b.x)) : 0', page)
        self.assertIn('const tolerance = Math.max(12, 12 / arrangement.zoom);', page)
        self.assertIn('overlapsAny', page)

    def test_hotplug_guards_exist(self):
        corners = (SHELL / 'modules/ii/screenCorners/ScreenCorners.qml').read_text()
        self.assertIn('readonly property bool tracked: monitor !== null', corners)
        self.assertIn(': tracked\n                ? Hyprland.workspaces.values.filter', corners)
        background = (SHELL / 'modules/ii/background/Background.qml').read_text()
        self.assertIn('bgRoot.monitor?.activeWorkspace?.id', background)
        self.assertNotIn('(bgRoot.monitor.activeWorkspace?.id ?? 1)', background)

    def test_service_reads_the_real_monitor_sizes(self):
        source = SERVICE.read_text()
        self.assertIn('mode: root.modeText(monitor)', source)
        self.assertNotIn('mode: `${monitor.width}x${monitor.height}@', source)
        self.assertIn('const factor = monitor.disabled ? 1 : scale;', source)

    def test_the_fallback_is_documented(self):
        docs = (PROJECT / 'docs/monitors.md').read_text()
        for phrase in ('preferred', '0x0', 'placeholder', 'monitors.json', 'shell'):
            self.assertIn(phrase, docs)

    @unittest.skipUnless(QUICKSHELL, 'Quickshell is not installed')
    def test_geometry_and_modes_with_real_runtime_data(self):
        with tempfile.TemporaryDirectory(prefix='velora-monitors-') as name:
            root = Path(name)
            build_harness(root, {'eDP-1': LAPTOP_INTENT})
            fixture = json.dumps({'enabled': LAPTOP_ENABLED, 'disabled': LAPTOP_DISABLED,
                                  'external': EXTERNAL, 'rotated': EXTERNAL_ROTATED,
                                  'fallback': FALLBACK,
                                  'overrides': {'eDP-1': LAPTOP_INTENT}})
            write(root, 'shell.qml', '''import QtQuick
import Quickshell
import qs.services
ShellRoot {
 readonly property var data: ''' + fixture + '''
 function fail(code, label) { console.error("TEST " + label); Qt.exit(code); }
 Timer { running: true; interval: 300; onTriggered: {
  const monitors = HyprlandMonitors;
  monitors.ready = true;
  monitors.overrides = {};
  // An enabled scaled output reports its logical size; the mode has to come back as the panel.
  monitors.monitors = [data.enabled];
  const spec = monitors.spec(data.enabled);
  if (spec.mode !== "2520x1680@60.00") fail(2, "mode " + spec.mode);
  const size = monitors.logicalSize(spec);
  if (size.width !== 1512 || size.height !== 1008) fail(3, "logical " + JSON.stringify(size));
  // A rotated 2x output keeps its own mode as well.
  monitors.monitors = [data.rotated];
  if (monitors.spec(data.rotated).mode !== "2560x1440@59.95") fail(4, "rotated " + monitors.spec(data.rotated).mode);
  // Nothing lit: the built-in is the fallback, and the intent stays untouched.
  monitors.overrides = data.overrides;
  monitors.monitors = [data.disabled, data.fallback];   // Hyprland's virtual output is present
  if (!monitors.fallbackActive) fail(5, "fallback inactive");
  if (monitors.monitorByName("FALLBACK") !== null) fail(12, "virtual output leaked into the list");
  const safe = monitors.effectiveSpec(data.disabled);
  if (safe.disabled !== false || safe.mode !== "preferred" || safe.position !== "0x0"
      || Math.abs(safe.scale - 1.666667) > 0.0001) fail(6, "safe " + JSON.stringify(safe));
  if (monitors.buildLua().includes('disabled = true')) fail(7, "lua still disables the panel");
  // The external is back and enabled by the intent: the saved layout rules again.
  monitors.monitors = [data.disabled, data.external];
  monitors.overrides = Object.assign({}, data.overrides, { "HDMI-A-1": EXTERNAL_INTENT_JSON });
  if (monitors.fallbackActive) fail(9, "fallback stuck on");
  if (monitors.effectiveSpec(data.disabled).disabled !== true) fail(10, "laptop turned on against the intent");
  const intentLua = monitors.buildLua();
  if (!intentLua.includes('output = "HDMI-A-1"') || !intentLua.includes('disabled = true'))
   fail(11, "intent lua " + intentLua);
  Qt.quit();
 } }
}'''.replace('EXTERNAL_INTENT_JSON', json.dumps(EXTERNAL_INTENT)))
            result = subprocess.run([QUICKSHELL, '-p', str(root / 'shell.qml')], env=isolated_env(root),
                                    capture_output=True, text=True, timeout=25)
            output = result.stdout + result.stderr
            self.assertNotIn('TEST ', output, output)
            self.assertEqual(result.returncode, 0, output)
            for noise in ('TypeError', 'ReferenceError'):
                self.assertNotIn(noise, output, output)

    @unittest.skipUnless(QUICKSHELL, 'Quickshell is not installed')
    def test_unplugging_the_only_lit_screen_writes_the_safe_config(self):
        # The cable is out: the external is still listed but off, Hyprland lights a virtual
        # output, and the saved intent still says the external should be on.
        lua, saved = self.run_reaction([[LAPTOP_DISABLED, EXTERNAL_UNPLUGGED, FALLBACK]],
                                       {'eDP-1': LAPTOP_INTENT, 'HDMI-A-1': EXTERNAL_INTENT})
        self.assertIn('output = "eDP-1"', lua)
        self.assertIn('mode = "preferred"', lua)
        self.assertIn('position = "0x0"', lua)
        self.assertNotIn('disabled = true', lua)
        # The user's choice is untouched: only the generated lua carries the fallback.
        self.assertEqual(saved, {'eDP-1': LAPTOP_INTENT, 'HDMI-A-1': EXTERNAL_INTENT})

    @unittest.skipUnless(QUICKSHELL, 'Quickshell is not installed')
    def test_plugging_the_external_back_restores_the_saved_layout(self):
        intent = {'eDP-1': LAPTOP_INTENT, 'HDMI-A-1': EXTERNAL_INTENT}
        # First nothing is lit (the fallback is written), then the external comes back.
        lua, saved = self.run_reaction([[LAPTOP_DISABLED, EXTERNAL_UNPLUGGED, FALLBACK],
                                        [LAPTOP_DISABLED, EXTERNAL]], intent)
        self.assertIn('output = "HDMI-A-1"', lua)
        self.assertIn('mode = "2560x1440@59.95"', lua)
        self.assertIn('disabled = true', lua)          # the laptop goes back off, as chosen
        self.assertNotIn('mode = "preferred"', lua)
        self.assertEqual(saved, intent)


if __name__ == '__main__':
    unittest.main()
