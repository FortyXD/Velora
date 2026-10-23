import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.panels.lock

/**
 * Battery and the sleep, power off and restart buttons (lock.showBattery, lock.showPowerButtons).
 * The buttons only act with a context (the real lock screen).
 */
Toolbar {
    id: root
    property var context: null
    property bool liveData: true
    readonly property bool interactive: root.context !== null
    readonly property bool requirePasswordToPower: Config.options.lock.security.requirePasswordToPower
    readonly property bool showBattery: Config.options.lock.showBattery && (!root.liveData || Battery.available)
    readonly property bool showButtons: Config.options.lock.showPowerButtons
    readonly property bool hasContent: root.showBattery || root.showButtons

    signal refocus()

    LockIconText {
        visible: root.showBattery
        icon: !root.liveData ? "battery_android_full" : Battery.isCharging ? "bolt" : "battery_android_full"
        text: root.liveData ? Math.round(Battery.percentage * 100) : "76"
        color: (root.liveData && Battery.isLow && !Battery.isCharging) ? Appearance.colors.colError : Appearance.colors.colOnSurfaceVariant
    }

    IconToolbarButton {
        visible: root.showButtons
        onClicked: if (root.interactive) Session.suspend()
        text: "dark_mode"
    }

    GuardedButton {
        visible: root.showButtons
        text: "power_settings_new"
        targetAction: LockContext.ActionEnum.Poweroff
    }

    GuardedButton {
        visible: root.showButtons
        text: "restart_alt"
        targetAction: LockContext.ActionEnum.Reboot
    }

    // Powering off or restarting asks for the password first when lock.security.requirePasswordToPower is on
    component GuardedButton: IconToolbarButton {
        id: guardedBtn
        required property var targetAction

        toggled: root.context?.targetAction === guardedBtn.targetAction

        onClicked: {
            if (!root.interactive) return;
            if (!root.requirePasswordToPower) {
                root.context.unlocked(guardedBtn.targetAction);
                return;
            }
            if (root.context.targetAction === guardedBtn.targetAction) {
                root.context.resetTargetAction();
            } else {
                root.context.targetAction = guardedBtn.targetAction;
                root.context.shouldReFocus();
            }
        }
    }
}
