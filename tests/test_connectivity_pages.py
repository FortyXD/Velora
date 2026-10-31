"""The real settings pages, in the real shell runtime, with the real daemon and a stand-in NetworkManager on a
private bus. It catches what stand-in widgets can't: a type that won't load, a property clash, a broken binding."""
import os
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
                     r'WlrLayershell|wlr-layer|Wayland|wayland|Polkit|polkit|PipeWire|pipewire|UPower|upower|logind|persistent states', re.I)

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


@unittest.skipUnless((QS and CARGO and DBUS) or REQUIRED, 'needs qs, cargo and dbus-daemon')
class SettingsPagesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        target = TOOLS / 'target'
        subprocess.run([CARGO, 'build', '--quiet', '--manifest-path', str(TOOLS / 'Cargo.toml'),
                        '-p', 'velora-connectivityd', '-p', 'velora-connectivity-fakes'], check=True, timeout=400)
        cls.daemon = target / 'debug/velora-connectivityd'
        cls.fakes = target / 'debug/velora-connectivity-fakes'

    def run_driver(self, driver, *, settings_page=None):
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
            (shell / 'shell.qml').write_text(driver)
            home = root / 'home'
            home.mkdir()
            # Programs that act on this computer are stood in for
            tools = root / 'tools'
            tools.mkdir()
            for name in ('rfkill', 'hyprctl', 'notify-send', 'wl-copy', 'nmcli', 'systemctl', 'qrencode'):
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
                               'QT_QPA_PLATFORM': 'offscreen', 'QT_QUICK_BACKEND': 'software', 'FONTCONFIG_FILE': '/etc/fonts/fonts.conf'}
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
                bus.kill()
                bus.wait()
        return output

    def assert_clean(self, output):
        problems = [line for line in output.splitlines()
                    if PROBLEMS.search(line) and not IGNORED.search(line) and 'CHECK_' not in line]
        self.assertEqual(problems, [], output[-4000:])

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
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            const devicePage = root.pageItemAt(root.pageIndex("bluetooth-device"));
            if (!devicePage || !ConnectivityBackend.ready) return;
            if (++settled < 3) return;
            const stayed = root.currentPageData.key === "wifi" && !devicePage.pageShown;
            console.log(stayed ? "DRIVER_PASS" : "DRIVER_FAIL unexpected page: " + root.currentPageData.key);
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
