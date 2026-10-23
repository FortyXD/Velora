import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * How many notifications wait and from which apps, never what they say.
 * With `liveData` off (the settings app, which must not start a notification server) an example.
 */
Rectangle {
    id: root
    property bool liveData: true
    // Newest app first, each once
    readonly property var apps: {
        if (!root.liveData) return [{ "appName": "Telegram", "appIcon": "telegram" }, { "appName": "Firefox", "appIcon": "firefox" }, { "appName": "Discord", "appIcon": "discord" }];
        let seen = [];
        let result = [];
        for (const notif of [...Notifications.list].reverse()) {
            const key = notif.appName || notif.appIcon;
            if (seen.includes(key)) continue;
            seen.push(key);
            result.push({ "appName": notif.appName, "appIcon": notif.appIcon });
        }
        return result;
    }
    readonly property int count: root.liveData ? Notifications.list.length : 4
    readonly property bool hasContent: root.count > 0

    implicitWidth: row.implicitWidth + 32
    implicitHeight: 56
    radius: height / 2
    color: Appearance.m3colors.m3surfaceContainer

    StyledRectangularShadow {
        target: root
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 10
        MaterialSymbol {
            text: "notifications"
            iconSize: Appearance.font.pixelSize.huge
            fill: 1
            color: Appearance.colors.colPrimary
        }
        StyledText {
            text: root.count === 1 ? Translation.tr("1 notification") : Translation.tr("%1 notifications").arg(root.count)
            font.pixelSize: Appearance.font.pixelSize.normal
            font.weight: Font.Medium
            color: Appearance.colors.colOnSurface
        }
        Row {
            spacing: -6
            Repeater {
                model: root.apps.slice(0, 5)
                delegate: NotificationAppIcon {
                    required property var modelData
                    implicitSize: 30
                    appIcon: modelData.appIcon
                    appName: modelData.appName
                }
            }
        }
        StyledText {
            visible: root.apps.length > 5
            text: `+${root.apps.length - 5}`
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnSurfaceVariant
        }
    }
}
