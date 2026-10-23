import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.panels.lock

/**
 * The password field with the fingerprint hint and the confirm button.
 * Without a context (previews) it only shows how it looks.
 */
Toolbar {
    id: root
    property var context: null
    readonly property bool interactive: root.context !== null
    property bool ctrlHeld: false
    readonly property alias field: passwordBox

    function forceFieldFocus() {
        if (root.interactive) passwordBox.forceActiveFocus();
    }

    // Fingerprint
    Loader {
        Layout.leftMargin: 10
        Layout.rightMargin: 6
        Layout.alignment: Qt.AlignVCenter
        active: root.context?.fingerprintsConfigured ?? false
        visible: active

        sourceComponent: MaterialSymbol {
            fill: 1
            text: "fingerprint"
            iconSize: Appearance.font.pixelSize.hugeass
            color: Appearance.colors.colOnSurfaceVariant
        }
    }

    ToolbarTextField {
        id: passwordBox
        Layout.rightMargin: -Layout.leftMargin
        placeholderText: GlobalStates.screenUnlockFailed && root.interactive ? Translation.tr("Incorrect password") : Translation.tr("Enter password")

        // Style
        clip: true
        font.pixelSize: Appearance.font.pixelSize.small
        selectedTextColor: materialShapeChars ? "transparent" : Appearance.colors.colOnSecondaryContainer
        selectionColor: materialShapeChars ? "transparent" : Appearance.colors.colSecondaryContainer

        // Password
        enabled: !(root.context?.unlockInProgress ?? false)
        readOnly: !root.interactive
        focusPolicy: root.interactive ? Qt.StrongFocus : Qt.NoFocus
        cursorDelegate: root.interactive ? null : noCursor // Previews have no blinking cursor
        Component {
            id: noCursor
            Item {}
        }
        activeFocusOnPress: root.interactive
        echoMode: TextInput.Password
        inputMethodHints: Qt.ImhSensitiveData

        // Synchronizing (across monitors) and unlocking
        onTextChanged: if (root.interactive) root.context.currentText = this.text
        onAccepted: {
            if (root.interactive) root.context.tryUnlock(root.ctrlHeld);
        }
        Connections {
            target: root.context
            enabled: root.interactive
            function onCurrentTextChanged() {
                passwordBox.text = root.context.currentText;
            }
        }

        Keys.onPressed: event => {
            if (!root.interactive) return;
            root.context.resetClearTimer();
            root.context.noteTypedKey(event);
        }

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: passwordBox.width - 8
                height: passwordBox.height
                radius: height / 2
            }
        }

        // Shake when wrong password
        ErrorShakeAnimation {
            id: wrongPasswordShakeAnim
            target: passwordBox
        }
        Connections {
            target: GlobalStates
            enabled: root.interactive
            function onScreenUnlockFailedChanged() {
                if (GlobalStates.screenUnlockFailed) wrongPasswordShakeAnim.restart();
            }
        }

        // We're drawing dots manually
        property bool materialShapeChars: Config.options.lock.materialShapeChars
        color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, materialShapeChars ? 1 : 0)
        Loader {
            active: passwordBox.materialShapeChars
            anchors {
                fill: parent
                leftMargin: passwordBox.padding
                rightMargin: passwordBox.padding
            }
            sourceComponent: PasswordChars {
                length: root.context?.currentText.length ?? 0
                selectionStart: passwordBox.selectionStart
                selectionEnd: passwordBox.selectionEnd
                cursorPosition: passwordBox.cursorPosition
            }
        }
    }

    ToolbarButton {
        id: confirmButton
        implicitWidth: height
        toggled: true
        enabled: !(root.context?.unlockInProgress ?? false)
        colBackgroundToggled: Appearance.colors.colPrimary

        onClicked: if (root.interactive) root.context.tryUnlock()

        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            iconSize: 24
            text: {
                const action = root.context?.targetAction ?? LockContext.ActionEnum.Unlock;
                if (action === LockContext.ActionEnum.Poweroff) return "power_settings_new";
                if (action === LockContext.ActionEnum.Reboot) return "restart_alt";
                return root.ctrlHeld ? "coffee" : "arrow_right_alt";
            }
            color: confirmButton.enabled ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
        }
    }
}
