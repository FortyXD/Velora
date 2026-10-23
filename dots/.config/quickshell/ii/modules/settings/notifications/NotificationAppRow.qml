import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.settings.preview

/**
 * One app on the Notifications page: icon, name, how its notifications show up and an on/off switch.
 * Clicking it unfolds the choices: banners, only in the list, or off; and showing through do not disturb.
 */
ColumnLayout {
    id: root
    required property string appKey
    required property var app // { name, icon, desktopEntry } from the shell's list of apps that sent notifications
    property bool expanded: false
    signal toggleExpanded()

    readonly property var rule: Config.options.notifications.apps?.[root.appKey] ?? {}
    readonly property string mode: root.rule.mode ?? "banners"
    readonly property bool bypassDnd: root.rule.bypassDnd === true
    // The name the app gives in its notifications ("Network Management" rather than its service "KDED")
    readonly property string displayName: {
        if ((root.app.name ?? "").length > 0 && root.app.name !== root.appKey) return root.app.name;
        const entry = (root.app.desktopEntry ?? "").length > 0 ? DesktopEntries.byId(root.app.desktopEntry) : null;
        return entry?.name || root.app.name || root.appKey;
    }

    readonly property bool settingsSearchable: true
    readonly property string searchText: root.displayName

    // Writes the rule; the default (banners, not through do not disturb) leaves no entry behind,
    // unless the app was added by hand before it ever sent anything
    function setRule(patch) {
        let apps = Object.assign({}, Config.options.notifications.apps ?? {});
        const next = Object.assign({}, apps[root.appKey] ?? {}, patch);
        if ((next.mode ?? "banners") === "banners" && next.bypassDnd !== true && next.added !== true) delete apps[root.appKey];
        else apps[root.appKey] = next;
        Config.options.notifications.apps = apps;
    }
    function removeRule() {
        let apps = Object.assign({}, Config.options.notifications.apps ?? {});
        delete apps[root.appKey];
        Config.options.notifications.apps = apps;
    }

    function ipc(func) {
        Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "notifications", func, root.appKey]);
    }

    spacing: 0

    RippleButton {
        Layout.fillWidth: true
        implicitHeight: 58
        leftPadding: 12
        rightPadding: 12
        buttonRadius: Appearance.rounding.small
        colBackground: root.expanded ? Appearance.colors.colLayer2 : "transparent"
        colBackgroundHover: Appearance.colors.colLayer2Hover
        onClicked: root.toggleExpanded()

        contentItem: RowLayout {
            spacing: 12
            NotificationAppIcon {
                implicitSize: 38
                appIcon: root.app.icon ?? ""
                appName: root.app.name ?? ""
                desktopEntry: root.app.desktopEntry ?? ""
                opacity: root.mode === "off" ? 0.45 : 1
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: root.displayName
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: {
                        const base = root.mode === "off" ? Translation.tr("Off")
                            : root.mode === "silent" ? Translation.tr("Only in the list")
                            : Translation.tr("Banners");
                        return root.bypassDnd && root.mode !== "off" ? `${base} · ${Translation.tr("Shows during do not disturb")}` : base;
                    }
                }
            }
            MaterialSymbol {
                text: "expand_more"
                iconSize: 20
                color: Appearance.colors.colSubtext
                rotation: root.expanded ? 180 : 0
                Behavior on rotation {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
            StyledSwitch {
                checkable: false
                checked: root.mode !== "off"
                onClicked: root.setRule({ "mode": root.mode === "off" ? "banners" : "off" })
            }
        }
    }

    ColumnLayout { // The choices
        visible: root.expanded
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 8
        Layout.bottomMargin: 10
        spacing: 6

        Flow {
            Layout.fillWidth: true
            Layout.topMargin: 6
            spacing: 4
            SchemeTile {
                id: bannersTile
                label: Translation.tr("Banners")
                frameWidth: 104
                frameHeight: 64
                selected: root.mode === "banners"
                onClicked: root.setRule({ "mode": "banners" })
                Rectangle { // A banner in the corner of the screen
                    x: parent.width - width - 6; y: 6; width: 48; height: 16; radius: 5
                    color: bannersTile.ink
                }
            }
            SchemeTile {
                id: listTile
                label: Translation.tr("Only in the list")
                frameWidth: 104
                frameHeight: 64
                selected: root.mode === "silent"
                onClicked: root.setRule({ "mode": "silent" })
                Rectangle { // The sidebar with the notification in it
                    x: parent.width - width; y: 0; width: 40; height: parent.height
                    color: listTile.faint
                    Column {
                        x: 5; y: 8; spacing: 4
                        Repeater {
                            model: 3
                            Rectangle { required property int index; width: 30; height: 7; radius: 3; color: index === 0 ? listTile.ink : listTile.faint }
                        }
                    }
                }
            }
            SchemeTile {
                id: offTile
                label: Translation.tr("Off")
                frameWidth: 104
                frameHeight: 64
                selected: root.mode === "off"
                onClicked: root.setRule({ "mode": "off" })
                MaterialSymbol { anchors.centerIn: parent; text: "notifications_off"; iconSize: 26; color: offTile.ink }
            }
        }

        ConfigSwitch {
            enabled: root.mode !== "off"
            buttonIcon: "do_not_disturb_off"
            text: Translation.tr("Show even during do not disturb")
            description: Translation.tr("For the apps you never want to miss, like calls or messages from family")
            autoToggle: false
            checked: root.bypassDnd
            onClicked: root.setRule({ "bypassDnd": !root.bypassDnd })
        }

        RowLayout {
            spacing: 6
            RippleButton {
                implicitHeight: 34
                leftPadding: 12
                rightPadding: 14
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer2
                onClicked: root.ipc("clearApp")
                contentItem: RowLayout {
                    spacing: 6
                    MaterialSymbol { text: "clear_all"; iconSize: 18; color: Appearance.colors.colOnLayer2 }
                    StyledText { text: Translation.tr("Clear its notifications"); font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colOnLayer2 }
                }
            }
            RippleButton {
                implicitHeight: 34
                leftPadding: 12
                rightPadding: 14
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer2
                onClicked: {
                    root.removeRule();
                    root.ipc("forgetApp");
                }
                contentItem: RowLayout {
                    spacing: 6
                    MaterialSymbol { text: "delete"; iconSize: 18; color: Appearance.colors.colOnLayer2 }
                    StyledText { text: Translation.tr("Remove from this list"); font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colOnLayer2 }
                }
            }
        }
    }
}
