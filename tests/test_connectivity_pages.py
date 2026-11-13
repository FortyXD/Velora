"""The real settings pages, in the real shell runtime, with the real daemon and a stand-in NetworkManager on a
private bus. It catches what stand-in widgets can't: a type that won't load, a property clash, a broken binding."""
import os
import json
from pathlib import Path
import re
import shutil
import signal
import subprocess
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[1]
SHELL = PROJECT / 'dots/.config/quickshell/ii'
TOOLS = PROJECT / 'tools'
QS = shutil.which('qs')
CARGO = shutil.which('cargo')
DBUS = '/usr/bin/dbus-daemon' if Path('/usr/bin/dbus-daemon').exists() else shutil.which('dbus-daemon')
REQUIRED = os.environ.get('VELORA_REQUIRE_CONNECTIVITY_TESTS') == '1'
PROBLEMS = re.compile(r'unavailable|is not a type|TypeError|ReferenceError|Cannot override|Cannot assign|Unable to assign|'
                      r'Non-existent|failed to load|Could not|Expected token|Script .* unavailable|coerced to void', re.I)
# Noise from outside these pages, which load the whole shell's singletons
IGNORED = re.compile(r'Read of .* failed|Notifications\.qml|GlobalFocusGrab|QFont|Fontconfig|portal|gsettings|hyprctl|Hyprland|HYPRLAND|QDBus|Bluetooth|bluez|'
                     r'WlrLayershell|wlr-layer|Wayland|wayland|Polkit|polkit|PipeWire|pipewire|UPower|upower|PowerProfilesDaemon|logind|persistent states', re.I)

# Its own configuration: the standard ones start real services on demand
BUS_CONFIG = """<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:tmpdir=/tmp</listen>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
"""

