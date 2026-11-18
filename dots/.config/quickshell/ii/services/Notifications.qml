pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

/**
 * Provides extra features not in Quickshell.Services.Notifications:
 *  - Persistent storage
 *  - Popup notifications, with timeout
 *  - Notification groups by app
 *  - Per-app rules (Config.options.notifications.apps): banners, only in the list, or off; and showing through
 *    do not disturb. Apps that ever sent something are remembered for Settings → Notifications.
 */
Singleton {
	id: root
    component Notif: QtObject {
        id: wrapper
        required property int notificationId // Could just be `id` but it conflicts with the default prop in QtObject
        property Notification notification
        property list<var> actions: notification?.actions.map((action) => ({
            "identifier": action.identifier,
            "text": action.text,
        })) ?? []
        property bool popup: false
        property bool isTransient: notification?.hints.transient ?? false
        property string appIcon: NotificationUtils.appIcon(notification?.appIcon)
        property string appName: notification?.appName ?? ""
        property string desktopEntry: notification?.desktopEntry ?? ""
        property string body: notification?.body ?? ""
        property string image: NotificationUtils.localImage(notification?.image)
        property string summary: notification?.summary ?? ""
        property double time
        property string urgency: notification?.urgency.toString() ?? "normal"
        property Timer timer

        function release() {
            timer?.stop();
            notification?.dismiss();
            destroy();
        }

        onNotificationChanged: {
            if (notification === null) {
                root.discardNotification(notificationId);
            }
        }
    }

    function notifToJSON(notif) {
        return {
            "notificationId": notif.notificationId,
            "actions": notif.actions,
            "appIcon": notif.appIcon,
            "appName": notif.appName,
            "desktopEntry": notif.desktopEntry,
            "body": notif.body,
            "image": notif.image,
            "summary": notif.summary,
            "time": notif.time,
            "urgency": notif.urgency,
        }
    }
    function notifToString(notif) {
        return JSON.stringify(notifToJSON(notif), null, 2);
    }

    component NotifTimer: Timer {
        required property Notif owner
        interval: 7000
        running: true
        onTriggered: {
            owner.timer = null;
            if (owner.isTransient) root.discardNotification(owner.notificationId);
            else root.timeoutNotification(owner.notificationId);
            destroy();
        }
    }

    readonly property bool silent: NotificationPreferences.silent
    property int unread: 0
    function toggleSilent() { NotificationPreferences.setQuiet(!root.silent); }
    onSilentChanged: {
        if (!root.silent) return;
        for (const n of root.list) {
            if (n?.popup && !root.ruleFor(root.appKey(n.appName, n.desktopEntry)).bypassDnd)
                root.timeoutNotification(n.notificationId);
        }
    }

    function appKey(appName, desktopEntry) {
        return (desktopEntry ?? "").length > 0 ? desktopEntry : ((appName ?? "").length > 0 ? appName : "unknown");
    }
    function ruleFor(key) {
        return Config.options?.notifications.apps?.[key] ?? {};
    }

    // Apps seen so far: { key: { name, icon, desktopEntry, count, lastSeen } }
    property var seenApps: Object.create(null)
    property bool seenAppsLoaded: false
    function rememberApp(key, appName, appIcon, desktopEntry, time = Date.now()) {
        const known = root.seenApps[key];
        root.seenApps[key] = {
            "name": appName || known?.name || key,
            "icon": NotificationUtils.appIcon(appIcon) || known?.icon || "",
            "desktopEntry": desktopEntry || known?.desktopEntry || "",
            "count": (known?.count ?? 0) + 1,
            "lastSeen": Math.max(time, known?.lastSeen ?? 0),
        };
        if (root.seenAppsLoaded) seenAppsWriteTimer.restart();
    }
    // Apps in the saved notifications count too, the first time this list is made
    function seedSeenApps() {
        if (!root.seenAppsLoaded) return;
        const known = new Set(Object.keys(root.seenApps));
        let added = false;
        for (const notif of root.list) {
            const key = root.appKey(notif.appName, notif.desktopEntry);
            if (known.has(key)) continue;
            root.rememberApp(key, notif.appName, notif.appIcon, notif.desktopEntry, notif.time); // Keeps the newest time
            added = true;
        }
        if (added) seenAppsWriteTimer.restart();
    }
    function discardApp(key) {
        root.list.filter(notif => root.appKey(notif.appName, notif.desktopEntry) === key)
            .map(notif => notif.notificationId)
            .forEach(id => root.discardNotification(id));
    }
    FileView {
        id: seenAppsFile
        path: Directories.notificationAppsPath
        onLoaded: {
            try {
                const apps = Object.assign(Object.create(null), JSON.parse(seenAppsFile.text()));
                for (const app of Object.values(apps)) app.icon = NotificationUtils.appIcon(app.icon);
                root.seenApps = apps;
            } catch (e) {
                root.seenApps = Object.create(null);
            }
            root.seenAppsLoaded = true;
            root.seedSeenApps();
        }
        onLoadFailed: error => {
            root.seenAppsLoaded = true;
            root.seedSeenApps();
            seenAppsWriteTimer.restart();
        }
    }
    Timer {
        id: seenAppsWriteTimer
        interval: 1500
        onTriggered: seenAppsFile.setText(JSON.stringify(root.seenApps, null, 2))
    }

    IpcHandler {
        target: "notifications"
        function toggleSilent(): void { root.toggleSilent(); }
        function setSilent(on: bool): void { NotificationPreferences.setQuiet(on); }
        function silenceFor(minutes: int): void {
            if (minutes > 0 && minutes <= 1440) NotificationPreferences.setQuiet(true, minutes);
        }
        function previewBanner(): bool { return root.showPreview(); }
        function clearApp(key: string): void { root.discardApp(key) }
        function forgetApp(key: string): void {
            delete root.seenApps[key];
            seenAppsWriteTimer.restart();
        }
    }
    property var filePath: Directories.notificationsPath
    property list<Notif> list: []
    property Notif preview: null
    readonly property var popupList: {
        const live = list.filter(notif => notif?.popup);
        return preview ? [...live, preview] : live;
    }
    readonly property bool centerOpen: Config.options.panelFamily !== "waffle" && SidebarLayout.sideOf("notifications") === "left"
        ? GlobalStates.sidebarLeftOpen : GlobalStates.sidebarRightOpen

    function showPreview() {
        if (GlobalStates.screenLocked) return false;
        if (!root.preview) {
            root.preview = notifComponent.createObject(root, {
                notificationId: -1, popup: true, time: Date.now(),
                appName: Translation.tr("Notification preview"), appIcon: "preferences-system-notifications",
                summary: Translation.tr("Test banner"), body: Translation.tr("Your notifications will appear here.")
            });
        }
        previewTimer.restart();
        return true;
    }
    function clearPreview() {
        const old = root.preview;
        root.preview = null;
        previewTimer.stop();
        old?.destroy();
    }
    Timer {
        id: previewTimer
        interval: Math.max(1, Config.options.notifications.timeout)
        onTriggered: root.clearPreview()
    }
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() { if (GlobalStates.screenLocked) root.clearPreview(); }
    }
    property var latestTimeForApp: Object.create(null)
    Component {
        id: notifComponent
        Notif {}
    }
    Component {
        id: notifTimerComponent
        NotifTimer {}
    }

    function stringifyList(list) {
        return JSON.stringify(list.filter(notif => notif).map((notif) => notifToJSON(notif)), null, 2);
    }
    
    onListChanged: {
        // Update latest time for each app
        root.list.forEach((notif) => {
            if (!root.latestTimeForApp[notif.appName] || notif.time > root.latestTimeForApp[notif.appName]) {
                root.latestTimeForApp[notif.appName] = Math.max(root.latestTimeForApp[notif.appName] || 0, notif.time);
            }
        });
        // Remove apps that no longer have notifications
        Object.keys(root.latestTimeForApp).forEach((appName) => {
            if (!root.list.some((notif) => notif.appName === appName)) {
                delete root.latestTimeForApp[appName];
            }
        });
    }

    function appNameListForGroups(groups) {
        return Object.keys(groups).sort((a, b) => {
            // Sort by time, descending
            return groups[b].time - groups[a].time;
        });
    }

    function groupsForList(list) {
        const groups = Object.create(null);
        list.filter(notif => notif).forEach((notif) => { // Destroyed notifications leave null entries for a moment
            if (!groups[notif.appName]) {
                groups[notif.appName] = {
                    appName: notif.appName,
                    appIcon: notif.appIcon,
                    desktopEntry: notif.desktopEntry,
                    notifications: [],
                    time: 0
                };
            }
            groups[notif.appName].notifications.push(notif);
            // Always set to the latest time in the group
            groups[notif.appName].time = latestTimeForApp[notif.appName] || notif.time;
        });
        return groups;
    }

    property var groupsByAppName: groupsForList(root.list)
    property var popupGroupsByAppName: groupsForList(root.popupList)
    property list<string> appNameList: appNameListForGroups(root.groupsByAppName)
    property list<string> popupAppNameList: appNameListForGroups(root.popupGroupsByAppName)

    // Quickshell's notification IDs starts at 1 on each run, while saved notifications
    // can already contain higher IDs. This is for avoiding id collisions
    property int idOffset
    signal initDone();
    signal notify(notification: var);
    signal discard(id: int);
    signal discardAll();
    signal timeout(id: var);

	NotificationServer {
        id: notifServer
        // actionIconsSupported: true
        actionsSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: false
        bodyMarkupSupported: true
        bodySupported: true
        imageSupported: true
        keepOnReload: false
        persistenceSupported: true

        onNotification: (notification) => {
            const key = root.appKey(notification.appName, notification.desktopEntry);
            root.rememberApp(key, notification.appName, notification.appIcon, notification.desktopEntry);
            const rule = root.ruleFor(key);
            if (rule.mode === "off") return; // Left untracked, so the server drops it
            notification.tracked = true
            const newNotifObject = notifComponent.createObject(root, {
                "notificationId": notification.id + root.idOffset,
                "notification": notification,
                "time": Date.now(),
            });
			root.list = [...root.list, newNotifObject];

            // Popup: not for apps set to "only in the list"; apps allowed through do not disturb still pop up
            const showPopup = rule.mode !== "silent" && !root.centerOpen && (!root.silent || rule.bypassDnd === true);
            if (!root.centerOpen) root.unread++;
            if (showPopup) {
                newNotifObject.popup = true;
                if (notification.expireTimeout != 0) {
                    newNotifObject.timer = notifTimerComponent.createObject(newNotifObject, {
                        "owner": newNotifObject,
                        "interval": notification.expireTimeout < 0 ? (Config?.options.notifications.timeout ?? 7000) : notification.expireTimeout,
                    });
                }
            }
            root.notify(newNotifObject);
            // console.log(notifToString(newNotifObject));
            notifFileView.setText(stringifyList(root.list));
        }
    }

    function markAllRead() {
        root.unread = 0;
    }

    function discardNotification(id) {
        if (id === -1) { root.clearPreview(); return; }
        const notif = root.list.find(n => n?.notificationId === id);
        if (!notif) return;
        // Dismissing the server object can synchronously report the same closure.
        root.list = root.list.filter(n => n && n !== notif);
        notifFileView.setText(stringifyList(root.list));
        notif.release();
        root.discard(id);
    }

    function discardAllNotifications() {
        const removed = root.list.slice();
        root.list = [];
        notifFileView.setText(stringifyList(root.list));
        for (const notif of removed) notif?.release();
        root.discardAll();
    }

    function cancelTimeout(id) {
        if (id === -1) { previewTimer.stop(); return; }
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        root.list[index]?.timer?.stop();
    }

    function timeoutNotification(id) {
        if (id === -1) { root.clearPreview(); return; }
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        if (root.list[index] != null)
            root.list[index].popup = false;
        root.timeout(id);
    }

    function timeoutAll() {
        root.clearPreview();
        root.popupList.forEach((notif) => {
            root.timeout(notif.notificationId);
        })
        root.popupList.forEach((notif) => {
            notif.popup = false;
        });
    }

    function attemptInvokeAction(id, notifIdentifier) {
        console.log("[Notifications] Attempting to invoke action with identifier: " + notifIdentifier + " for notification ID: " + id);
        const notifServerIndex = notifServer.trackedNotifications.values.findIndex((notif) => notif.id + root.idOffset === id);
        console.log("Notification server index: " + notifServerIndex);
        if (notifServerIndex !== -1) {
            const notifServerNotif = notifServer.trackedNotifications.values[notifServerIndex];
            const action = notifServerNotif.actions.find((action) => action.identifier === notifIdentifier);
            // console.log("Action found: " + JSON.stringify(action));
            action.invoke()
        } 
        else {
            console.log("Notification not found in server: " + id)
        }
        root.discardNotification(id);
    }

    function refresh() {
        notifFileView.reload()
    }

    Component.onCompleted: {
        refresh()
    }

    FileView {
        id: notifFileView
        path: Qt.resolvedUrl(filePath)
        onLoaded: {
            const fileContents = notifFileView.text()
            root.list = JSON.parse(fileContents).map((notif) => {
                return notifComponent.createObject(root, {
                    "notificationId": notif.notificationId,
                    "actions": [], // Notification actions are meaningless if they're not tracked by the server or the sender is dead
                    "appIcon": NotificationUtils.appIcon(notif.appIcon),
                    "appName": notif.appName,
                    "desktopEntry": notif.desktopEntry ?? "",
                    "body": notif.body,
                    // image://qsimage handles belong to the previous session's notifications and are always dead now
                    "image": (notif.image ?? "").startsWith("image://qsimage/") ? "" : NotificationUtils.localImage(notif.image),
                    "summary": notif.summary,
                    "time": notif.time,
                    "urgency": notif.urgency,
                });
            });
            // Find largest notificationId
            let maxId = 0
            root.list.forEach((notif) => {
                maxId = Math.max(maxId, notif.notificationId)
            })

            console.log("[Notifications] File loaded")
            root.idOffset = maxId
            root.seedSeenApps()
            root.initDone()
        }
        onLoadFailed: (error) => {
            if(error == FileViewError.FileNotFound) {
                console.log("[Notifications] File not found, creating new file.")
                root.list = []
                notifFileView.setText(stringifyList(root.list));
            } else {
                console.log("[Notifications] Error loading file: " + error)
            }
        }
    }
}
