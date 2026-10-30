import QtQuick
import QtQuick.Controls
import QtTest
import "modules/settings/network"

Item {
    width: 700
    height: 180
    PasswordForm {
        id: form
        width: 680
        property string submitted: ""
        property int cancels: 0
        onAccepted: password => { submitted = password; busy = true; }
        onCanceled: cancels++
    }
    TestCase {
        name: "WifiPasswordForm"
        when: windowShown
        function test_keyboard_reveal_retry_clear_cancel() {
            const field = findChild(form, "wifiPasswordField");
            const reveal = findChild(form, "wifiRevealButton");
            const cancel = findChild(form, "wifiCancelButton");
            verify(field !== null && reveal !== null && cancel !== null);
            field.forceActiveFocus();
            tryCompare(field, "activeFocus", true);
            field.text = "  credential-sentinel-я  ";
            mouseClick(reveal);
            compare(field.echoMode, TextInput.Normal);
            field.forceActiveFocus();
            keyClick(Qt.Key_Return);
            compare(form.submitted, "  credential-sentinel-я  ");
            compare(form.text, "");
            compare(reveal.toggled, false);
            tryCompare(cancel, "activeFocus", true);
            keyClick(Qt.Key_Escape);
            compare(form.cancels, 1);
            form.busy = false;
            form.promptToken = "retry-2";
            tryCompare(field, "activeFocus", true);
            compare(field.echoMode, TextInput.Password);
            field.text = "never-retain-this";
            keyClick(Qt.Key_Escape);
            compare(form.cancels, 2);
            compare(form.text, "");
            field.text = "discard-on-hide";
            form.visible = false;
            compare(form.text, "");
        }
    }
}