DRIVER = r'''
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.settings
import qs.modules.common.panels

ShellRoot {
    id: root
    property int step: 0
    property var failures: []
    property var pairError: null
    property real collapsedCurrentHeight: 0

    function check(what, condition) {
        console.log((condition ? "CHECK_OK " : "CHECK_FAIL ") + what);
        if (!condition) failures.push(what);
    }

    function findItem(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children ?? []) {
            const found = root.findItem(child, name);
            if (found) return found;
        }
        return null;
    }

    function findItems(item, name) {
        let found = item.objectName === name ? [item] : [];
        for (const child of item.children ?? []) found = found.concat(root.findItems(child, name));
        return found;
    }

    function finish() {
        console.log(failures.length === 0 ? "DRIVER_PASS" : "DRIVER_FAIL " + failures.join("; "));
        Qt.exit(0);
    }

    FloatingWindow {
        id: window
        implicitWidth: 1000
        implicitHeight: 800
        visible: true

        function openPage(key) {
            console.log("OPEN_PAGE " + key);
        }

        Loader { id: wifi; anchors.fill: parent; source: "modules/settings/WifiConfig.qml" }
        Loader { id: connections; anchors.fill: parent; source: "modules/settings/ConnectionsConfig.qml" }
        Loader { id: editor; anchors.fill: parent; source: "modules/settings/ConnectionEditorConfig.qml" }
        Loader { id: bluetooth; anchors.fill: parent; source: "modules/settings/BluetoothConfig.qml" }
        Loader { id: device; anchors.fill: parent; source: "modules/settings/BluetoothDeviceConfig.qml" }
        Loader { id: options; anchors.fill: parent; source: "modules/settings/BluetoothOptionsConfig.qml" }
        Loader { id: keyboard; anchors.fill: parent; source: "modules/settings/KeyboardConfig.qml" }
        Loader { id: shortcuts; anchors.fill: parent; source: "modules/settings/ShortcutsConfig.qml" }
        Loader { id: prompt; source: "modules/common/panels/ConnectivityPromptWindow.qml"; active: false }
    }

    Timer {
        interval: 200
        repeat: true
        running: true
        onTriggered: {
            if (root.step === 0) {
                if ((Network.state.profiles ?? []).length < 6) return;
                root.step = 1;
                root.check("the Wi-Fi page loaded", wifi.status === Loader.Ready);
                root.check("the connections page loaded", connections.status === Loader.Ready);
                root.check("the editor page loaded", editor.status === Loader.Ready);
                root.check("all saved networks are listed", wifi.item.savedKeys.length === 4);
                root.check("the most recent available one first", wifi.item.savedKeys[0] === "home-uuid");
                root.check("a network without a profile is under nearby", wifi.item.nearby.some(network => network.ssid === "Cafe"));
                root.check("available saved networks lead nearby, then the rest by signal", JSON.stringify(wifi.item.nearby.map(network => network.ssid)) === '["Home","Office","Cafe","Neighbour"]');
                const bands = root.findItems(wifi.item, "wifiFrequencyBand");
                root.check("GHz shares one column with and without a lock", bands.length === 4 && bands.every(band => Math.abs(band.x - bands[0].x) < 0.5));
                wifi.item.query = "office";
                root.check("search finds an available saved network", wifi.item.matching.length === 1 && wifi.item.matching[0].ssid === "Office");
                wifi.item.query = "";
                const sections = Array.from(wifi.item.contentData).filter(item => item.settingsSection);
                root.check("the current connection, cable and nearby networks come first", sections[1].icon === "wifi" && sections[2].icon === "cable" && sections[3].icon === "wifi_find");
                root.check("Ethernet stays visible with an adapter but no active connection", !Network.ethernet && sections[2].visible);
                const cableRow = Array.from(sections[2].contentData)[0];
                root.check("Ethernet identifies the disconnected adapter", cableRow.title === "eth0" && cableRow.description === Translation.tr("Not connected"));
                root.check("Ethernet is shown as enabled whenever its adapter is present", cableRow.valueText === Translation.tr("Enabled"));
                root.check("saved passwords are the last section", sections[sections.length - 1].icon === "bookmark");
                const savedRows = Array.from(sections[sections.length - 1].contentData).find(item => typeof item.itemAt === "function");
                const savedRow = savedRows.itemAt(0);
                savedRow.primaryAction();
                root.check("clicking a saved password unfolds it without connecting", savedRow.expanded && !Network.connectionPending);
                savedRow.primaryAction();
                root.check("the VPN is under connections", connections.item.vpnKeys.includes("vpn-uuid"));
                root.check("the cable is under connections", connections.item.otherKeys.includes("wired-uuid"));
                root.check("no Wi-Fi is under other connections", !connections.item.otherKeys.includes("home-uuid"));
                Network.editProfile("home-uuid");
            } else if (root.step === 1) {
                if (ProfileEditor.fields["connection.id"] !== "home-uuid") return;
                root.step = 2;
                root.check("the editor shows the profile", ProfileEditor.title === "home-uuid");
                root.check("it knows the security", editor.item.securityChoice === "wpa-psk");
                root.check("it has no secret until asked", Object.keys(ProfileEditor.secrets).length === 0);
                ProfileEditor.set("connection.autoconnect", false);
                ProfileEditor.set("ipv4.method", "manual");
                ProfileEditor.set("ipv4.address-data", ["10.1.2.3/24"]);
                ProfileEditor.set("ipv4.gateway", "10.1.2.1");
                ProfileEditor.set("ipv4.dns", ["1.1.1.1"]);
                root.check("edits count as unsaved", ProfileEditor.dirty);
                ProfileEditor.save();
            } else if (root.step === 2) {
                if (ProfileEditor.saving || ProfileEditor.loading || ProfileEditor.dirty) return;
                root.step = 3;
                root.check("saving worked", ProfileEditor.errorText === "");
                root.check("the edit is stored", ProfileEditor.fields["connection.autoconnect"] === false);
                root.check("the address is stored", JSON.stringify(ProfileEditor.fields["ipv4.address-data"]) === '["10.1.2.3/24"]');
                root.check("the DNS server is stored", JSON.stringify(ProfileEditor.fields["ipv4.dns"]) === '["1.1.1.1"]');
                ProfileEditor.readSecrets(() => {
                    root.check("the password survived the edit", ProfileEditor.secrets["802-11-wireless-security.psk"] === "home-password");
                    ProfileEditor.forgetSecrets();
                    root.step = 4;
                });
            } else if (root.step === 4) {
                root.step = 5;
                ProfileEditor.open("vpn-uuid");
            } else if (root.step === 5) {
                if (ProfileEditor.fields["connection.id"] !== "Work VPN") return;
                root.step = 6;
                root.check("a VPN's kind is recognised", editor.item.isOpenVpn);
                root.check("its data is readable", ProfileEditor.value("vpn.data.remote", "") === "vpn.example.com");
                ProfileEditor.set("vpn.data.username", "me");
                ProfileEditor.save();
            } else if (root.step === 6) {
                if (ProfileEditor.saving || ProfileEditor.loading || ProfileEditor.dirty) return;
                root.step = 7;
                root.check("a VPN edit is stored", ProfileEditor.fields["vpn.data"].username === "me");
                root.check("the rest of its data stays", ProfileEditor.fields["vpn.data"].remote === "vpn.example.com");
                ProfileEditor.startNew("802-3-ethernet", "", { "connection.id": "New cable" });
                root.check("a new profile opens", ProfileEditor.isNew);
                root.check("as its kind", editor.item.isWired);
                ProfileEditor.save();
            } else if (root.step === 7) {
                if (ProfileEditor.saving || ProfileEditor.isNew || ProfileEditor.loading) return;
                root.step = 8;
                root.check("adding worked", ProfileEditor.errorText === "");
                root.check("and it opens the saved one", ProfileEditor.uuid.length === 36);
            } else if (root.step === 8) {
                if (!connections.item.otherKeys.includes(ProfileEditor.uuid)) return;
                root.check("the new profile is listed", true);
                root.step = 9;
            } else if (root.step === 9) {
                if ((BluetoothManager.saved ?? []).length < 2) return;
                root.step = 10;
                root.check("the Bluetooth page loaded", bluetooth.status === Loader.Ready);
                root.check("the device page loaded", device.status === Loader.Ready);
                root.check("the Bluetooth settings page loaded", options.status === Loader.Ready);
                root.check("the keyboard page loaded", keyboard.status === Loader.Ready);
                root.check("the shortcuts page loaded", shortcuts.status === Loader.Ready);
                root.check("saved devices are listed, connected first", bluetooth.item.savedKeys[0].endsWith("11_11_11_11_11_11"));
                root.check("new ones are apart", bluetooth.item.namedKeys.some(path => path.endsWith("33_33_33_33_33_33")));
                root.check("a saved device isn't under nearby", !bluetooth.item.namedKeys.some(path => path.endsWith("22_22_22_22_22_22")));
                BluetoothManager.showDevice("/org/bluez/hci0/dev_22_22_22_22_22_22");
                root.check("the device page shows it", device.item.device?.name === "Phone");
                BluetoothManager.setTrusted("/org/bluez/hci0/dev_22_22_22_22_22_22", false);
                BluetoothManager.pair("/org/bluez/hci0/dev_33_33_33_33_33_33", error => root.pairError = error);
            } else if (root.step === 10) {
                if (BluetoothManager.busy["/org/bluez/hci0/dev_33_33_33_33_33_33"] === true) return;
                root.step = 11;
                root.check("pairing worked", root.pairError === null);
                root.check("no error is showing", BluetoothManager.errors["/org/bluez/hci0/dev_33_33_33_33_33_33"] === undefined);
            } else if (root.step === 11) {
                if (!BluetoothManager.saved.some(device => device.name === "Speaker" && device.connected)) return;
                root.step = 12;
                root.check("the paired device moved to saved and connected", true);
                root.check("the device page's device is still right", device.item.device?.name === "Phone");
                BluetoothManager.showDevice("/org/bluez/hci0/dev_33_33_33_33_33_33");
                BluetoothManager.forget("/org/bluez/hci0/dev_33_33_33_33_33_33");
            } else if (root.step === 12) {
                if (BluetoothManager.saved.some(device => device.name === "Speaker")) return;
                root.check("forgetting removes it", true);
                root.check("the page doesn't hold on to it", device.item.device === null);
                root.step = 13;
                // The stand-in activates profiles without setting ActiveAccessPoint. Supply that scan
                // state here, including a strong saved network whose password was never usable.
                ConnectivityBackend.network = Object.assign({}, Network.state, {
                    networks: Network.state.networks.map(network => Object.assign({}, network, { active: network.ssid === "Home" })).concat([
                        Object.assign({}, Network.state.networks[0], { ssid: "Never joined", active: false, strength: 99, savedUuid: "never-uuid", neverUsed: true }),
                    ]),
                });
            } else if (root.step === 13) {
                if (wifi.item.current?.ssid !== "Home" || Network.connectionPending || wifi.item.nearby.some(network => network.ssid === "Home")) return;
                root.check("a saved network without usable credentials stays among the rest", JSON.stringify(wifi.item.nearby.map(network => network.ssid)) === '["Office","Never joined","Cafe","Neighbour"]');
                const summary = root.findItem(wifi.item, "currentNetworkSummary");
                const details = root.findItem(wifi.item, "currentNetworkDetails");
                root.check("the current network starts folded, with its name and signal", !details.visible && summary.title === "Home" && summary.valueText.includes("82%"));
                root.collapsedCurrentHeight = Array.from(wifi.item.contentData).find(item => item.settingsSection && item.icon === "wifi").height;
                summary.clicked();
                root.check("opening the current network starts without a height jump", details.visible && details.implicitHeight === 0);
                root.step = 15;
            } else if (root.step === 15) {
                const details = root.findItem(wifi.item, "currentNetworkDetails");
                if (details.opacity < 1) return;
                root.check("the opening animation reveals the details", details.height > 0);
                root.findItem(wifi.item, "currentNetworkSummary").clicked();
                root.check("closing keeps the details visible while their height shrinks", details.visible && details.height > 0 && !details.enabled);
                root.step = 16;
            } else if (root.step === 16) {
                const details = root.findItem(wifi.item, "currentNetworkDetails");
                if (details.visible) return;
                const currentSection = Array.from(wifi.item.contentData).find(item => item.settingsSection && item.icon === "wifi");
                root.check("the closing animation leaves no empty space", details.implicitHeight === 0 && Math.abs(currentSection.height - root.collapsedCurrentHeight) < 0.5);
                details.settingsReveal();
                root.check("settings search unfolds details before scrolling", wifi.item.currentExpanded && details.implicitHeight > 0);
                wifi.item.pageShown = false;
                root.check("leaving the page folds the details", !wifi.item.currentExpanded);
                root.step = 14;
                ConnectivityBackend.network = Object.assign({}, Network.state, {
                    devices: Network.state.devices.filter(device => device.deviceType !== 1),
                    ethernetDetails: null,
                    ethernetConnected: false,
                });
            } else if (root.step === 14) {
                const cableSection = Array.from(wifi.item.contentData).find(item => item.settingsSection && item.icon === "cable");
                root.check("Ethernet is hidden when its adapter is absent", !cableSection.visible);
                root.finish();
            }
        }
    }

    Timer {
        interval: 25000
        running: true
        onTriggered: {
            root.check("reached the end within the time limit, stopped at step " + root.step, false);
            root.finish();
        }
    }
}
'''


