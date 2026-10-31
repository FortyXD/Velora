import QtQuick
import QtQuick.Controls
import QtTest

Item {
    width: 800
    height: 200
    PasswordForm { id: form; width: 780; focusOnShow: false }
    SignalSpy { id: accepted; target: form; signalName: "accepted" }
    SignalSpy { id: canceled; target: form; signalName: "canceled" }

    TestCase {
        name: "WifiPasswordForm"
        when: windowShown
        function field() { return findChild(form, "wifiPasswordField"); }
        function reveal() { return findChild(form, "wifiRevealButton"); }
        function init() {
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
    }
}
