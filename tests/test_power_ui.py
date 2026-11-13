"""Small Qt-backed regression suite for the chart and opt-in process lifecycle."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[1]
SHELL = PROJECT / 'dots/.config/quickshell/ii'
QT_TEST = shutil.which('qmltestrunner6') or next((str(p) for p in (
    Path('/usr/lib/qt6/bin/qmltestrunner'), Path('/usr/lib64/qt6/bin/qmltestrunner')) if p.exists()), None)
def isolated_env(root):
    """Keep Qt/Quickshell caches, logs and settings out of the user's profile."""
    env = {**os.environ, 'QT_QPA_PLATFORM': 'offscreen', 'QT_QUICK_BACKEND': 'software',
           'QT_QPA_PLATFORMTHEME': 'generic', 'FONTCONFIG_FILE': '/etc/fonts/fonts.conf',
           'QT_LOGGING_RULES': '*.warning=true;*.critical=true', 'QT_LOGGING_TO_CONSOLE': '1'}
    for variable, directory in (('HOME', 'home'), ('XDG_CONFIG_HOME', 'config'),
                                ('XDG_CACHE_HOME', 'cache'), ('XDG_STATE_HOME', 'xdg-state'),
                                ('XDG_DATA_HOME', 'data'), ('XDG_RUNTIME_DIR', 'runtime')):
        path = root / directory
        path.mkdir(mode=0o700, exist_ok=True)
        env[variable] = str(path)
    # No test component needs the live compositor or user session bus.
    env.pop('WAYLAND_DISPLAY', None)
    env.pop('DISPLAY', None)
    env['DBUS_SESSION_BUS_ADDRESS'] = 'unix:path=' + str(root / 'absent-bus')
    return env


def write(root, name, text):
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


