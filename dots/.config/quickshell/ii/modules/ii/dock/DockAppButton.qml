import qs.services
import qs.modules.common
import QtQuick
import QtQuick.Window
import Quickshell

/**
 * A pinned or running app in the dock. Also renders the separator entry
 * between pinned and running apps.
 */
DockTile {
    id: root

    required property var modelData
    readonly property string appId: modelData.appId
    readonly property var toplevels: modelData.toplevels ?? []
    readonly property int windowCount: toplevels.length
    readonly property bool active: toplevels.some(t => t.activated)
    readonly property bool urgent: toplevels.some(t => t.HyprlandToplevel?.urgent ?? false)
    property int lastFocused: -1

    separator: appId === "SEPARATOR"
    tint: !separator && Config.options.dock.monochromeIcons
    label: separator ? "" : TaskbarApps.displayName(appId)
    showIndicator: windowCount > 0
    indicatorActive: active
    bouncing: !separator && TaskbarApps.launchingApps[appId] !== undefined

    onActiveChanged: {
        if (active) root.lastFocused = toplevels.findIndex(t => t.activated);
    }
    onUrgentChanged: {
        if (urgent && !active) root.attentionBounces = 2;
    }

    // Slide in and out instead of popping
    ListView.onAdd: appearAnim.restart()
    ListView.onRemove: removeAnim.start()
    NumberAnimation {
        id: appearAnim
        target: root
        property: "appear"
        from: 0
        to: 1
        duration: 340
        easing.type: Easing.OutCubic
    }
    SequentialAnimation {
        id: removeAnim
        PropertyAction {
            target: root
            property: "ListView.delayRemove"
            value: true
        }
        NumberAnimation {
            target: root
            property: "appear"
            to: 0
            duration: 280
            easing.type: Easing.InOutCubic
        }
        PropertyAction {
            target: root
            property: "ListView.delayRemove"
            value: false
        }
    }

    onClicked: {
        if (root.separator) return;
        root.dock.tileActivated(root);
        if (root.windowCount === 0) {
            TaskbarApps.launch(root.appId, 0);
            return;
        }
        // Clicking the focused app cycles through its windows
        const activeIndex = root.toplevels.findIndex(t => t.activated);
        let target = activeIndex >= 0 ? (activeIndex + 1) % root.windowCount
            : (root.lastFocused >= 0 && root.lastFocused < root.windowCount ? root.lastFocused : root.windowCount - 1);
        root.lastFocused = target;
        root.toplevels[target].activate();
    }

    onMiddleClicked: {
        if (root.separator) return;
        root.dock.tileActivated(root);
        TaskbarApps.launch(root.appId, root.windowCount);
    }

    onRightClicked: {
        if (root.separator) root.dock.dockMenuRequested(root);
        else root.dock.appMenuRequested(root);
    }

    Image {
        visible: !root.separator
        anchors.fill: parent
        source: root.separator ? "" : Quickshell.iconPath(TaskbarApps.iconFor(root.appId), "application-x-executable")
        // Load at the magnified size so zoomed icons stay sharp
        sourceSize.width: root.dock.iconSize * root.dock.maxScale * Screen.devicePixelRatio
        sourceSize.height: root.dock.iconSize * root.dock.maxScale * Screen.devicePixelRatio
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
    }
}
