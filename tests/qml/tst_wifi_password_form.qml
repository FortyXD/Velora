import QtQuick
import QtQuick.Controls
import QtTest

Item {
    width: 800
    height: 200
    PasswordForm { id: form; width: 780; focusOnShow: false }
    SavedPasswordBox { id: saved; y: 100; width: 360; uuid: "first" }
    SignalSpy { id: accepted; target: form; signalName: "accepted" }
    SignalSpy { id: canceled; target: form; signalName: "canceled" }

    TestCase {
        name: "WifiPasswordForm"
        when: windowShown
        function field() { return findChild(form, "wifiPasswordField"); }
        function reveal() { return findChild(form, "wifiRevealButton"); }
        function init() {
            form.width = 780;
            form.visible = true;
            form.enabled = true;
            form.busy = false;
            form.allowEmpty = false;
            form.clear();
            wait(0);
            accepted.clear();
            canceled.clear();
        }
        function typePassword() {
            field().text = "private-password";
            reveal().toggled = true;
            compare(field().echoMode, TextInput.Normal);
        }
        function checkCleared() {
            compare(field().text, "");
            verify(!reveal().toggled);
            compare(field().echoMode, TextInput.Password);
        }
        function test_submit_clears_before_emitting() {
            typePassword();
            form.submit();
            compare(accepted.count, 1);
            compare(accepted.signalArguments[0][0], "private-password");
            checkCleared();
        }
        function test_hiding_and_collapsing_clear() {
            typePassword();
            form.visible = false;
            checkCleared();
            form.visible = true;
            typePassword();
            form.enabled = false;
            checkCleared();
        }
        function test_cancel_clears() {
            typePassword();
            form.cancel();
            checkCleared();
            compare(canceled.count, 1);
        }
        function test_waiting_clears_and_stops_submission() {
            typePassword();
            form.busy = true;
            tryCompare(field(), "text", "");
            checkCleared();
            verify(!field().enabled);
            compare(form.cancelText, "Stop waiting");
            form.submit();
            compare(accepted.count, 0);
            form.cancel();
            compare(canceled.count, 1);
        }
        function test_empty_password_is_only_allowed_for_open_networks() {
            form.submit();
            compare(accepted.count, 0);
            form.allowEmpty = true;
            form.submit();
            compare(accepted.count, 1);
            compare(accepted.signalArguments[0][0], "");
        }

        function test_controls_reflow_without_losing_input() {
            const cancel = findChild(form, "wifiCancelButton");
            field().text = "still editing";
            form.width = 250;
            tryVerify(() => field().width === form.width && cancel.y >= field().height);
            form.width = 780;
            tryVerify(() => cancel.x >= field().width);
            compare(field().text, "still editing");
        }

        function test_saved_box_rejects_obsolete_replies() {
            function pending() { return ConnectivityBackend.calls[ConnectivityBackend.calls.length - 1]; }
            saved.toggleReveal();
            const read = pending();
            saved.clear();
            saved.toggleQr();
            const qr = pending();
            read.done({ secrets: [{ section: "802-11-wireless-security", key: "psk", value: "old" }] }, null);
            compare(saved.revealed, "");
            verify(saved.busy);
            saved.uuid = "second";
            qr.done({ image: "obsolete" }, null);
            compare(saved.qrImage, "");
            verify(!saved.busy);
            saved.copy();
            const copy = pending();
            saved.visible = false;
            saved.visible = true;
            copy.done(null, { message: "Old copy request" });
            compare(saved.errorText, "");
            saved.toggleReveal();
            compare(pending().params.uuid, "second");
            pending().done({ secrets: [{ section: "802-11-wireless-security", key: "psk", value: "current" }] }, null);
            compare(saved.revealed, "current");
            saved.clear();
        }
    }
}