class PowerUiTests(unittest.TestCase):
    def test_opt_in_schema_and_shell_only_owner(self):
        config = (SHELL / 'modules/common/Config.qml').read_text()
        battery = config.split('property JsonObject battery: JsonObject {', 1)[1].split('}', 1)[0]
        self.assertIn('property bool advancedAnalytics: false', battery)
        owners = [str(path.relative_to(SHELL)) for path in SHELL.rglob('*.qml')
                  if 'PowerAnalytics.load()' in path.read_text()]
        self.assertEqual(owners, ['shell.qml'])
        settings = (SHELL / 'modules/settings/BatteryConfig.qml').read_text()
        self.assertIn('PowerAnalyticsPanel {', settings)
        self.assertIn('pageActive: page.pageShown', settings)
        self.assertIn('!PowerAnalytics.hasLivePower ? "—"', settings)
        popup = (SHELL / 'modules/ii/bar/BatteryPopup.qml').read_text()
        self.assertIn('if (!Battery.energyRateAvailable) return "—";', popup)

    def test_example_config_ships_the_analytics_default(self):
        example = json.loads((PROJECT / 'dots/.config/illogical-impulse/config.example.json').read_text())
        self.assertIs(example['battery']['advancedAnalytics'], False)

    def test_every_power_analytics_string_is_translated_to_russian(self):
        russian = json.loads((SHELL / 'translations/ru_RU.json').read_text())
        files = [*(SHELL / 'modules/settings/power').rglob('*.qml'),
                 SHELL / 'services/PowerAnalytics.qml', SHELL / 'modules/settings/BatteryConfig.qml']
        missing = sorted({match for path in files
                          for match in re.findall(r'Translation\.tr\("((?:[^"\\]|\\.)*)"', path.read_text())
                          if match not in russian})
        self.assertEqual(missing, [], 'Add these to translations/ru_RU.json')

    @unittest.skipUnless(QT_TEST, 'Qt 6 Quick Test unavailable')
    def test_chart_math_transitions_and_actual_paint(self):
        with tempfile.TemporaryDirectory(prefix='velora-power-chart-') as name:
            root = Path(name)
            for file in ('PowerHistoryChart.qml', 'ChartMath.js'):
                shutil.copy2(SHELL / 'modules/settings/power' / file, root)
            shutil.copy2(PROJECT / 'tests/qml/tst_powerchart.qml', root)
            write(root, 'qs/modules/common/qmldir', 'module qs.modules.common\nsingleton Appearance 1.0 Appearance.qml\n')
            write(root, 'qs/modules/common/Appearance.qml', '''pragma Singleton
import QtQuick
QtObject {
 property var colors: ({colPrimary: "#89b4fa", colSubtext: "#777777", colSecondaryContainer: "#34344a", colOnSecondaryContainer: "#ffffff"})
 property var font: ({pixelSize: {smaller: 12, small: 14}, family: {main: "Sans Serif"}})
 property var rounding: ({small: 8})
 property var animation: ({elementMoveFast: {duration: 120, type: Easing.OutCubic, bezierCurve: [0,0,1,1,1,1]}})
}''')
            write(root, 'qs/modules/common/widgets/qmldir', 'module qs.modules.common.widgets\nStyledText 1.0 StyledText.qml\n')
            write(root, 'qs/modules/common/widgets/StyledText.qml', 'import QtQuick\nText {}\n')
            write(root, 'qs/services/qmldir', 'module qs.services\nsingleton Translation 1.0 Translation.qml\n')
            write(root, 'qs/services/Translation.qml', 'pragma Singleton\nimport QtQuick\nQtObject { function tr(value) { return value; } }\n')
            result = subprocess.run([QT_TEST, '-import', str(root), '-input', str(root), '-o', '-,txt'],
                                    env=isolated_env(root), text=True, capture_output=True, timeout=20)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotIn('ReferenceError', result.stdout + result.stderr)
            self.assertNotIn('TypeError', result.stdout + result.stderr)

    @unittest.skipUnless(shutil.which('quickshell'), 'Quickshell unavailable')
    def test_real_service_opt_in_cleanup_and_settings_reader(self):
        with tempfile.TemporaryDirectory(prefix='velora-power-service-') as name:
            root = Path(name)
            write(root, 'modules/common/qmldir', 'module qs.modules.common\nsingleton Config 1.0 Config.qml\nsingleton Directories 1.0 Directories.qml\n')
            write(root, 'modules/common/Config.qml', '''pragma Singleton
import QtQuick
QtObject {
 property bool ready: true
 property QtObject options: QtObject {
  property QtObject battery: QtObject {
   property bool advancedAnalytics: false
   property bool automaticSuspend: false
   property int low: 20
   property int critical: 5
   property int full: 101
   property int suspend: 3
  }
  property QtObject sounds: QtObject { property bool battery: false }
 }
}
''')
            write(root, 'modules/common/Directories.qml', 'pragma Singleton\nimport QtQuick\nQtObject { property string state: ' + json.dumps(str(root / 'state')) + ' }\n')
            write(root, 'modules/common/functions/qmldir', 'module qs.modules.common.functions\nsingleton FileUtils 1.0 FileUtils.qml\n')
            write(root, 'modules/common/functions/FileUtils.qml', 'pragma Singleton\nimport QtQuick\nQtObject { function trimFileProtocol(s) { return s.replace("file://", ""); } }\n')
            write(root, 'services/qmldir', 'module qs.services\nsingleton PowerAnalytics 1.0 PowerAnalytics.qml\nsingleton Translation 1.0 Translation.qml\n')
            shutil.copy2(SHELL / 'services/PowerAnalytics.qml', root / 'services/PowerAnalytics.qml')
            write(root, 'services/Translation.qml', 'pragma Singleton\nimport QtQuick\nQtObject { function tr(s) { return s; } }\n')
            with (root / 'services/qmldir').open('a') as stream:
                stream.write('singleton Battery 1.0 Battery.qml\n')
            # Load the actual Battery bindings, replacing only its external UPower
            # import so the test never queries hardware or triggers power actions.
            battery = (SHELL / 'services/Battery.qml').read_text()
            write(root, 'services/Battery.qml', battery.replace('import Quickshell.Services.UPower', 'import qs.fixtures'))
            write(root, 'fixtures/qmldir', 'module qs.fixtures\nsingleton UPower 1.0 UPower.qml\nsingleton UPowerDeviceState 1.0 UPowerDeviceState.qml\n')
            write(root, 'fixtures/UPowerDeviceState.qml', '''pragma Singleton
import QtQuick
QtObject { enum State { Unknown, Charging, Discharging, PendingCharge } }
''')
            write(root, 'fixtures/UPower.qml', '''pragma Singleton
import QtQuick
QtObject {
 property var devices: ({values: []})
 property QtObject displayDevice: QtObject {
  property bool isLaptopBattery: false
  property int state: 2
  property real percentage: 0.5
  property real changeRate: 4.25
  property real timeToEmpty: 1000
  property real timeToFull: 2000
 }
}
''')
            # Production panel/reader lifecycle with a delayed-stop process fixture.
            power = root / 'modules/settings/power'
            power.mkdir(parents=True)
            for file in ('PowerAnalyticsPanel.qml', 'AnalyticsSegments.qml', 'PowerHistoryChart.qml', 'ChartMath.js'):
                shutil.copy2(SHELL / 'modules/settings/power' / file, power)
            with (root / 'modules/common/qmldir').open('a') as stream:
                stream.write('singleton Appearance 1.0 Appearance.qml\n')
            write(root, 'modules/common/Appearance.qml', '''pragma Singleton
import QtQuick
QtObject {
 property var colors: ({colPrimary:"#89b4fa",colSubtext:"#777777",colSecondaryContainer:"#34344a",colOnSecondaryContainer:"#ffffff",colLayer3:"#252536",colLayer2Hover:"#333344",colOnLayer2:"#ffffff",colError:"#ff7777"})
 property var font: ({pixelSize:{smaller:12,small:14},family:{main:"Sans Serif"}})
 property var rounding: ({small:8,full:999})
 property QtObject animation: QtObject { property QtObject elementMoveFast: QtObject {
  property int duration:120; property int type:Easing.OutCubic; property var bezierCurve:[0,0,1,1,1,1]
  property Component numberAnimation:NumberAnimation { duration:120 }
  property Component colorAnimation:ColorAnimation { duration:120 }
 } }
}''')
            write(root, 'modules/common/widgets/qmldir', 'module qs.modules.common.widgets\nContentSection 1.0 ContentSection.qml\nConfigSwitch 1.0 ConfigSwitch.qml\nStyledText 1.0 StyledText.qml\nRippleButton 1.0 RippleButton.qml\n')
            write(root, 'modules/common/widgets/ContentSection.qml', 'import QtQuick\nimport QtQuick.Layouts\nColumnLayout { property string title; property string icon; property string description }')
            write(root, 'modules/common/widgets/ConfigSwitch.qml', 'import QtQuick.Controls\nButton { property string buttonIcon; property string description; property bool autoToggle }')
            write(root, 'modules/common/widgets/StyledText.qml', 'import QtQuick\nText {}')
            write(root, 'modules/common/widgets/RippleButton.qml', 'import QtQuick\nimport QtQuick.Controls\nButton { property real buttonRadius; property color colBackgroundHover }')
            # The actual collector has separate real-process/fake-sysfs tests.
            write(root, 'scripts/power/analytics.py', '''import json,signal,sys,time
from pathlib import Path
mode=sys.argv[1]
p=Path(sys.argv[sys.argv.index('--state-dir')+1])
log=p.parents[1]/'calls.txt'
log.parent.mkdir(parents=True,exist_ok=True)
with log.open('a') as f:f.write(mode+'\\n')
if mode=='clear':
 if p.exists():
  for q in p.iterdir():q.unlink()
else:
 def stop(*args):
  signal.signal(signal.SIGTERM,signal.SIG_IGN)
  time.sleep(0.6)
  if mode=='collect':
   with log.open('a') as f:f.write('collect-exited\\n')
  sys.exit(0)
 signal.signal(signal.SIGTERM,stop)
 if mode=='collect':p.mkdir(parents=True,exist_ok=True)
 while True:
  if mode=='collect':
   q=p/'latest.tmp'
   q.write_text(json.dumps({'timestamp':time.time(),'battery_power_w':-17.0,'percentage':62.0,'voltage_v':12.1}))
   q.replace(p/'latest.json')
  else:
   window=int(sys.argv[sys.argv.index('--window-seconds')+1])
   try:latest=json.loads((p/'latest.json').read_text())
   except (FileNotFoundError,json.JSONDecodeError):latest=None
   now=time.time()
   print(json.dumps({'latest':latest,'points':[latest] if latest else [],'window_start':now-window,'window_end':now,'sample_count':int(latest is not None),'stats':{}}),flush=True)
  time.sleep(0.15)
''')
            write(root, 'shell.qml', '''import QtQuick
import Quickshell
import "modules/common"
import "services"
import "modules/settings/power"
ShellRoot {
 PowerAnalyticsPanel { id: panel; width: 600 }
 function descendant(node,name) {
  if(node.objectName===name)return node;
  for(let child of (node.children??[])){let found=descendant(child,name);if(found)return found;}
  return null;
 }
 property int phase: 0
 property int checks: 0
 Component.onCompleted: PowerAnalytics.load()
 Timer { interval: 500; repeat: true; running: true
  onTriggered: {
   phase++;
   if (phase===1 && (PowerAnalytics.enabled || !Battery.energyRateAvailable || Battery.energyRate!==4.25)) {
    console.error("TEST default-off UPower source"); Qt.exit(5);
   }
   if (phase===2) {
    Config.options.battery.advancedAnalytics=true;
    if (Battery.energyRateAvailable || !isNaN(Battery.energyRate)) { console.error("TEST missing sample fallback"); Qt.exit(6); }
   }
   if (phase===3) descendant(panel,"powerHistoryRanges").selected(3600);
   if (phase===4) descendant(panel,"powerHistoryRanges").selected(28800);
   if (phase===7) {
    if (!PowerAnalytics.hasLivePower) { console.error("TEST no live sample", PowerAnalytics.error); Qt.exit(2); }
    if (!Battery.energyRateAvailable || Battery.energyRate!==17) { console.error("TEST analytics source"); Qt.exit(7); }
    PowerAnalytics.clock=PowerAnalytics.latest.timestamp+9;
    if (Battery.energyRateAvailable || !isNaN(Battery.energyRate)) { console.error("TEST stale sample fallback"); Qt.exit(8); }
    PowerAnalytics.clock=PowerAnalytics.latest.timestamp-3;
    if (Battery.energyRateAvailable || !isNaN(Battery.energyRate)) { console.error("TEST future sample fallback"); Qt.exit(9); }
    PowerAnalytics.clock=PowerAnalytics.latest.timestamp;
    let sample=PowerAnalytics.latest;
    PowerAnalytics.latest=Object.assign({},sample,{battery_power_w:null});
    if (Battery.energyRateAvailable || !isNaN(Battery.energyRate)) { console.error("TEST null sample fallback"); Qt.exit(10); }
    PowerAnalytics.latest=sample;
    let frame=descendant(panel,"powerHistoryChart").frame;
    if(!frame || Math.abs(frame.end-frame.start-28800)>1){console.error("TEST stale range");Qt.exit(4);}
    checks++; Config.options.battery.advancedAnalytics=false;
    if (!Battery.energyRateAvailable || Battery.energyRate!==4.25) { console.error("TEST restore UPower source"); Qt.exit(11); }
   }
   if (phase===8) Config.options.battery.advancedAnalytics=true;
   if (phase===10) Config.options.battery.advancedAnalytics=false;
   if (phase===14) { if (PowerAnalytics.latest!==null) { console.error("TEST stale sample"); Qt.exit(3); } Qt.quit(); }
  }
 }
}''')
            result = subprocess.run(['quickshell', '-p', str(root)], env=isolated_env(root), capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotIn('TEST ', result.stdout + result.stderr)
            self.assertNotIn('TypeError', result.stdout + result.stderr)
            self.assertNotIn('ReferenceError', result.stdout + result.stderr)
            calls = (root / 'state/calls.txt').read_text().splitlines()
            self.assertEqual(calls.count('collect'), 2, calls)
            self.assertGreaterEqual(calls.count('watch'), 2, calls)
            self.assertGreaterEqual(calls.count('clear'), 2, calls)
            collecting = False
            for call in calls:
                if call == 'collect':
                    self.assertFalse(collecting, calls)
                    collecting = True
                elif call == 'collect-exited':
                    collecting = False
                elif call == 'clear':
                    self.assertFalse(collecting, 'clear ran before delayed collector exit: ' + str(calls))
            self.assertFalse(collecting, calls)
            self.assertFalse((root / 'state/user/power-analytics/latest.json').exists())
            # A settings-only process must not start or erase the shell's collector.
            write(root, 'shell.qml', '''import QtQuick
import Quickshell
import "modules/common"
import "services"
ShellRoot {
 Component.onCompleted: Config.options.battery.advancedAnalytics=true
 Timer { interval: 400; running: true; onTriggered: { console.log(PowerAnalytics.enabled); Qt.quit(); } }
}''')
            before = (root / 'state/calls.txt').read_text()
            result = subprocess.run(['quickshell', '-p', str(root)], env=isolated_env(root), capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual((root / 'state/calls.txt').read_text(), before)


if __name__ == '__main__':
    unittest.main()
