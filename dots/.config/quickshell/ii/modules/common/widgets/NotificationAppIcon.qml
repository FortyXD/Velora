import qs.modules.common
import qs.modules.common.functions
import Qt5Compat.GraphicalEffects
import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications

MaterialShape { // App icon
    id: root
    property var appIcon: ""
    property string appName: "" // Helps find the icon through the app's desktop entry
    property string desktopEntry: "" // The notification's desktop-entry hint, the most reliable key
    property var summary: ""
    property var urgency: NotificationUrgency.Normal
    property bool isUrgent: urgency === NotificationUrgency.Critical
    property var image: ""
    property real materialIconScale: 0.57
    property real appIconScale: 0.8
    property real smallAppIconScale: 0.49
    property real materialIconSize: implicitSize * materialIconScale
    property real appIconSize: implicitSize * appIconScale
    property real smallAppIconSize: implicitSize * smallAppIconScale

    // The icon name may not exist in the theme (or be a stale path): try the theme, then the app's
    // desktop entry. Empty when nothing is found, so a broken "image-missing" icon is never shown.
    readonly property string resolvedAppIcon: {
        const icon = root.appIcon ?? "";
        if (icon.startsWith("/") || icon.startsWith("file:")) return icon.startsWith("/") ? `file://${icon}` : icon;
        const direct = icon.length > 0 ? Quickshell.iconPath(icon, true) : "";
        if (direct.length > 0) return direct;
        const entry = (root.desktopEntry.length > 0 ? DesktopEntries.byId(root.desktopEntry) : null)
            ?? (icon.length > 0 ? DesktopEntries.heuristicLookup(icon) : null)
            ?? (root.appName.length > 0 ? (DesktopEntries.heuristicLookup(root.appName)
                ?? DesktopEntries.heuristicLookup(root.appName.split(" ")[0])) : null); // "Telegram Desktop" -> "Telegram"
        return entry?.icon ? Quickshell.iconPath(entry.icon, true) : "";
    }
    // Notification images are only valid while the sender keeps the notification;
    // when one can't be loaded, show the app icon instead of an empty circle
    property bool imageFailed: false
    onImageChanged: imageFailed = false
    readonly property bool showImage: (root.image ?? "") != "" && !root.imageFailed
    property bool appIconFailed: false
    onResolvedAppIconChanged: appIconFailed = false
    readonly property bool showAppIcon: root.resolvedAppIcon != "" && !root.appIconFailed

    implicitSize: 38 * scale
    property list<var> urgentShapes: [
        MaterialShape.Shape.VerySunny,
        MaterialShape.Shape.SoftBurst,
    ]
    shape: isUrgent ? urgentShapes[Math.floor(Math.random() * urgentShapes.length)] : MaterialShape.Shape.Circle

    color: isUrgent ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer
    Loader {
        id: materialSymbolLoader
        active: !root.showImage && !root.showAppIcon
        anchors.fill: parent
        sourceComponent: MaterialSymbol {
            text: {
                const defaultIcon = NotificationUtils.findSuitableMaterialSymbol("")
                const guessedIcon = NotificationUtils.findSuitableMaterialSymbol(root.summary)
                return (root.urgency == NotificationUrgency.Critical && guessedIcon === defaultIcon) ?
                    "priority_high" : guessedIcon
            }
            anchors.fill: parent
            color: isUrgent ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
            iconSize: root.materialIconSize
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
    Loader {
        id: appIconLoader
        active: !root.showImage && root.showAppIcon
        anchors.centerIn: parent
        sourceComponent: IconImage {
            id: appIconImage
            implicitSize: root.appIconSize
            asynchronous: true
            source: root.resolvedAppIcon
            onStatusChanged: if (status === Image.Error) root.appIconFailed = true
        }
    }
    Loader {
        id: notifImageLoader
        active: root.showImage
        anchors.fill: parent
        sourceComponent: Item {
            anchors.fill: parent
            StyledImage {
                id: notifImage
                anchors.fill: parent
                readonly property int size: parent.width

                source: root.image
                fillMode: Image.PreserveAspectCrop
                cache: false
                antialiasing: true
                asynchronous: true
                onStatusChanged: if (status === Image.Error) root.imageFailed = true

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: notifImage.size
                        height: notifImage.size
                        radius: Appearance.rounding.full
                    }
                }
            }
            Loader {
                id: notifImageAppIconLoader
                active: root.showAppIcon
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                sourceComponent: IconImage {
                    implicitSize: root.smallAppIconSize
                    asynchronous: true
                    source: root.resolvedAppIcon
                    onStatusChanged: if (status === Image.Error) root.appIconFailed = true
                }
            }
        }
    }
}