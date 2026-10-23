import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.notifications

ContentPage {
    id: page

    // Do not disturb lives in the shell (Persistent); it's changed through the shell so popups follow at once
    readonly property bool doNotDisturb: Persistent.states.notifications.silent
    function setDoNotDisturb(on) {
        Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "notifications", "setSilent", on ? "true" : "false"]);
    }

    // Apps that ever sent a notification (kept by the shell), plus apps added here by hand
    property var seenApps: ({})
    FileView {
        id: appsFile
        path: Directories.notificationAppsPath
        watchChanges: true
        onFileChanged: appsFile.reload()
        onLoaded: {
            try {
                page.seenApps = JSON.parse(appsFile.text()) ?? {};
            } catch (e) {
                page.seenApps = {};
            }
        }
    }
    readonly property var rules: Config.options.notifications.apps ?? {}
    readonly property var apps: {
        let keys = new Set([...Object.keys(page.seenApps), ...Object.keys(page.rules)]);
        let result = [];
        for (const key of keys) {
            const seen = page.seenApps[key];
            const entry = DesktopEntries.byId(key);
            result.push({
                "key": key,
                "name": seen?.name || entry?.name || key,
                "icon": seen?.icon || entry?.icon || "",
                "desktopEntry": seen?.desktopEntry || (entry ? key : ""),
                "lastSeen": seen?.lastSeen ?? 0,
            });
        }
        return result.sort((a, b) => (b.lastSeen - a.lastSeen) || a.name.localeCompare(b.name));
    }
    readonly property var shownApps: {
        const query = searchField.text.trim().toLowerCase();
        return query.length === 0 ? page.apps : page.apps.filter(app => app.name.toLowerCase().includes(query) || app.key.toLowerCase().includes(query));
    }
    property string expandedKey: ""

    ContentSection {
        icon: "do_not_disturb_on"
        title: Translation.tr("Do not disturb")

        RippleButton { // Big switch
            Layout.fillWidth: true
            implicitHeight: dndRow.implicitHeight + 28
            buttonRadius: Appearance.rounding.normal
            colBackground: page.doNotDisturb ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
            colBackgroundHover: page.doNotDisturb ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover
            onClicked: page.setDoNotDisturb(!page.doNotDisturb)

            readonly property bool settingsSearchable: true
            readonly property string searchText: Translation.tr("Do not disturb")

            contentItem: RowLayout {
                id: dndRow
                spacing: 14
                Rectangle {
                    implicitWidth: 48
                    implicitHeight: 48
                    radius: 24
                    color: page.doNotDisturb ? Appearance.colors.colPrimary : Appearance.colors.colLayer3
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: page.doNotDisturb ? "notifications_paused" : "notifications"
                        iconSize: 26
                        fill: page.doNotDisturb ? 1 : 0
                        color: page.doNotDisturb ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        Layout.fillWidth: true
                        text: page.doNotDisturb ? Translation.tr("Do not disturb is on") : Translation.tr("Do not disturb is off")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.variableAxes: ({ "wght": 600 })
                        color: page.doNotDisturb ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: Translation.tr("Notifications go quietly to the list in the sidebar. Apps you allow below still show up.")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
                StyledSwitch {
                    checkable: false
                    checked: page.doNotDisturb
                    onClicked: page.setDoNotDisturb(!page.doNotDisturb)
                }
            }
        }
    }

    ContentSection {
        icon: "apps"
        title: Translation.tr("Apps")
        description: Translation.tr("Every app that has sent a notification shows up here. Click one to choose how it may reach you.")

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            TextField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: Translation.tr("Search apps")
                placeholderTextColor: Appearance.colors.colSubtext
                color: Appearance.colors.colOnLayer3
                leftPadding: 14
                topPadding: 10
                bottomPadding: 10
                font.pixelSize: Appearance.font.pixelSize.small
                background: Rectangle {
                    implicitHeight: 40
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colLayer3
                    border.width: searchField.activeFocus ? 2 : 0
                    border.color: Appearance.colors.colPrimary
                }
            }
            RippleButton {
                implicitHeight: 40
                leftPadding: 12
                rightPadding: 16
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer3
                colBackgroundHover: Appearance.colors.colLayer3Hover
                onClicked: appPicker.open()
                contentItem: RowLayout {
                    spacing: 6
                    MaterialSymbol { text: "add"; iconSize: 20; color: Appearance.colors.colOnLayer3 }
                    StyledText { text: Translation.tr("Add an app"); font.pixelSize: Appearance.font.pixelSize.small; color: Appearance.colors.colOnLayer3 }
                }
            }
        }

        Repeater {
            model: page.shownApps
            delegate: NotificationAppRow {
                required property var modelData
                Layout.fillWidth: true
                appKey: modelData.key
                app: modelData
                expanded: page.expandedKey === modelData.key
                onToggleExpanded: page.expandedKey = expanded ? "" : modelData.key
            }
        }
        StyledText {
            visible: page.shownApps.length === 0
            Layout.fillWidth: true
            Layout.margins: 8
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            text: page.apps.length === 0 ? Translation.tr("No app has sent a notification yet") : Translation.tr("No app matches your search")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }

        AppPickerPopup {
            id: appPicker
            title: Translation.tr("Set up notifications for an app")
            excludedIds: page.apps.map(app => app.key)
            onPicked: entry => {
                let apps = Object.assign({}, Config.options.notifications.apps ?? {});
                apps[entry.id] = { "mode": "banners", "added": true };
                Config.options.notifications.apps = apps;
                page.expandedKey = entry.id;
            }
        }
    }

    ContentSection {
        icon: "web_asset"
        title: Translation.tr("Popups")

        ConfigSpinBox {
            icon: "av_timer"
            text: Translation.tr("Timeout duration (ms)")
            description: Translation.tr("Used when the notification doesn't set its own")
            value: Config.options.notifications.timeout
            from: 1000
            to: 60000
            stepSize: 1000
            onValueChanged: Config.options.notifications.timeout = value
        }
        ConfigSwitch {
            buttonIcon: "counter_2"
            text: Translation.tr("Show unread count in the bar")
            autoToggle: false
            checked: Config.options.bar.indicators.notifications.showUnreadCount
            onClicked: Config.options.bar.indicators.notifications.showUnreadCount = !Config.options.bar.indicators.notifications.showUnreadCount
        }
    }

    ContentSection {
        icon: "tune"
        title: Translation.tr("On-screen display")
        description: Translation.tr("Volume and brightness indicators")

        ConfigSpinBox {
            icon: "av_timer"
            text: Translation.tr("Timeout (ms)")
            value: Config.options.osd.timeout
            from: 100
            to: 3000
            stepSize: 100
            onValueChanged: Config.options.osd.timeout = value
        }
    }
}
