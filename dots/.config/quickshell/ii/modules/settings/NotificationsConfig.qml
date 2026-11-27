import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.notifications

SettingsDetailPage {
    id: rootPage

    sectionTitles: ({
        quiet: Translation.tr("Schedule and duration"),
        banners: Translation.tr("Banners and indicators"),
        apps: Translation.tr("App notifications")
    })
    readonly property string quietStatus: {
        if (!NotificationPreferences.silent) return Translation.tr("Banners are on");
        if (NotificationPreferences.state.silent) return Translation.tr("Until I turn it off");
        return Translation.tr("Until %1").arg(Qt.formatTime(new Date(NotificationPreferences.quietEnd), "HH:mm"));
    }
    readonly property var schedule: Config.options.notifications.quietHours
    readonly property var times: Array.from({length: 48}, (_, i) => {
        const value = String(Math.floor(i / 2)).padStart(2, "0") + (i % 2 ? ":30" : ":00");
        return {displayName: value, value: value};
    })
    property string ipcError: ""
    function shellAction(method, args = []) {
        if (shellProcess.running) return;
        ipcError = "";
        shellProcess.command = ["qs", "-c", "ii", "ipc", "call", "notifications", method, ...args];
        shellProcess.running = true;
    }
    function toggleQuiet() { shellAction("setSilent", [NotificationPreferences.silent ? "false" : "true"]); }
    Process {
        id: shellProcess
        stdout: StdioCollector {
            onStreamFinished: if (text.trim() === "false") rootPage.ipcError = Translation.tr("Unlock the screen to preview a banner.")
        }
        onExited: code => { if (code !== 0) rootPage.ipcError = Translation.tr("Could not reach the running shell."); }
    }
    readonly property var pauseOptions: [
        {displayName: Translation.tr("Off"), value: 0},
        {displayName: Translation.tr("30 minutes"), value: 30},
        {displayName: Translation.tr("1 hour"), value: 60},
        {displayName: Translation.tr("2 hours"), value: 120},
        {displayName: Translation.tr("Until I turn it off"), value: -1}
    ]
    readonly property var pauseChoice: !NotificationPreferences.silent ? 0 : NotificationPreferences.state.silent ? -1 : undefined
    function selectPause(value) {
        if (value > 0) shellAction("silenceFor", [String(value)]);
        else shellAction("setSilent", [value === 0 ? "false" : "true"]);
    }

    component ActionFeedback: StyledText {
        visible: rootPage.ipcError.length > 0
        Layout.fillWidth: true
        Layout.margins: 8
        text: rootPage.ipcError
        wrapMode: Text.Wrap
        color: Appearance.colors.colError
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
                rootPage.seenApps = JSON.parse(appsFile.text()) ?? {};
            } catch (e) {
                rootPage.seenApps = {};
            }
        }
        onLoadFailed: rootPage.seenApps = ({})
    }
    readonly property var rules: Config.options.notifications.apps ?? {}
    readonly property var apps: {
        let keys = new Set([...Object.keys(rootPage.seenApps), ...Object.keys(rootPage.rules)]);
        let result = [];
        for (const key of keys) {
            const seen = rootPage.seenApps[key];
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
    readonly property var recentApps: rootPage.apps.filter(app => app.lastSeen > 0).slice(0, 3)
    readonly property var shownApps: {
        const query = searchField.text.trim().toLowerCase();
        return query.length === 0 ? rootPage.apps : rootPage.apps.filter(app => app.name.toLowerCase().includes(query) || app.key.toLowerCase().includes(query));
    }
    property string expandedKey: ""
    onAppsChanged: searchContentChanged()
    function openApp(key) {
        searchField.clear();
        rootPage.tab = "apps";
        expandedKey = key;
        Qt.callLater(() => {
            if (rootPage.tab !== "apps" || rootPage.expandedKey !== key || !rootPage.pageShown) return;
            const i = rootPage.shownApps.findIndex(app => app.key === key);
            if (i >= 0) rootPage.revealItem(appRows.itemAt(i), false);
        });
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        SettingsBranch {
            id: overview
            page: rootPage
            key: "overview"
            Rectangle {
                id: quietCard
                Layout.fillWidth: true
                implicitHeight: quietPanel.implicitHeight + 16
                radius: Appearance.rounding.normal
                readonly property color accent: ColorUtils.mix("#a99ce1", Appearance.colors.colPrimary, 0.57)
                property color shade: ColorUtils.mix(accent, Appearance.colors.colLayer2Base, NotificationPreferences.silent ? 0.26 : 0.12)
                Behavior on shade { animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this) }
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: quietCard.shade }
                    GradientStop { position: 1; color: Appearance.colors.colLayer2 }
                }
                ColumnLayout {
                    id: quietPanel
                    x: 8; y: 8; width: parent.width - 16; spacing: 2
                    GridLayout {
                        Layout.fillWidth: true
                        columns: width >= 415 ? 2 : 1
                        columnSpacing: 8; rowSpacing: 0
                        RippleButton {
                            id: quietToggle
                            objectName: "notificationQuietToggle"
                            Layout.fillWidth: true
                            Layout.preferredWidth: 320; Layout.minimumWidth: 0
                            implicitHeight: Math.max(60, contentItem.implicitHeight + 14)
                            leftPadding: 9; rightPadding: 12
                            readonly property bool settingsSearchable: true
                            text: Translation.tr("Do not disturb")
                            readonly property string searchText: text
                            Accessible.name: text
                            Accessible.role: Accessible.CheckBox
                            Accessible.checked: NotificationPreferences.silent
                            onClicked: rootPage.toggleQuiet()
                            contentItem: RowLayout {
                                spacing: 12
                                Rectangle {
                                    implicitWidth: 42; implicitHeight: 42; radius: 21
                                    color: ColorUtils.mix(quietCard.accent, quietCard.shade, 0.29)
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: NotificationPreferences.silent ? "bedtime" : "bedtime_off"
                                        iconSize: 23; color: Appearance.colors.colOnLayer2
                                        rotation: NotificationPreferences.silent ? -12 : 0
                                        Behavior on rotation { animation: Appearance.animation.elementMove.numberAnimation.createObject(this) }
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 1
                                    StyledText {
                                        Layout.fillWidth: true; wrapMode: Text.Wrap
                                        text: quietToggle.text; font.family: Appearance.font.family.title
                                        font.pixelSize: Appearance.font.pixelSize.larger; font.weight: Font.DemiBold
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    StyledText { Layout.fillWidth: true; wrapMode: Text.Wrap; text: rootPage.quietStatus; font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext }
                                }
                                StyledSwitch {
                                    checkable: false; checked: NotificationPreferences.silent
                                    onClicked: rootPage.toggleQuiet()
                                }
                            }
                        }
                        ChoiceDropdown {
                            objectName: "quickQuietDuration"
                            Layout.alignment: Qt.AlignRight
                            Layout.rightMargin: 6
                            options: rootPage.pauseOptions
                            currentValue: rootPage.pauseChoice
                            displayText: NotificationPreferences.silent ? Translation.tr("Change duration") : Translation.tr("Pause for")
                            displayIcon: "timelapse"
                            Accessible.name: displayText
                            onSelected: value => rootPage.selectPause(value)
                        }
                    }
                    Rectangle { Layout.fillWidth: true; Layout.leftMargin: 10; Layout.rightMargin: 10; implicitHeight: 1; color: Appearance.colors.colOutlineVariant }
                    QuietHoursTimeline { branch: quiet }
                }
            }
            ActionFeedback {}
            ContentSection {
                card: false
                title: Translation.tr("Recent apps")
                icon: "history"
                Repeater {
                    model: rootPage.recentApps
                    delegate: NotificationAppRow {
                        required property var modelData
                        appKey: modelData.key
                        app: modelData
                        summaryOnly: true
                        onToggleExpanded: rootPage.openApp(appKey)
                    }
                }
                RowLayout {
                    visible: rootPage.recentApps.length === 0
                    Layout.fillWidth: true; Layout.margins: 14; spacing: 12
                    MaterialSymbol { text: "notifications_none"; iconSize: 24; color: Appearance.colors.colSubtext }
                    StyledText {
                        Layout.fillWidth: true; wrapMode: Text.Wrap
                        text: Translation.tr("Apps appear here after they send a notification.")
                        color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.small
                    }
                }
            }
            ContentSection {
                SettingsBranchLink {
                    branch: banners
                    title: Translation.tr("Banners")
                    buttonIcon: "picture_in_picture_alt"
                    summary: bannerPicker.corners.find(c => c.key === NotificationPreferences.corner).label + " · " + Translation.tr("%1 s").arg(Config.options.notifications.timeout / 1000)
                }
                SettingsBranchLink {
                    branch: appRules
                    buttonIcon: "apps"
                    title: Translation.tr("All apps")
                    summary: rootPage.apps.length ? String(rootPage.apps.length) : ""
                }
            }
        }

        SettingsBranch {
            id: quiet
            page: rootPage
            key: "quiet"
            ContentSection {
                title: Translation.tr("Pause notifications")
                ConfigComboRow {
                    objectName: "quietDuration"
                    icon: "timelapse"
                    text: Translation.tr("Pause for")
                    options: rootPage.pauseOptions
                    currentValue: rootPage.pauseChoice
                    dropdown.displayText: NotificationPreferences.silent ? rootPage.quietStatus : Translation.tr("Off")
                    searchable: false
                    onSelected: value => rootPage.selectPause(value)
                }
                ActionFeedback {}
            }
            ContentSection {
                icon: "schedule"
                title: Translation.tr("Quiet hours")
                description: rootPage.schedule.enabled && rootPage.schedule.from === rootPage.schedule.to
                    ? Translation.tr("Choose different start and end times.") : ""
                ConfigSwitch {
                    buttonIcon: "schedule"
                    text: Translation.tr("Use a daily schedule")
                    autoToggle: false
                    checked: rootPage.schedule.enabled
                    onClicked: rootPage.schedule.enabled = !checked
                }
                ConfigComboRow {
                    enabled: rootPage.schedule.enabled
                    icon: "bedtime"
                    text: Translation.tr("From")
                    searchable: false
                    options: rootPage.times
                    currentValue: rootPage.schedule.from
                    onSelected: value => rootPage.schedule.from = value
                }
                ConfigComboRow {
                    enabled: rootPage.schedule.enabled
                    icon: "wb_sunny"
                    text: Translation.tr("Until")
                    searchable: false
                    options: rootPage.times
                    currentValue: rootPage.schedule.to
                    onSelected: value => rootPage.schedule.to = value
                }
            }
        }

        SettingsBranch {
            id: banners
            page: rootPage
            key: "banners"
            ContentSection {
                title: Translation.tr("Banner position")
                description: Translation.tr("Select where banners appear on the screen.")
                BannerPositionPicker { id: bannerPicker; shown: rootPage.pageShown && banners.shown }
                ConfigNavRow {
                    objectName: "previewNotification"
                    title: Translation.tr("Show a test banner")
                    buttonIcon: "notifications_active"
                    trailingIcon: "play_arrow"
                    onClicked: { bannerPicker.replay(); rootPage.shellAction("previewBanner"); }
                }
                ConfigNavRow {
                    visible: Config.options.notifications.popupPosition !== "auto"
                    title: Translation.tr("Use the theme’s default corner")
                    buttonIcon: "restart_alt"
                    trailingIcon: ""
                    onClicked: Config.options.notifications.popupPosition = "auto"
                }
                ActionFeedback {}
            }
            ContentSection {
                title: Translation.tr("Banners")
                ConfigSlider {
                    buttonIcon: "av_timer"
                    text: Translation.tr("Banner duration")
                    description: Translation.tr("Used when the notification doesn't set its own")
                    from: 1; to: 60
                    value: Config.options.notifications.timeout / 1000
                    valueText: Translation.tr("%1 s").arg(value.toFixed(value % 1 ? 1 : 0))
                    defaultValue: 7
                    defaultValueText: Translation.tr("%1 s").arg(7)
                    usePercentTooltip: false
                    onMoved: Config.options.notifications.timeout = Math.round(value) * 1000
                }
                ConfigSwitch {
                    buttonIcon: "counter_2"
                    text: Translation.tr("Show unread count in the bar")
                    autoToggle: false
                    checked: Config.options.bar.indicators.notifications.showUnreadCount
                    onClicked: Config.options.bar.indicators.notifications.showUnreadCount = !checked
                }
            }
            ContentSection {
                title: Translation.tr("On-screen display")
                description: Translation.tr("Volume and brightness indicators")
                ConfigSlider {
                    buttonIcon: "av_timer"
                    text: Translation.tr("Indicator duration")
                    from: 0.1; to: 3
                    defaultValue: 1
                    defaultValueText: Translation.tr("%1 s").arg(1)
                    usePercentTooltip: false
                    value: Config.options.osd.timeout / 1000
                    valueText: Translation.tr("%1 s").arg(value.toFixed(1))
                    onMoved: Config.options.osd.timeout = Math.round(value * 10) * 100
                }
            }
        }

        SettingsBranch {
            id: appRules
            page: rootPage
            key: "apps"
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
                    id: appRows
                    model: rootPage.shownApps
                    delegate: NotificationAppRow {
                        required property var modelData
                        Layout.fillWidth: true
                        appKey: modelData.key
                        app: modelData
                        expanded: rootPage.expandedKey === modelData.key
                        onToggleExpanded: rootPage.expandedKey = expanded ? "" : modelData.key
                    }
                }
                StyledText {
                    visible: rootPage.shownApps.length === 0
                    Layout.fillWidth: true
                    Layout.margins: 8
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    text: rootPage.apps.length === 0 ? Translation.tr("No app has sent a notification yet") : Translation.tr("No app matches your search")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }

                AppPickerPopup {
                    id: appPicker
                    title: Translation.tr("Set up notifications for an app")
                    excludedIds: rootPage.apps.map(app => app.key)
                    onPicked: entry => {
                        let apps = Object.assign({}, Config.options.notifications.apps ?? {});
                        apps[entry.id] = { "mode": "banners", "added": true };
                        Config.options.notifications.apps = apps;
                        searchField.clear();
                        rootPage.expandedKey = entry.id;
                    }
                }
            }
        }
    }
}