LENS_SETTINGS_FIXTURE = '''pragma Singleton
import QtQuick
import Quickshell
Singleton {
    property bool enabled: true
    property bool ready: false
    property bool settingsVisible: false
    property bool unlocking: false
    property string reviewingSource: ""
    property var reviewChoices: []
    property string problem: ""
    property var setupInfo: ({installed:false, running:false, models:false, stage:""})
    property var status: ({locked:true})
    readonly property bool usable: enabled && ready && !status.locked
    readonly property bool setupRunning: setupInfo.running
    function refresh() {}
    function checkSetup() {}
    property string query: ""
    property var results: []
    function search(text) { query = text; }
    function cancelSearch() { query = ""; results = []; }
    function reconnectNow() {}
    function prepare() { setupInfo = {installed:false,running:true,stage:"models",step:4,steps_total:5,steps_done:3,elapsed_seconds:125,progress:{task:"model-download",model:"e5",model_number:1,models_total:2,unit:"bytes",done:262144000,total:524288000,transferred:210000000}}; }
    function cancelSetup() { setupInfo = {installed:false,running:false,stage:"cancelled"}; }
    function setupLabel() { return "Downloading and preparing models"; }
    function unlockIndex() {}
    function call(method, params, done) {}
    function configure(changes) { status = Object.assign({}, status, {config: Object.assign({}, status.config, changes)}); }
    function reviewSource(path, include) {
        reviewChoices = reviewChoices.concat([{path, include}]);
        configure({source_reviews: status.config.source_reviews.filter(review => review.path !== path)});
    }
}
'''

