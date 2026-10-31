import QtQuick
import QtTest

Item {
    TestCase {
        name: "Network"

        function ap(ssid, extra) {
            return Object.assign({
                ssid, bssid: "00:00:00:00:00:01", strength: 60, frequency: 5180, active: false, security: "WPA2",
                securityType: "wpa-psk", savedUuid: "", savedCredentials: false, neverUsed: false,
                device: "/dev/wifi", accessPoint: "/ap/" + ssid
            }, extra ?? {});
        }

        function publish(state) {
            ConnectivityBackend.network = Object.assign({ available: true, wifiEnabled: true, wifiStatus: "disconnected", connectivity: "full", networks: [], profiles: [], activeConnections: [] }, state ?? {});
        }

        function network(ssid) {
            return Network.wifiNetworks.find(item => item.ssid === ssid);
        }

        function lastCall() {
            return ConnectivityBackend.calls[ConnectivityBackend.calls.length - 1];
        }

        function init() {
            Network.connectionPending = false;
            Network.wifiConnectSsid = "";
            Network.passwordPromptSsid = "";
            Network.credentialErrorSsid = "";
            Network.wifiErrorMessage = "";
            ConnectivityBackend.problem = "";
            publish();
            ConnectivityBackend.calls = [];
        }

        function test_state_reads_through() {
            publish({ wifiConnected: true, ethernetConnected: true, wifiScanning: true, wifiStatus: "limited", connectivity: "portal" });
            verify(Network.available && Network.wifi && Network.ethernet && Network.wifiScanning);
            compare(Network.wifiStatus, "limited");
            compare(Network.connectivity, "portal");
            ConnectivityBackend.network = ({});
            verify(!Network.available && !Network.wifiEnabled);
            compare(Network.wifiStatus, "disconnected");
        }

        function test_network_objects_survive_updates_and_go_when_the_network_does() {
            publish({ networks: [ap("Home", { strength: 40 })] });
            const home = network("Home");
            home.askingPassword = true;
            publish({ networks: [ap("Home", { strength: 90 }), ap("Cafe")] });
            verify(network("Home") === home, "the same object, keeping what the row was doing");
            verify(home.askingPassword);
            compare(home.strength, 90);
            compare(Network.wifiNetworks.length, 2);
            publish({ networks: [ap("Cafe")] });
            verify(network("Home") === undefined);
        }

        function test_the_friendly_order_is_active_saved_then_by_signal() {
            publish({ networks: [
                ap("New", { strength: 95 }),
                ap("Saved", { strength: 30, savedUuid: "u" }),
                ap("Here", { strength: 10, active: true, savedUuid: "h" }),
            ] });
            compare(Network.friendlyWifiNetworks.map(item => item.ssid), ["Here", "Saved", "New"]);
            compare(Network.active.ssid, "Here");
            compare(Network.networkStrength, 10);
        }

        function test_saved_lists_come_from_profiles() {
            publish({
                networks: [ap("Near", { savedUuid: "n" })],
                profiles: [
                    { connectionType: "802-11-wireless", ssid: "Near", uuid: "n" },
                    { connectionType: "802-11-wireless", ssid: "Far", uuid: "f" },
                    { connectionType: "vpn", ssid: "", uuid: "v" },
                ],
            });
            compare(Network.savedNetworks.length, 2);
            compare(Network.savedOutOfRange.map(item => item.uuid), ["f"]);
        }

        function test_details_keep_the_shape_the_page_reads() {
            publish({ wifiDetails: { interface: "wlan0", ip4: { addresses: ["10.0.0.2/24"], gateway: "10.0.0.1", dns: ["1.1.1.1"] } } });
            compare(Network.wifiDetails.ip, "10.0.0.2/24");
            compare(Network.wifiDetails.gateway, "10.0.0.1");
            compare(Network.wifiDetails.dns[0], "1.1.1.1");
            compare(Network.wifiDetails.device, "wlan0");
            compare(Network.ethernetDetails.ip, undefined);
        }

        function test_a_new_secure_network_asks_first_and_sends_nothing() {
            publish({ networks: [ap("Home")] });
            Network.connectToWifiNetwork(network("Home"));
            verify(network("Home").askingPassword);
            compare(Network.passwordPromptSsid, "Home");
            verify(!Network.connectionPending);
            compare(ConnectivityBackend.calls.length, 0);
        }

        function test_a_saved_network_activates_its_profile() {
            publish({ networks: [ap("Home", { savedUuid: "u" })] });
            Network.connectToWifiNetwork(network("Home"));
            compare(lastCall().method, "network.activate");
            compare(lastCall().params.uuid, "u");
            verify(Network.connectionPending);
            compare(Network.wifiConnectSsid, "Home");
            verify(Network.wifiConnecting);
        }

        function test_an_open_network_joins_directly() {
            publish({ networks: [ap("Cafe", { security: "", securityType: "none" })] });
            Network.connectToWifiNetwork(network("Cafe"));
            compare(lastCall().method, "network.join");
            compare(lastCall().params.ssid, "Cafe");
            compare(lastCall().params.bssid, "00:00:00:00:00:01");
        }

        function test_nothing_starts_while_off_busy_or_already_connected() {
            publish({ networks: [ap("Here", { active: true, savedUuid: "h" }), ap("Other", { savedUuid: "o" })] });
            Network.connectToWifiNetwork(network("Here"));
            compare(ConnectivityBackend.calls.length, 0);
            Network.connectionPending = true;
            Network.connectToWifiNetwork(network("Other"));
            compare(ConnectivityBackend.calls.length, 0);
            Network.connectionPending = false;
            publish({ wifiEnabled: false, networks: [ap("Other", { savedUuid: "o" })] });
            ConnectivityBackend.calls = [];
            Network.connectToWifiNetwork(network("Other"));
            compare(ConnectivityBackend.calls.length, 0);
        }

        function test_success_clears_everything() {
            publish({ networks: [ap("Home", { savedUuid: "u" })] });
            Network.connectToWifiNetwork(network("Home"));
            lastCall().done({ active: "/a/1" }, null);
            verify(!Network.connectionPending);
            compare(Network.wifiConnectSsid, "");
            compare(Network.wifiErrorMessage, "");
        }

        function test_a_refused_new_password_asks_again() {
            publish({ networks: [ap("Home")] });
            Network.changePassword(network("Home"), "typed");
            compare(lastCall().method, "network.join");
            compare(lastCall().params.password, "typed");
            lastCall().done(null, { code: "wrong_secret", message: "refused" });
            verify(network("Home").askingPassword);
            compare(Network.passwordPromptSsid, "Home");
            compare(network("Home").errorText, "Password rejected. Try again.");
            verify(!Network.connectionPending);
        }

        function test_a_refused_saved_password_offers_to_update_it() {
            publish({ networks: [ap("Home", { savedUuid: "u" })] });
            Network.connectToWifiNetwork(network("Home"));
            lastCall().done(null, { code: "secrets_required", message: "none" });
            compare(Network.credentialErrorSsid, "Home");
            verify(!network("Home").askingPassword);
            Network.requestPasswordUpdate();
            verify(network("Home").askingPassword);
            compare(Network.credentialErrorSsid, "");
            Network.cancelPasswordPrompt();
            verify(!network("Home").askingPassword);
            compare(Network.passwordPromptSsid, "");
        }

        function test_other_failures_show_their_message() {
            publish({ networks: [ap("Home", { savedUuid: "u" })] });
            Network.connectToWifiNetwork(network("Home"));
            lastCall().done(null, { code: "failed", message: "DHCP failed" });
            compare(Network.wifiErrorMessage, "DHCP failed");
            compare(network("Home").errorText, "DHCP failed");
            compare(Network.credentialErrorSsid, "");
        }

        function test_changing_a_used_profiles_password_keeps_the_profile() {
            publish({ networks: [ap("Home", { savedUuid: "u" })] });
            Network.changePassword(network("Home"), "new");
            compare(lastCall().method, "network.changePassword");
            compare(lastCall().params.uuid, "u");
            compare(lastCall().params.password, "new");
        }

        function test_a_profile_that_never_connected_starts_over() {
            publish({ networks: [ap("Home", { savedUuid: "u", neverUsed: true })] });
            verify(!network("Home").known);
            Network.changePassword(network("Home"), "new");
            compare(lastCall().method, "network.forget");
            lastCall().done(null, null);
            compare(lastCall().method, "network.join");
            compare(lastCall().params.password, "new");
        }

        function test_a_failed_removal_doesnt_join() {
            publish({ networks: [ap("Home", { savedUuid: "u", neverUsed: true })] });
            Network.changePassword(network("Home"), "new");
            const forget = lastCall();
            forget.done(null, { code: "permission_denied", message: "no" });
            compare(lastCall(), forget);
            compare(Network.wifiErrorMessage, "no");
            verify(!Network.connectionPending);
        }

        function test_an_empty_password_goes_nowhere() {
            publish({ networks: [ap("Home")] });
            Network.changePassword(network("Home"), "");
            compare(ConnectivityBackend.calls.length, 0);
        }

        function test_hidden_and_qr_joins() {
            Network.connectToHiddenNetwork("Ghost", "secret");
            compare(lastCall().method, "network.join");
            verify(lastCall().params.hidden);
            lastCall().done(null, null);
            Network.joinNetwork("Shared", "secret");
            compare(lastCall().params.ssid, "Shared");
            verify(!lastCall().params.hidden);
        }

        function test_disconnect_stops_the_wifi_connection_only() {
            publish({ activeConnections: [
                { connectionType: "802-3-ethernet", uuid: "cable" },
                { connectionType: "802-11-wireless", uuid: "wifi" },
            ] });
            Network.disconnectWifiNetwork();
            compare(lastCall().method, "network.deactivate");
            compare(lastCall().params.uuid, "wifi");
            publish({ activeConnections: [{ connectionType: "802-3-ethernet", uuid: "cable" }] });
            ConnectivityBackend.calls = [];
            Network.disconnectWifiNetwork();
            compare(ConnectivityBackend.calls.length, 0);
        }

        function test_forget_needs_a_profile() {
            Network.forgetWifiNetwork("");
            compare(ConnectivityBackend.calls.length, 0);
            Network.forgetWifiNetwork("u");
            compare(lastCall().method, "network.forget");
        }

        function test_the_switch_and_scans() {
            Network.enableWifi(false);
            compare(lastCall().method, "network.setWifiEnabled");
            compare(lastCall().params.enabled, false);
            Network.toggleWifi();
            compare(lastCall().params.enabled, false);
            Network.rescanWifi(true);
            compare(lastCall().method, "network.scan");
            verify(lastCall().params.force);
            publish({ wifiEnabled: false });
            ConnectivityBackend.calls = [];
            Network.rescanWifi();
            compare(ConnectivityBackend.calls.length, 0);
        }

        function test_airplane_mode_goes_through_the_daemon() {
            publish({ airplaneMode: true });
            verify(Network.airplaneMode);
            Network.setAirplaneMode(false);
            compare(lastCall().method, "network.setAirplaneMode");
            compare(lastCall().params.enabled, false);
        }

        function test_turning_wifi_on_looks_for_networks() {
            publish({ wifiEnabled: false });
            ConnectivityBackend.calls = [];
            publish({ wifiEnabled: true });
            compare(lastCall().method, "network.scan");
            verify(lastCall().params.force);
        }

        function test_service_problems_have_a_message() {
            compare(Network.snapshotError, "");
            ConnectivityBackend.problem = "missing";
            verify(Network.snapshotError.indexOf("isn't installed") >= 0);
            ConnectivityBackend.problem = "version";
            verify(Network.snapshotError.indexOf("out of date") >= 0);
            ConnectivityBackend.problem = "crashed";
            verify(Network.snapshotError.indexOf("stopped") >= 0);
        }

        function test_the_icon_follows_the_state() {
            publish({ ethernetConnected: true });
            compare(Network.materialSymbol, "lan");
            publish({ wifiEnabled: false });
            compare(Network.materialSymbol, "signal_wifi_off");
            publish({ wifiStatus: "connecting" });
            compare(Network.materialSymbol, "wifi");
            publish({ wifiStatus: "connected", networks: [ap("Here", { active: true, strength: 90 })] });
            compare(Network.materialSymbol, "signal_wifi_4_bar");
            publish({ wifiStatus: "limited" });
            compare(Network.materialSymbol, "signal_wifi_bad");
            publish({ wifiStatus: "disconnected" });
            compare(Network.materialSymbol, "wifi_find");
        }

        function test_small_helpers() {
            compare(Network.strengthSymbol(90), "signal_wifi_4_bar");
            compare(Network.strengthSymbol(10), "signal_wifi_0_bar");
            compare(Network.frequencyBand(2412), "2.4 GHz");
            compare(Network.frequencyBand(5180), "5 GHz");
            compare(Network.frequencyBand(5955), "6 GHz");
            compare(Network.frequencyBand(0), "");
        }
    }
}
