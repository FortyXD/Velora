import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * A shortcut drawn as keycaps. Click it and press keys to record a new one: Esc cancels,
 * Backspace turns the shortcut off. While recording, Hyprland switches to an empty submap
 * so the keys reach this window instead of running binds.
 */
RippleButton {
    id: root
    property var mods: []
    property string key: ""
    property bool turnedOff: false
    property bool allowTurnOff: true
    property string emptyText: Translation.tr("Record")
    property string hint: ""
    readonly property bool recording: HyprlandKeybinds.activeRecorder === root
    property var heldMods: []

    signal recorded(var mods, string key)
    signal turnOffRequested()

    function start() {
        if (HyprlandKeybinds.activeRecorder && HyprlandKeybinds.activeRecorder !== root) HyprlandKeybinds.activeRecorder.stop();
        HyprlandKeybinds.activeRecorder = root;
        HyprlandKeybinds.startCapture();
        root.heldMods = [];
        root.hint = "";
        root.forceActiveFocus();
        idleTimer.restart();
    }

    function stop() {
        if (!root.recording) return;
        HyprlandKeybinds.activeRecorder = null;
        HyprlandKeybinds.endCapture();
        root.heldMods = [];
        idleTimer.stop();
    }

    function modOfKey(qtKey) {
        if ([Qt.Key_Super_L, Qt.Key_Super_R, Qt.Key_Meta].includes(qtKey)) return "Super";
        if (qtKey === Qt.Key_Control) return "Ctrl";
        if (qtKey === Qt.Key_Alt) return "Alt";
        if (qtKey === Qt.Key_Shift) return "Shift";
        return "";
    }

    onClicked: root.recording ? root.stop() : root.start()
    onActiveFocusChanged: if (!activeFocus) root.stop()
    Component.onDestruction: root.stop()

    // Window shortcuts like Esc or Ctrl+Tab must not fire while recording
    Keys.onShortcutOverride: event => {
        if (root.recording) event.accepted = true;
    }
    Keys.onPressed: event => {
        if (!root.recording) return;
        event.accepted = true;
        idleTimer.restart();
        let mods = KeyUtils.modsFromEvent(event.modifiers);
        const key = KeyUtils.keyFromEvent(event);
        if (key === "") { // Only modifiers so far
            const own = root.modOfKey(event.key);
            if (own && !mods.includes(own)) mods.push(own);
            root.heldMods = KeyUtils.sortMods(mods);
            return;
        }
        if (mods.length === 0 && key === "Escape") {
            root.stop();
            return;
        }
        if (mods.length === 0 && key === "BackSpace" && root.allowTurnOff) {
            root.stop();
            root.turnOffRequested();
            return;
        }
        if (!KeyUtils.worksAlone(key) && (mods.length === 0 || (mods.length === 1 && mods[0] === "Shift"))) {
            root.hint = Translation.tr("Add Super, Ctrl or Alt to %1").arg(KeyUtils.keyLabel(key));
            shake.restart();
            return;
        }
        root.stop();
        root.recorded(KeyUtils.sortMods(mods), key);
    }
    Keys.onReleased: event => {
        if (!root.recording) return;
        event.accepted = true;
        const own = root.modOfKey(event.key);
        root.heldMods = KeyUtils.sortMods(KeyUtils.modsFromEvent(event.modifiers).filter(mod => mod !== own));
    }

    Timer { // Hyprland gives the keybinds back after 15 s anyway
        id: idleTimer
        interval: 12000
        onTriggered: root.stop()
    }

    implicitHeight: 34
    implicitWidth: Math.max(64, contentItem.implicitWidth + 20)
    buttonRadius: Appearance.rounding.small
    colBackground: root.recording ? Appearance.colors.colPrimaryContainer : "transparent"
    colBackgroundHover: root.recording ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer2Hover
    colRipple: Appearance.colors.colLayer2Active

    transform: Translate {
        id: shakeTranslate
    }
    SequentialAnimation {
        id: shake
        NumberAnimation { target: shakeTranslate; property: "x"; to: -5; duration: 50 }
        NumberAnimation { target: shakeTranslate; property: "x"; to: 5; duration: 70 }
        NumberAnimation { target: shakeTranslate; property: "x"; to: -3; duration: 60 }
        NumberAnimation { target: shakeTranslate; property: "x"; to: 0; duration: 50 }
    }

    Rectangle { // Pulsing outline while listening
        anchors.fill: parent
        radius: root.buttonRadius
        color: "transparent"
        border.width: 2
        border.color: Appearance.colors.colPrimary
        visible: root.recording
        SequentialAnimation on opacity {
            running: root.recording
            loops: Animation.Infinite
            NumberAnimation { from: 1; to: 0.35; duration: 700; easing.type: Easing.InOutSine }
            NumberAnimation { from: 0.35; to: 1; duration: 700; easing.type: Easing.InOutSine }
        }
    }

    contentItem: Item {
        implicitWidth: content.implicitWidth
        implicitHeight: content.implicitHeight

        RowLayout {
            id: content
            anchors.centerIn: parent
            spacing: 6

            KeyCombo { // Current shortcut, or the modifiers held while recording
                visible: root.recording ? root.heldMods.length > 0 : (!root.turnedOff && root.key.length > 0)
                labels: root.recording ? [...root.heldMods.map(mod => KeyUtils.modLabel(mod)), "…"] : KeyUtils.comboLabels(root.mods, root.key)
                keyColor: root.recording ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
                textColor: root.recording ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
            }
            MaterialSymbol {
                visible: !root.recording && (root.turnedOff || root.key.length === 0)
                text: root.turnedOff ? "block" : "keyboard"
                iconSize: 18
                color: Appearance.colors.colSubtext
            }
            StyledText {
                visible: root.recording ? root.heldMods.length === 0 : (root.turnedOff || root.key.length === 0)
                text: root.recording ? Translation.tr("Press keys…") : root.turnedOff ? Translation.tr("Off") : root.emptyText
                font.pixelSize: Appearance.font.pixelSize.small
                color: root.recording ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
            }
        }
    }

    StyledToolTip {
        extraVisibleCondition: !root.recording
        text: Translation.tr("Click to change")
    }
}
