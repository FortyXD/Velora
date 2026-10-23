pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
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
        property string appIcon: notification?.appIcon ?? ""
        property string appName: notification?.appName ?? ""
        property string desktopEntry: notification?.desktopEntry ?? ""
        property string body: notification?.body ?? ""
        property string image: notification?.image ?? ""
        property string summary: notification?.summary ?? ""
        property double time
        property string urgency: notification?.urgency.toString() ?? "normal"
        property Timer timer

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
        required property int notificationId
        interval: 7000
        running: true
        onTriggered: () => {
            const index = root.list.findIndex((notif) => notif.notificationId === notificationId);
            const notifObject = root.list[index];
            print("[Notifications] Notification timer triggered for ID: " + notificationId + ", transient: " + notifObject?.isTransient);
            if (notifObject.isTransient) root.discardNotification(notificationId);
            else root.timeoutNotification(notificationId);
            destroy()
        }
    }

    property bool silent: false
    property int unread: 0
    // Do not disturb survives restarts; the settings app reads it from there and changes it over IPC
    onSilentChanged: if (Persistent.ready && Persistent.states.notifications.silent !== root.silent) Persistent.states.notifications.silent = root.silent
    Connections {
        target: Persistent
        function onReadyChanged() {
            if (Persistent.ready) root.silent = Persistent.states.notifications.silent;
        }
    }

    function appKey(appName, desktopEntry) {
        return (desktopEntry ?? "").length > 0 ? desktopEntry : ((appName ?? "").length > 0 ? appName : "unknown");
    }
    function ruleFor(key) {
        return Config.options?.notifications.apps?.[key] ?? {};
    }

    // Apps seen so far: { key: { name, icon, desktopEntry, count, lastSeen } }
    property var seenApps: ({})
    property bool seenAppsLoaded: false
    function rememberApp(key, appName, appIcon, desktopEntry, time = Date.now()) {
        const known = root.seenApps[key];
        root.seenApps[key] = {
            "name": appName || known?.name || key,
            "icon": appIcon || known?.icon || "",
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
                root.seenApps = JSON.parse(seenAppsFile.text()) ?? {};
            } catch (e) {
                root.seenApps = {};
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
        function toggleSilent(): void { root.silent = !root.silent }
        function setSilent(on: bool): void { root.silent = on }
        function clearApp(key: string): void { root.discardApp(key) }
        function forgetApp(key: string): void {
            delete root.seenApps[key];
            seenAppsWriteTimer.restart();
        }
    }
    property var filePath: Directories.notificationsPath
    property list<Notif> list: []
    property var popupList: list.filter((notif) => notif.popup);
    property bool popupInhibited: (GlobalStates?.sidebarRightOpen ?? false) || silent
    property var latestTimeForApp: ({})
    Component {
        id: notifComponent
        Notif {}
    }
    Component {
        id: notifTimerComponent
        NotifTimer {}
    }

    function stringifyList(list) {
        return JSON.stringify(list.map((notif) => notifToJSON(notif)), null, 2);
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
        const groups = {};
        list.forEach((notif) => {
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
        bodyImagesSupported: true
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
            const sidebarOpen = GlobalStates?.sidebarRightOpen ?? false;
            const showPopup = rule.mode !== "silent" && (!root.popupInhibited || (rule.bypassDnd === true && root.silent && !sidebarOpen));
            if (rule.mode === "silent") root.unread++;
            if (showPopup) {
                newNotifObject.popup = true;
                if (notification.expireTimeout != 0) {
                    newNotifObject.timer = notifTimerComponent.createObject(root, {
                        "notificationId": newNotifObject.notificationId,
                        "interval": notification.expireTimeout < 0 ? (Config?.options.notifications.timeout ?? 7000) : notification.expireTimeout,
                    });
                }
                root.unread++;
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
        console.log("[Notifications] Discarding notification with ID: " + id);
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        const notifServerIndex = notifServer.trackedNotifications.values.findIndex((notif) => notif.id + root.idOffset === id);
        if (index !== -1) {
            root.list.splice(index, 1);
            notifFileView.setText(stringifyList(root.list));
            triggerListChange()
        }
        if (notifServerIndex !== -1) {
            notifServer.trackedNotifications.values[notifServerIndex].dismiss()
        }
        root.discard(id); // Emit signal
    }

    function discardAllNotifications() {
        root.list = []
        triggerListChange()
        notifFileView.setText(stringifyList(root.list));
        notifServer.trackedNotifications.values.forEach((notif) => {
            notif.dismiss()
        })
        root.discardAll();
    }

    function cancelTimeout(id) {
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        if (root.list[index] != null)
            root.list[index].timer.stop();
    }

    function timeoutNotification(id) {
        const index = root.list.findIndex((notif) => notif.notificationId === id);
        if (root.list[index] != null)
            root.list[index].popup = false;
        root.timeout(id);
    }

    function timeoutAll() {
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

    function triggerListChange() {
        root.list = root.list.slice(0)
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
                    "appIcon": notif.appIcon,
                    "appName": notif.appName,
                    "desktopEntry": notif.desktopEntry ?? "",
                    "body": notif.body,
                    // image://qsimage handles belong to the previous session's notifications and are always dead now
                    "image": (notif.image ?? "").startsWith("image://qsimage/") ? "" : notif.image,
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
