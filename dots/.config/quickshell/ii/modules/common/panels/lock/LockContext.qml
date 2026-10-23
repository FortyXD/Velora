import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam

Scope {
    id: root

    enum ActionEnum { Unlock, Poweroff, Reboot }

    signal shouldReFocus()
    signal unlocked(targetAction: var)
    signal failed()

    // These properties are in the context and not individual lock surfaces
    // so all surfaces can share the same state.
    property string currentText: ""
    property bool unlockInProgress: false
    property bool showFailure: false
    property bool fingerprintsConfigured: false
    property var targetAction: LockContext.ActionEnum.Unlock
    property bool alsoInhibitIdle: false

    // The password is hidden, so say when what's being typed can't be right
    property bool capsLock: false
    property bool nonLatinInput: false
    property string pamNotice: "" // e.g. the account being locked after too many failed attempts

    function resetTargetAction() {
        root.targetAction = LockContext.ActionEnum.Unlock;
    }

    function clearText() {
        root.currentText = "";
    }

    function resetClearTimer() {
        passwordClearTimer.restart();
    }

    function reset() {
        root.resetTargetAction();
        root.clearText();
        root.unlockInProgress = false;
        root.nonLatinInput = false;
        stopFingerPam();
    }

    function noteTypedKey(event) {
        if (event.key === Qt.Key_CapsLock) {
            keyboardStateTimer.restart(); // The LED state flips after this event
            return;
        }
        const text = event.text;
        if (!text || text.length !== 1 || text.toLowerCase() === text.toUpperCase()) return; // Only letters tell anything
        root.nonLatinInput = !/[A-Za-z]/.test(text);
        const upper = text !== text.toLowerCase();
        const shift = (event.modifiers & Qt.ShiftModifier) !== 0;
        root.capsLock = upper !== shift;
    }

    function refreshKeyboardState() {
        keyboardStateProc.running = true;
    }

    Timer {
        id: keyboardStateTimer
        interval: 100
        onTriggered: root.refreshKeyboardState()
    }

    Process {
        id: keyboardStateProc
        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector {
            id: keyboardStateCollector
            onStreamFinished: {
                try {
                    const keyboard = HyprlandXkb.typingKeyboard(JSON.parse(keyboardStateCollector.text).keyboards);
                    root.capsLock = keyboard?.capsLock ?? false;
                } catch (e) {
                    root.capsLock = false;
                }
            }
        }
    }

    Timer {
        id: passwordClearTimer
        interval: Math.max(3, Config.options.lock.clearPasswordAfter) * 1000
        onTriggered: {
            root.reset();
        }
    }

    onCurrentTextChanged: {
        if (currentText.length > 0) {
            showFailure = false;
            GlobalStates.screenUnlockFailed = false;
        }
        GlobalStates.screenLockContainsCharacters = currentText.length > 0;
        passwordClearTimer.restart();
    }

    function tryUnlock(alsoInhibitIdle = false) {
        root.alsoInhibitIdle = alsoInhibitIdle;
        root.unlockInProgress = true;
        root.pamNotice = "";
        pam.start();
    }

    function tryFingerUnlock() {
        if (root.fingerprintsConfigured) {
            fingerPam.start();
        }
    }

    function stopFingerPam() {
        if (fingerPam.active) {
            fingerPam.abort();
        }
    }

    Process {
        id: fingerprintCheckProc
        running: true
        command: ["bash", "-c", "fprintd-list $(whoami)"]
        stdout: StdioCollector {
            id: fingerprintOutputCollector
            onStreamFinished: {
                root.fingerprintsConfigured = fingerprintOutputCollector.text.includes("Fingerprints for user");
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                // console.warn("[LockContext] fprintd-list command exited with error:", exitCode, exitStatus);
                root.fingerprintsConfigured = false;
            }
        }
    }
    
    PamContext {
        id: pam

        // pam_unix will ask for a response for the password prompt
        onPamMessage: {
            if (this.responseRequired) {
                this.respond(root.currentText);
            } else if (this.message.trim().length > 0) {
                // pam_faillock explains a lockout here; without it a correct password just looks wrong
                root.pamNotice = [root.pamNotice, this.message.trim()].filter(part => part.length > 0).join(" ");
            }
        }

        // pam_unix won't send any important messages so all we need is the completion status.
        onCompleted: result => {
            if (result == PamResult.Success) {
                root.pamNotice = "";
                root.unlocked(root.targetAction);
                stopFingerPam();
            } else {
                root.clearText();
                root.unlockInProgress = false;
                GlobalStates.screenUnlockFailed = true;
                root.showFailure = true;
            }
        }
    }

    PamContext {
        id: fingerPam

        configDirectory: "pam"
        config: "fprintd.conf"

        onCompleted: result => {
            if (result == PamResult.Success) {
                root.unlocked(root.targetAction);
                stopFingerPam();
            } else if (result == PamResult.Error) { // if timeout or etc..
                tryFingerUnlock()
            }
        }
    }
}