@unittest.skipUnless((QS and CARGO and DBUS) or REQUIRED, 'needs qs, cargo and dbus-daemon')
class SettingsPagesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        target = TOOLS / 'target'
        if not os.environ.get('VELORA_TEST_PREBUILT'):
            subprocess.run([CARGO, 'build', '--quiet', '--manifest-path', str(TOOLS / 'Cargo.toml'),
                            '-p', 'velora-connectivityd', '-p', 'velora-connectivity-fakes'], check=True, timeout=400)
        cls.daemon = target / 'debug/velora-connectivityd'
        cls.fakes = target / 'debug/velora-connectivity-fakes'

    def run_driver(self, driver, *, settings_page=None, service_overrides=None):
        with tempfile.TemporaryDirectory(prefix='velora-pages-') as directory:
            root = Path(directory)
            shell = root / 'shell'
            shell.mkdir()
            for item in SHELL.iterdir():
                if item.name not in ('shell.qml', 'settings.qml', 'services'):
                    (shell / item.name).symlink_to(item)
            # The real services, but for the one that opens a panel, which only a compositor can give
            services = shell / 'services'
            services.mkdir()
            for item in (SHELL / 'services').iterdir():
                if item.name != 'Idle.qml':
                    (services / item.name).symlink_to(item)
            (services / 'Idle.qml').write_text('pragma Singleton\nimport Quickshell\nSingleton { property bool inhibit: false; function toggleInhibit(active) {} }\n')
            for name, source in (service_overrides or {}).items():
                (services / name).unlink(missing_ok=True)
                (services / name).write_text(source)
            (shell / 'shell.qml').write_text(driver)
            home = root / 'home'
            home.mkdir()
            # Programs that act on this computer are stood in for
            tools = root / 'tools'
            tools.mkdir()
            for name in ('rfkill', 'hyprctl', 'notify-send', 'wl-copy', 'nmcli', 'systemctl', 'qrencode', 'ddcutil'):
                (tools / name).write_text('#!/bin/sh\nexit 0\n')
                (tools / name).chmod(0o755)
            runtime = root / 'runtime'
            runtime.mkdir(mode=0o700)
            config = root / 'bus.conf'
            config.write_text(BUS_CONFIG)
            bus = subprocess.Popen([DBUS, f'--config-file={config}', '--nofork', '--print-address'], stdout=subprocess.PIPE, text=True)
            fakes = None
            try:
                address = bus.stdout.readline().strip()
                # Nothing here may reach the desktop this runs on: no compositor, session or user services
                inherited = {name: value for name, value in os.environ.items()
                             if name not in ('HYPRLAND_INSTANCE_SIGNATURE', 'WAYLAND_DISPLAY', 'DISPLAY', 'XDG_SESSION_ID', 'SWAYSOCK', 'I3SOCK')}
                environment = {**inherited, 'HOME': str(home), 'XDG_CONFIG_HOME': str(home / '.config'), 'XDG_STATE_HOME': str(home / '.state'),
                               'XDG_CACHE_HOME': str(home / '.cache'), 'XDG_DATA_HOME': str(home / '.data'), 'XDG_RUNTIME_DIR': str(runtime),
                               'DBUS_SYSTEM_BUS_ADDRESS': address, 'DBUS_SESSION_BUS_ADDRESS': address,
                               'PATH': f"{tools}:{inherited.get('PATH', '/usr/bin')}",
                               'VELORA_CONNECTIVITYD': str(self.daemon), 'VELORA_NM_VPN_DIRS': '/nonexistent',
                               'QT_QPA_PLATFORM': 'offscreen', 'QT_QPA_PLATFORMTHEME': 'generic', 'QT_QUICK_BACKEND': 'software', 'FONTCONFIG_FILE': '/etc/fonts/fonts.conf'}
                if settings_page is not None:
                    environment.update(QS_SETTINGS_PAGE=settings_page, QS_SETTINGS_SECTION='', QS_SETTINGS_SEARCH='')
                fakes = subprocess.Popen([str(self.fakes)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, env=environment)
                self.assertEqual(fakes.stdout.readline().strip(), 'READY')
                log = root / 'log.txt'
                with log.open('w') as output_file:
                    # Its own process group, and a file for its output: whatever the shell starts can't hold this up
                    shell_process = subprocess.Popen([QS, '-p', str(shell / 'shell.qml'), '--no-color'], env=environment, stdout=output_file,
                                                     stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, start_new_session=True)
                    try:
                        shell_process.wait(timeout=45)
                    except subprocess.TimeoutExpired:
                        pass
                    finally:
                        try:
                            os.killpg(shell_process.pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                        shell_process.wait()
                output = log.read_text(errors='replace')
            finally:
                if fakes:
                    fakes.kill()
                    fakes.wait()
                    fakes.stdin.close()
                    fakes.stdout.close()
                bus.kill()
                bus.wait()
                bus.stdout.close()
        return output

    def assert_clean(self, output):
        problems = [line for line in output.splitlines()
                    if PROBLEMS.search(line) and not IGNORED.search(line) and 'CHECK_' not in line]
        self.assertEqual(problems, [], output[-4000:])

    def test_display_last_output_guard(self):
        output = self.run_driver('''
import QtQuick
import QtTest
import Quickshell
import qs.services
import qs.modules.settings
ShellRoot {
    id: root
    property int step: 0
    property bool failed: false
    TestCase { id: input; name: "LastDisplay"; when: false }
    function check(value,message) { if (!value) { failed = true; console.log("CHECK_FAIL " + message); } }
    function find(item,name) { if (item.objectName === name) return item; for (const child of item.children ?? []) { const found = find(child,name); if (found) return found; } return null; }
    FloatingWindow {
        implicitWidth: 960; implicitHeight: 850; visible: true
        DisplaysConfig { id: page; anchors.fill: parent }
    }
    Timer {
        interval: 500; running: true; repeat: true
        onTriggered: {
            const toggle = root.find(page,"displayEnabled");
            if (step === 0) {
                HyprlandMonitors.keep(); HyprlandMonitors.overrides = {};
                HyprlandMonitors.monitors = [
                    {name:"eDP-1",width:1920,height:1080,refreshRate:60,scale:1,x:0,y:0,availableModes:["1920x1080@60"]},
                    {name:"HDMI-A-1",width:1920,height:1080,refreshRate:60,scale:1,x:1920,y:0,availableModes:["1920x1080@60"]}
                ];
                page.selectedName = "eDP-1";
            } else if (step === 1) {
                root.check(toggle.enabled && toggle.checked,"first display can be turned off");
                input.mouseClick(toggle);
                root.check(HyprlandMonitors.overrides["eDP-1"]?.disabled,"first display was disabled");
                HyprlandMonitors.keep();
                page.selectedName = "HDMI-A-1";
            } else if (step === 2) {
                root.check(!toggle.enabled && toggle.checked && toggle.description.length > 0,"last display remains on with explanation");
                toggle.clicked(); // Even a stale event must be rejected by the service.
                root.check(!HyprlandMonitors.spec(page.selected).disabled && !HyprlandMonitors.confirming,"stale click cannot disable last display");
                page.selectedName = "eDP-1";
            } else if (step === 3) {
                root.check(toggle.enabled && !toggle.checked,"disabled display can be enabled again");
                input.mouseClick(toggle);
                HyprlandMonitors.keep();
                page.selectedName = "HDMI-A-1";
            } else if (step === 4) {
                root.check(toggle.enabled && toggle.checked,"other display can now be disabled");
                HyprlandMonitors.monitors = [HyprlandMonitors.monitors[1]];
            } else {
                root.check(!toggle.enabled && toggle.checked,"unplugged display is not counted as a fallback");
                console.log(root.failed ? "DRIVER_FAIL" : "DRIVER_PASS"); Qt.quit();
            }
            step++;
        }
    }
}
''')
        self.assertIn("DRIVER_PASS",output,output[-6000:])
        self.assertNotIn("CHECK_FAIL",output)
        self.assert_clean(output)

    def test_lens_settings_load_with_real_widgets(self):
        output = self.run_driver('''
import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.settings
ShellRoot {
    FloatingWindow {
        visible: true
        implicitWidth: 1000
        implicitHeight: 800
        Loader { id: page; anchors.fill: parent; source: "modules/settings/SearchConfig.qml" }
    }
    Timer {
        interval: 800; running: true
        onTriggered: {
            console.log(page.status === Loader.Ready && !Lens.enabled ? "DRIVER_PASS" : "DRIVER_FAIL");
            Qt.exit(0);
        }
    }
}
''')
        self.assertIn('DRIVER_PASS', output, output[-4000:])
        self.assert_clean(output)

    def test_lens_result_rows_show_literal_paths_in_both_launchers(self):
        output = self.run_driver('''
import QtQuick
import Quickshell
import qs.modules.common.models
import qs.modules.ii.overview
import qs.modules.waffle.startMenu.searchPage
ShellRoot {
    LauncherSearchResult {
        id: sampleEntry
        name: "lecture.md"
        lensPath: "/home/example/Documents/SHAD/DL/<notes>/lecture.md"
        comment: "Related meaning"
        iconType: LauncherSearchResult.IconType.Material
        iconName: "description"
    }
    FloatingWindow {
        visible: true
        implicitWidth: 600; implicitHeight: 400
        Column {
            width: parent.width
            SearchItem { id: overview; width: parent.width; entry: sampleEntry; query: "conv layer" }
            SearchResultButton { id: waffle; width: parent.width; entry: sampleEntry }
        }
    }
    function pathRow(item) {
        if (item.objectName === "lensResultPath") return item;
        for (const child of item.children ?? []) {
            const result = pathRow(child);
            if (result) return result;
        }
        return null;
    }
    Timer {
        property int step: 0
        interval: 700; running: true; repeat: true
        onTriggered: {
            const rows = [pathRow(overview), pathRow(waffle)];
            if (step === 0) {
                if (rows.some(r => !r || !r.visible || r.text !== sampleEntry.lensPath || r.textFormat !== Text.PlainText || r.height <= 0)) {
                    console.log("DRIVER_FAIL file paths"); Qt.exit(0); return;
                }
                sampleEntry.lensPath = "app:code.desktop";
            } else {
                console.log(rows.every(r => !r.visible) ? "DRIVER_PASS" : "DRIVER_FAIL app paths");
                Qt.exit(0);
            }
            step++;
        }
    }
}
''')
        self.assertIn('DRIVER_PASS', output, output[-6000:])
        self.assert_clean(output)

    def test_plain_search_does_not_show_symbolic_calculator_results(self):
        output = self.run_driver('''
import QtQuick
import Quickshell
import qs.services
ShellRoot {
    Timer {
        property int step: 0
        interval: 800; running: true; repeat: true
        onTriggered: {
            if (step === 0) LauncherSearch.query = "2+2";
            if (step === 1) {
                if (!LauncherSearch.mathQuery || !LauncherSearch.results.some(r => r.name === "4")) { console.log("DRIVER_FAIL arithmetic"); Qt.exit(0); return; }
                LauncherSearch.query = "npl";
            }
            if (step === 2) {
                console.log(!LauncherSearch.mathQuery && LauncherSearch.mathResult === "" && !LauncherSearch.results.some(r => r.iconName === "calculate") ? "DRIVER_PASS" : "DRIVER_FAIL symbolic noise");
                Qt.exit(0);
            }
            step++;
        }
    }
}
''')
        self.assertIn('DRIVER_PASS', output, output[-6000:])
        self.assert_clean(output)

    def test_lens_config_results_precede_loose_application_matches(self):
        lens = '''pragma Singleton
import QtQuick
import Quickshell
Singleton {
    property bool enabled: true
    property string query: ""
    property string queryKind: ""
    property var results: []
    function search(text) {
        query = text;
        queryKind = text.startsWith("config ") ? "config" : "";
        results = [{id:1,name:"general.lua",path:"/home/example/.config/hypr/general.lua",kind:"config"}];
    }
    function explanation(hit) { return "Text match"; }
    function open(hit, folder) {}
}
'''
        apps = '''pragma Singleton
import QtQuick
import Quickshell
Singleton {
    function fuzzyQuery(query) {
        return [{id:"configuration.desktop",name:"Configuration",icon:"settings",comment:"",runInTerminal:false,genericName:"",keywords:[],actions:[],execute:()=>{}}];
    }
}
'''
        driver = '''
import QtQuick
import Quickshell
import qs.services
ShellRoot {
    Timer {
        property int step: 0
        interval: 500; running: true; repeat: true
        onTriggered: {
            if (step === 0) LauncherSearch.query = "config for keyboard hypr";
            if (step === 1) {
                if (LauncherSearch.results[0]?.name !== "general.lua") { console.log("DRIVER_FAIL config result order"); Qt.exit(0); return; }
                LauncherSearch.query = "configuration";
            }
            if (step === 2) {
                console.log(LauncherSearch.results[0]?.name === "Configuration" ? "DRIVER_PASS" : "DRIVER_FAIL app result order");
                Qt.exit(0);
            }
            step++;
        }
    }
}
'''
        output = self.run_driver(driver, service_overrides={'Lens.qml': lens, 'AppSearch.qml': apps})
        self.assertIn('DRIVER_PASS', output, output[-6000:])
        self.assert_clean(output)

    def test_lens_setup_folder_picker_and_layout(self):
        stub = LENS_SETTINGS_FIXTURE
        artifacts = os.environ.get('VELORA_TEST_ARTIFACTS', '')
        if artifacts:
            Path(artifacts).mkdir(parents=True, exist_ok=True)
        driver = r'''
import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.settings
ShellRoot {
    id: root
    property int step: 0
    property bool failed: false
    property bool grabbing: false
    property string artifacts: ARTIFACTS
    function find(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children ?? []) { const result = find(child, name); if (result) return result; }
        return null;
    }
    function findAll(item, name) {
        let results = item.objectName === name ? [item] : [];
        for (const child of item.children ?? []) results = results.concat(findAll(child, name));
        return results;
    }
    function inside(item, ancestor) {
        for (let parent = item.parent; parent; parent = parent.parent) if (parent === ancestor) return true;
        return false;
    }
    function check(condition, message) { if (!condition) { failed = true; console.log("CHECK_FAIL " + message); } }
    function snapshot(name) {
        if (!artifacts) return;
        grabbing = true;
        capture.grabToImage(result => { result.saveToFile(artifacts + "/" + name + ".png"); grabbing = false; });
    }
    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 830
        implicitHeight: 1050
        color: Appearance.colors.colLayer1
        Rectangle {
            id: capture; width: parent.width; height: parent.height; color: Appearance.colors.colLayer1
            Loader { id: page; anchors.fill: parent; source: "modules/settings/SearchConfig.qml"; onLoaded: item.tab = "indexing" }
        }
    }
    Timer {
        interval: 350; repeat: true; running: true
        onTriggered: {
            if (grabbing) return;
            const settings = root.find(page.item, "lensSettings");
            const folders = root.find(page.item, "lensFolders");
            if (step === 0) {
                root.check(page.status === Loader.Ready, "page loaded");
                root.check(!folders.visible, "hide unavailable controls");
                root.check(root.find(page.item, "lensStatusTitle").text === "Set up search on this computer", "missing service has its own status");
                root.snapshot("setup");
            } else if (step === 1) {
                root.find(page.item, "lensPrepare").clicked();
                root.check(Lens.setupRunning, "setup starts inside Settings");
            } else if (step === 2) {
                root.check(root.find(page.item, "lensSetupSteps").text === "Step 4 of 5 · 3 completed", "setup step counts");
                root.check(root.find(page.item, "lensSetupMetric").text.includes("250.0 MiB"), "measured download size");
                root.check(root.find(page.item, "lensSetupProgress").visible && Math.abs(root.find(page.item, "lensSetupProgress").value - 0.5) < 0.01, "half the model data is ready");
                root.snapshot("progress");
            } else if (step === 3) {
                Lens.setupInfo = {installed:true,models:true,running:false,stage:"done"};
                Lens.ready = true;
                page.item.tab = "files";
                Lens.status = {locked:false,models:true,files:1240,pending:0,failed:0,config:{roots:["/home/example/Projects","/home/example/Documents/Research/Deep learning experiments/Projects"],excludes:[],activity:true,media:true,paused:false}};
            } else if (step === 4) {
                root.check(folders.visible, "folder list appears when ready");
                const samples = root.find(page.item, "lensDatasetSamples");
                root.check(samples && !samples.checked, "dataset samples default off");
                settings.addFolder("/home/example/Projects/training-data", false, true);
                settings.addFolder("/home/example/Projects/training-data", false, true);
                root.check(Lens.status.config.dataset_folders.length === 1, "dataset choice is saved without duplicates");
                root.check(Lens.status.config.roots.length === 2 && Lens.status.config.excludes.length === 0, "dataset rules preserve source and exclusion lists");
                samples.clicked();
                root.check(Lens.status.config.dataset_samples === true, "enable individual samples");
                samples.clicked();
                root.check(Lens.status.config.dataset_samples === false, "disable individual samples");
                settings.removeFolder("/home/example/Projects/training-data", false, true);
                root.check(Lens.status.config.dataset_folders.length === 0, "dataset choice can be removed");
                root.check(root.find(page.item, "lensIndexCount").text.includes("files and apps"), "legacy totals explicitly include apps");
                root.check(!root.inside(folders, root.find(page.item, "lensSetupCard")) && page.item.tab === "files", "folders have their own details, separate from index maintenance");
                settings.addFolder("/tmp/Новая папка", false);
                root.check(Lens.status.config.roots.length === 3, "folder picker result saves immediately");
                settings.removeFolder("/tmp/Новая папка", false);
                settings.addFolder("/home/example/Projects/private", true);
                root.check(Lens.status.config.roots.length === 2 && Lens.status.config.excludes.length === 1, "remove and exclude save immediately");
            } else if (step === 5) {
                root.snapshot("ready");
            } else if (step === 6) {
                capture.width = 530;
            } else if (step === 7) {
                root.check(page.width <= 540 && settings.width <= page.width && settings.width > 300, "narrow layout fits");
                const paths = root.findAll(folders, "lensFolderPath");
                root.check(paths.length === 2 && paths[1].text === Lens.status.config.roots[1], "show full selected paths");
                root.check(paths[1].lineCount > 1 && !paths[1].truncated, "long paths wrap in narrow settings");
                root.snapshot("narrow");
            } else if (step === 8) {
                page.item.tab = "indexing";
                Lens.status = Object.assign({}, Lens.status, {files:1093,pending:330,failed:20,applications:93,folder_stats:{total:1000,pending:300,failed:20},idle:true,on_battery:false,current:{name:"lecture.mp4",folder:"/home/example/Projects/Course videos",elapsed_seconds:63,video_seconds:240}});
            } else if (step === 9) {
                root.check(settings.indexCompleted === 700, "processed includes skipped items");
                root.check(settings.indexTotal === 1000 && settings.indexPending === 300, "application work is excluded from folder progress");
                root.check(root.find(page.item, "lensApplicationCount").text === "Applications: 93 available", "separate app count");
                root.check(root.find(page.item, "lensIndexPercent").text === "70%", "index percent");
                root.check(Math.abs(root.find(page.item, "lensIndexBar").value - 0.7) < 0.01, "index bar");
                root.check(root.find(page.item, "lensCurrentFile").text.includes("lecture.mp4"), "current file is visible");
                root.check(root.find(page.item, "lensCurrentFolder").text.includes("/home/example/Projects/Course videos"), "current processing folder is visible");
                root.snapshot("indexing");
            } else if (step === 10) {
                Lens.status = Object.assign({}, Lens.status, {scanning:true,total_known:false});
                root.check(!root.find(page.item, "lensIndexPercent").visible, "unknown total has no percent");
                root.check(!root.find(page.item, "lensIndexBar").visible, "unknown total has no fraction bar");
                root.check(root.find(page.item, "lensIndexCount").text.includes("counting"), "discovery reports growing count");
            } else if (step === 11) {
                Lens.setupInfo = {installed:false,running:false,stage:"failed"};
                Lens.problem = "Fixture setup failure";
                root.check(root.find(page.item,"searchProblemSummary").visible, "setup failure remains visible on overview");
                Lens.problem = "";
                Lens.status = {locked:true,session_locked:false,models:true};
                root.check(settings.folders.length === 0 && !folders.visible, "lock clears folder paths");
                root.check(settings.datasets.length === 0, "lock clears dataset paths");
                root.check(!root.find(page.item, "lensIndexProgress").visible, "lock hides progress");
                root.check(root.find(page.item, "lensCurrentFile").text === "", "lock clears current filename");
                root.check(root.find(page.item, "lensCurrentFolder").text === "", "lock clears current directory");
                Lens.setupInfo = {installed:true,running:true,stage:"models",progress:{unit:"bytes",done:123,total:null}};
                root.check(!root.find(page.item, "lensSetupProgress").visible, "unknown download size has no fraction");
            } else if (step === 12) {
                page.item.tab = "files";
                Lens.setupInfo = {installed:true,models:true,running:false,stage:"done"};
                Lens.status = {locked:false,models:true,files:93,pending:0,failed:0,config:{roots:[],excludes:[],activity:true,media:true,paused:false}};
            } else if (step === 13) {
                root.check(!root.find(page.item, "lensIndexProgress").visible, "apps alone do not imply folders are 100% indexed");
                root.check(settings.statusDescription.includes("No folders selected"), "empty scope is explicit");
                root.check(root.find(page.item, "lensApplicationCount").text === "Applications: 93 available", "old service's apps-only count is identified");
                root.check(root.find(page.item, "lensAddFolder").visible, "choose a folder directly in the status card");
                root.snapshot("applications-only");
            } else if (step === 14) {
                Lens.status = Object.assign({}, Lens.status, {applications:93,folder_stats:{total:0,pending:0,failed:0}});
                root.check(settings.indexTotal === 0 && !settings.showIndexProgress, "new service also hides empty folder progress");
            } else if (step === 15) {
                Lens.status = {locked:false,models:true,files:4,pending:2,config:{roots:["/home/example/Documents"],source_reviews:[{path:"/home/example/Documents/Projects/llvm-project",files:10000},{path:"/home/example/Documents/Photos/Family album",files:10000}],excludes:[]}};
            } else if (step === 16) {
                root.check(root.find(page.item, "lensSourceReviews").visible, "large folders require a visible choice");
                root.check(root.findAll(page.item, "lensReviewPath").length === 2, "each large folder is identified");
                root.check(root.find(page.item, "lensReviewCount").text.startsWith("At least"), "bounded counts are not presented as exact totals");
                root.check(settings.statusTitle === "Choose which large folders to search", "pending choices are reflected in status");
                root.snapshot("large-folder-choice");
            } else if (step === 17) {
                page.item.tab = "search";
                root.check(root.find(page.item,"searchReviewSummary").visible, "overview preserves pending folder choices");
                root.find(page.item,"searchReviewSummary").clicked();
                root.check(page.item.tab === "files", "review summary opens folder details");
                root.find(page.item, "lensReviewExclude").clicked();
                root.check(Lens.reviewChoices[0].include === false && Lens.reviewChoices[0].path.endsWith("llvm-project"), "exclude targets the displayed folder");
            } else if (step === 18) {
                root.find(page.item, "lensReviewInclude").clicked();
                root.check(Lens.reviewChoices[1].include === true && Lens.reviewChoices[1].path.endsWith("Family album"), "include targets the displayed folder");
            } else if (step === 19) {
                root.check(!root.find(page.item, "lensSourceReviews").visible, "resolved choices leave the page");
            } else if (step === 20) {
                page.item.tab = "indexing";
                Lens.status = {locked:false,models:true,pending:8,files:10,idle:false,on_battery:false,config:{roots:["/home/example/Documents"],source_reviews:[],excludes:[],fast_indexing:false}};
            } else if (step === 21) {
                root.check(settings.statusTitle === "Waiting for idle time", "normal indexing explains why it is waiting");
                page.item.tab = "indexing";
                const fast = root.find(page.item, "lensFastIndexing");
                root.check(fast.visible && !fast.checked, "fast mode is opt in");
                fast.clicked();
                root.check(Lens.status.config.fast_indexing === true && fast.checked, "fast indexing switch saves and displays its setting");
                root.check(settings.statusTitle === "Fast indexing is running", "fast mode does not claim to wait for idle");
            } else if (step === 22) {
                root.check(root.find(page.item, "lensFastIndexing").checked, "fast switch stays enabled after bindings settle");
                root.snapshot("fast-indexing");
            } else if (step === 23) {
                Lens.status = Object.assign({}, Lens.status, {on_battery:true});
                root.check(settings.statusTitle === "Waiting for external power", "battery still pauses fast mode");
                Lens.status = Object.assign({}, Lens.status, {on_battery:false,config:Object.assign({}, Lens.status.config, {paused:true})});
                root.check(settings.statusTitle === "Indexing is paused", "manual pause still applies");
                Lens.status = Object.assign({}, Lens.status, {config:Object.assign({}, Lens.status.config, {paused:false})});
                root.find(page.item, "lensFastIndexing").clicked();
                root.check(Lens.status.config.fast_indexing === false && settings.statusTitle === "Waiting for idle time", "switching back restores normal status");
            } else if (step === 24) {
                root.find(page.item, "lensAllIn").clicked();
                root.check(Lens.status.config.all_in === true && settings.statusTitle === "All in indexing is running", "All in works independently of the fast checkbox");
                root.check(!root.find(page.item, "lensFastIndexing").enabled, "All in takes precedence over fast mode");
                root.check(root.find(page.item, "lensAllIn").title === "Stop All in", "All in has a clear stop action");
            } else if (step === 25) {
                root.snapshot("all-in");
            } else if (step === 26) {
                root.find(page.item, "lensAllIn").clicked();
                root.check(Lens.status.config.all_in === false && settings.statusTitle === "Waiting for idle time", "stopping All in returns to the previous normal mode");
                root.find(page.item, "lensFastIndexing").clicked();
                root.find(page.item, "lensAllIn").clicked();
                root.find(page.item, "lensAllIn").clicked();
                root.check(Lens.status.config.fast_indexing === true && settings.statusTitle === "Fast indexing is running", "All in also preserves a previous fast-mode choice");
            } else if (step === 27) {
                console.log(root.failed ? "DRIVER_FAIL" : "DRIVER_PASS");
                Qt.exit(0);
            }
            step++;
        }
    }
}
'''.replace('ARTIFACTS', json.dumps(artifacts))
        output = self.run_driver(driver, service_overrides={'Lens.qml': stub})
        self.assertIn('DRIVER_PASS', output, output[-6000:])
        self.assertNotIn('CHECK_FAIL', output)
        self.assert_clean(output)

    def test_wifi_connections_and_editor_pages(self):
        output = self.run_driver(DRIVER)
        self.assertIn('DRIVER_PASS', output, output[-4000:])
        self.assertNotIn('CHECK_FAIL', output)
        self.assert_clean(output)

    def test_wifi_deep_link_stays_on_wifi_after_bluetooth_preloads(self):
        # The full settings window supplies pageShown only after a background page has been built.
        # A stand-alone page loader cannot catch navigation triggered during that construction.
        probe = r'''
    Timer {
        property int settled: 0
        property int stage: 0
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            const devicePage = root.pageItemAt(root.pageIndex("bluetooth-device"));
            if (!devicePage || !ConnectivityBackend.ready) return;
            if (++settled < 3) return;
            if (stage === 0) {
                const stayed = root.currentPageData.key === "wifi" && !devicePage.pageShown;
                if (!stayed) {
                    console.log("DRIVER_FAIL unexpected page: " + root.currentPageData.key);
                    Qt.quit();
                    return;
                }
                stage = 1;
                settled = 0;
                root.openPage("bluetooth-device");
                return;
            }
            console.log(root.currentPageData.key === "bluetooth" ? "DRIVER_PASS" : "DRIVER_FAIL missing-device page did not return to Bluetooth");
            Qt.quit();
        }
    }
    Timer {
        interval: 20000
        running: true
        onTriggered: {
            console.log("DRIVER_FAIL background pages did not finish loading");
            Qt.quit();
        }
    }
'''
        driver = (SHELL / 'settings.qml').read_text().replace('    id: root\n', '    id: root\n' + probe, 1)
        output = self.run_driver(driver, settings_page='wifi')
        self.assertIn('DRIVER_PASS', output, output[-5000:])
        self.assertNotIn('DRIVER_FAIL', output)


if __name__ == '__main__':
    unittest.main()
