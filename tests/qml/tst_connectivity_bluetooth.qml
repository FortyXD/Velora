import QtQuick
import QtTest

Item {
    SignalSpy { id: pageSignal; target: BluetoothManager; signalName: "openDevicePage" }

    TestCase {
        name: "Bluetooth"

        function lastCall() {
            return ConnectivityBackend.calls[ConnectivityBackend.calls.length - 1];
        }

        function device(path, extra) {
            return Object.assign({ path, name: path, address: "00:00:00:00:00:01", paired: true, connected: false, deviceType: "phone" }, extra ?? {});
        }

        function init() {
            ConnectivityBackend.calls = [];
            ConnectivityBackend.bluetooth = ({ available: true, powered: true, adapters: [{ path: "/a", name: "laptop" }, { path: "/b", name: "other" }], saved: [device("/d/1", { connected: true }), device("/d/2")], nearby: [device("/d/3", { paired: false })] });
            BluetoothManager.selectedAdapter = "";
            BluetoothManager.selectedDevice = "";
            BluetoothManager.busy = ({});
            BluetoothManager.errors = ({});
            BluetoothManager.sendingTo = "";
            BluetoothManager.sendError = "";
            ConnectivityPrompts.queue = [];
            pageSignal.clear();
        }

        function test_state_reads_through() {
            verify(BluetoothManager.available && BluetoothManager.powered);
            compare(BluetoothManager.connected.map(item => item.path), ["/d/1"]);
            compare(BluetoothManager.deviceByPath["/d/3"].paired, false);
            ConnectivityBackend.bluetooth = ({});
            verify(!BluetoothManager.available);
            compare(BluetoothManager.saved.length, 0);
            compare(BluetoothManager.adapter, null);
        }

        function test_the_first_adapter_unless_another_is_chosen() {
            compare(BluetoothManager.adapter.path, "/a");
            BluetoothManager.selectedAdapter = "/b";
            compare(BluetoothManager.adapter.path, "/b");
            BluetoothManager.setDiscoverable(true);
            compare(lastCall().params.adapter, "/b");
            BluetoothManager.selectedAdapter = "/gone";
            compare(BluetoothManager.adapter.path, "/a");
        }

        function test_a_device_page_follows_the_selection() {
            BluetoothManager.showDevice("/d/2");
            compare(pageSignal.count, 1);
            compare(BluetoothManager.device.path, "/d/2");
            ConnectivityBackend.bluetooth = ({ available: true, saved: [], nearby: [] });
            compare(BluetoothManager.device, null);
        }

        function test_a_request_shows_as_busy_and_its_failure_stays_on_the_device() {
            let finished = null;
            BluetoothManager.pair("/d/3", error => finished = error);
            compare(lastCall().method, "bluetooth.pair");
            compare(lastCall().params.device, "/d/3");
            verify(BluetoothManager.busy["/d/3"]);
            lastCall().done(null, { code: "wrong_secret", message: "The device refused the pairing" });
            verify(!BluetoothManager.busy["/d/3"]);
            compare(BluetoothManager.errors["/d/3"], "The device refused the pairing");
            compare(finished.code, "wrong_secret");
            // A new try clears it
            BluetoothManager.pair("/d/3", null);
            compare(BluetoothManager.errors["/d/3"], undefined);
        }

        function test_canceling_isnt_an_error_to_show() {
            BluetoothManager.pair("/d/3", null);
            lastCall().done(null, { code: "canceled", message: "canceled" });
            compare(BluetoothManager.errors["/d/3"], undefined);
        }

        function test_requests_carry_what_they_need() {
            BluetoothManager.connectDevice("/d/2");
            compare(lastCall().method, "bluetooth.connect");
            BluetoothManager.disconnectDevice("/d/2");
            compare(lastCall().method, "bluetooth.disconnect");
            BluetoothManager.setTrusted("/d/2", true);
            compare(lastCall().params.value, true);
            BluetoothManager.setBlocked("/d/2", false);
            compare(lastCall().method, "bluetooth.setBlocked");
            BluetoothManager.rename("/d/2", "New");
            compare(lastCall().params.name, "New");
            BluetoothManager.forget("/d/2");
            compare(lastCall().method, "bluetooth.forget");
            BluetoothManager.cancelPairing("/d/2");
            compare(lastCall().method, "bluetooth.cancelPairing");
            BluetoothManager.setEnabled(false);
            compare(lastCall().params.enabled, false);
            BluetoothManager.setDiscovering(true);
            compare(lastCall().method, "bluetooth.setDiscovering");
            BluetoothManager.setDiscoverableTimeout(60);
            compare(lastCall().params.seconds, 60);
            BluetoothManager.setAdapterName("desk");
            compare(lastCall().params.name, "desk");
            const count = ConnectivityBackend.calls.length;
            BluetoothManager.setAdapterName("");
            compare(ConnectivityBackend.calls.length, count, "no empty name");
        }

        function test_sending_files_reports_its_progress() {
            BluetoothManager.sendFiles("AA", ["/x/a.txt"]);
            compare(BluetoothManager.sendingTo, "AA");
            ConnectivityBackend.event("transferStarted", { name: "/x/a.txt", size: 100 });
            compare(BluetoothManager.sendingName, "a.txt");
            ConnectivityBackend.event("transferProgress", { transferred: 50 });
            compare(BluetoothManager.sendingDone, 50);
            lastCall().done(null, { code: "failed", message: "The device didn't take the file" });
            compare(BluetoothManager.sendingTo, "");
            compare(BluetoothManager.sendError, "The device didn't take the file");
        }

        function test_every_device_type_has_a_symbol_and_a_name() {
            for (const type of ["phone", "modem", "computer", "network", "headset", "headphones", "audio", "keyboard", "mouse", "joypad", "tablet", "camera", "printer", "imaging", "display", "wearable", "toy", "health"]) {
                verify(BluetoothManager.typeSymbol(type) !== "bluetooth", type);
                verify(BluetoothManager.typeLabel(type) !== "Device", type);
            }
            compare(BluetoothManager.typeSymbol("unknown"), "bluetooth");
            compare(BluetoothManager.typeLabel("unknown"), "Device");
        }

        function ask(data) {
            ConnectivityBackend.event("prompt", data);
        }

        function test_questions_come_one_at_a_time() {
            compare(ConnectivityPrompts.current, null);
            ask({ id: 1, kind: "bluetooth-pin", deviceName: "Kb" });
            ask({ id: 2, kind: "bluetooth-confirm", deviceName: "Ph", code: "000042" });
            compare(ConnectivityPrompts.current.id, 1);
            ConnectivityPrompts.answer(true, { pin: "1234" });
            compare(lastCall().method, "prompt.answer");
            compare(lastCall().params.id, 1);
            compare(lastCall().params.accepted, true);
            compare(lastCall().params.values.pin, "1234");
            compare(ConnectivityPrompts.current.id, 2);
            compare(ConnectivityPrompts.code, "000042");
            ConnectivityPrompts.answer(false);
            compare(lastCall().params.accepted, false);
            compare(ConnectivityPrompts.current, null);
        }

        function test_a_question_taken_back_goes_away() {
            ask({ id: 1, kind: "bluetooth-pin", deviceName: "Kb" });
            ask({ id: 2, kind: "bluetooth-pin", deviceName: "Ph" });
            ConnectivityBackend.event("promptWithdrawn", { id: 1 });
            compare(ConnectivityPrompts.current.id, 2);
            compare(ConnectivityBackend.calls.length, 0, "nothing to answer to");
        }

        function test_the_daemon_going_away_clears_them() {
            ask({ id: 1, kind: "bluetooth-pin", deviceName: "Kb" });
            ConnectivityBackend.ready = false;
            compare(ConnectivityPrompts.current, null);
            ConnectivityBackend.ready = true;
        }

        function test_a_shown_code_needs_no_answer() {
            ask({ id: 1, kind: "bluetooth-show-code", deviceName: "Kb", code: "000007" });
            verify(ConnectivityPrompts.isNote);
            compare(ConnectivityPrompts.fields.length, 0);
            ConnectivityPrompts.answer(false);
            compare(ConnectivityBackend.calls.length, 0);
        }

        function test_a_password_question_names_its_fields() {
            ask({ id: 1, kind: "secrets", connectionName: "Home", connectionType: "802-11-wireless", fields: ["psk"], message: "", retry: false });
            compare(ConnectivityPrompts.fields[0].label, "Password");
            verify(ConnectivityPrompts.fields[0].hidden);
            compare(ConnectivityPrompts.symbol, "wifi_password");
            verify(ConnectivityPrompts.title.indexOf("Home") >= 0);
            verify(ConnectivityPrompts.title.indexOf("needs") >= 0);
        }

        function test_a_retry_says_so() {
            ask({ id: 1, kind: "secrets", connectionName: "Home", connectionType: "802-11-wireless", fields: ["psk"], message: "", retry: true });
            verify(ConnectivityPrompts.title.indexOf("didn't accept") >= 0);
        }

        function test_a_vpn_code_shows_the_servers_words_in_the_open() {
            ask({ id: 1, kind: "secrets", connectionName: "Work", connectionType: "vpn", fields: ["challenge-response"], message: "Enter your code", retry: false });
            compare(ConnectivityPrompts.message, "Enter your code");
            compare(ConnectivityPrompts.fields[0].label, "Code");
            verify(!ConnectivityPrompts.fields[0].hidden);
            compare(ConnectivityPrompts.symbol, "vpn_key");
        }

        function test_each_kind_has_words() {
            for (const kind of ["bluetooth-pin", "bluetooth-passkey", "bluetooth-confirm", "bluetooth-show-code", "bluetooth-authorize", "bluetooth-service", "bluetooth-file"]) {
                ConnectivityPrompts.queue = [{ id: 1, kind, deviceName: "X", code: "1", fileName: "f", fileSize: 1, folder: "/d" }];
                verify(ConnectivityPrompts.title.length > 0, kind);
                verify(ConnectivityPrompts.message.length > 0, kind);
                verify(ConnectivityPrompts.acceptText.length > 0, kind);
                verify(ConnectivityPrompts.declineText.length > 0, kind);
            }
        }

        function test_a_file_offer_says_what_and_where() {
            ask({ id: 1, kind: "bluetooth-file", deviceName: "Ph", fileName: "a.jpg", fileSize: 2097152, folder: "/home/me/Downloads" });
            verify(ConnectivityPrompts.message.indexOf("a.jpg") >= 0);
            verify(ConnectivityPrompts.message.indexOf("2.0 MB") >= 0);
            verify(ConnectivityPrompts.message.indexOf("/home/me/Downloads") >= 0);
            compare(ConnectivityPrompts.acceptText, "Accept");
            compare(ConnectivityPrompts.sizeText(10), "10 bytes");
            compare(ConnectivityPrompts.sizeText(2048), "2 KB");
        }
    }
}
