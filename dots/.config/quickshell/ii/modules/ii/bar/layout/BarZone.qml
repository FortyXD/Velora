import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.bar
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

/**
 * One of the five bar zones: lays out its widgets in runs (pills), and handles clicks and
 * scrolling on the free space between them according to the zone's actions.
 */
FocusedScrollMouseArea {
    id: root

    required property string zoneName
    required property var items
    required property QtObject factory
    property var actions: ({})
    property bool vertical: false
    property int tier: 0
    property bool editing: false
    property real fixedLength: -1 // Set when the center is balanced
    property real outerPadding: 0 // Toward the screen edge
    property real innerPadding: 0 // Toward the center
    property real spacing: 4
    // Where items gather when none of them takes the free space: start, end or center
    property string align: "start"
    property string outerSide: "" // "left" or "right": where the scroll hint goes

    signal menuRequested(real x, real y) // Right click on the free space

    readonly property var segments: BarLayoutUtils.segments(items, Config.options.bar.style.islands)
    readonly property var segmentItems: {
        let result = [];
        for (let i = 0; i < repeater.count; i++) {
            const segment = repeater.itemAt(i);
            if (segment) result.push(segment);
        }
        return result;
    }
    // Checked by content, not `visible`, which is also false while the zone itself is hidden
    readonly property var shownSegments: segmentItems.filter(segment => segment.shownCount > 0)
    readonly property bool hasContent: shownSegments.length > 0
    readonly property bool anyFill: shownSegments.some(segment => segment.fills)
    readonly property real rigidWidth: shownSegments.length === 0 ? 0
        : shownSegments.reduce((sum, segment) => sum + segment.rigidWidth, 0) + root.spacing * (shownSegments.length - 1)

    readonly property real startPadding: outerSide === "right" ? innerPadding : outerPadding
    // Widgets taking part in the layout, in visual order
    function orderedHosts() {
        let result = [];
        for (const segment of root.shownSegments) result.push(...segment.hosts.filter(host => host.present));
        return result;
    }
    readonly property real endPadding: outerSide === "right" ? outerPadding : innerPadding

    implicitWidth: fixedLength >= 0 ? fixedLength : Math.max(editing && !hasContent ? 56 : 0, rowLayout.implicitWidth + startPadding + endPadding)
    implicitHeight: Appearance.sizes.baseBarHeight
    Behavior on implicitWidth {
        enabled: root.fixedLength >= 0
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    acceptedButtons: (actions.click && actions.click !== "none" ? Qt.LeftButton : Qt.NoButton)
        | (actions.middleClick && actions.middleClick !== "none" ? Qt.MiddleButton : Qt.NoButton)
        | Qt.RightButton

    function runAction(action) {
        switch (action) {
        case "sidebarLeft":
            GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
            break;
        case "sidebarRight":
            GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
            break;
        case "overview":
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
            break;
        case "session":
            GlobalStates.sessionOpen = !GlobalStates.sessionOpen;
            break;
        case "wallpaperSelector":
            GlobalStates.wallpaperSelectorOpen = !GlobalStates.wallpaperSelectorOpen;
            break;
        case "mediaPlayPause":
            MprisController.activePlayer?.togglePlaying();
            break;
        case "muteToggle":
            Audio.toggleMute();
            break;
        }
    }

    function scroll(up) {
        switch (actions.scroll) {
        case "brightness":
            if (up) Brightness.increaseBrightness();
            else Brightness.decreaseBrightness();
            break;
        case "volume":
            if (up) Audio.incrementVolume();
            else Audio.decrementVolume();
            break;
        case "workspaces":
            Hyprland.dispatch(`hl.dsp.focus({ workspace = "${up ? "r-1" : "r+1"}" })`);
            break;
        }
    }

    onScrollUp: scroll(true)
    onScrollDown: scroll(false)
    onMovedAway: {
        if (actions.scroll === "brightness") GlobalStates.osdBrightnessOpen = false;
        else if (actions.scroll === "volume") GlobalStates.osdVolumeOpen = false;
    }
    onPressed: event => {
        if (event.button === Qt.LeftButton) runAction(actions.click);
        else if (event.button === Qt.MiddleButton) runAction(actions.middleClick);
        else if (event.button === Qt.RightButton) root.menuRequested(event.x, event.y);
    }

    Loader {
        active: root.outerSide.length > 0 && ["brightness", "volume", "workspaces"].includes(root.actions.scroll)
        anchors.left: root.outerSide === "left" ? parent.left : undefined
        anchors.right: root.outerSide === "right" ? parent.right : undefined
        anchors.verticalCenter: parent.verticalCenter
        sourceComponent: ScrollHint {
            reveal: root.hovered
            side: root.outerSide
            icon: root.actions.scroll === "volume" ? "volume_up"
                : root.actions.scroll === "workspaces" ? "view_carousel"
                : Hyprsunset.gamma === 100 ? "light_mode" : "wb_twilight"
            tooltipText: root.actions.scroll === "volume" ? Translation.tr("Scroll to change volume")
                : root.actions.scroll === "workspaces" ? Translation.tr("Scroll to switch workspaces")
                : Translation.tr("Scroll to change brightness")
        }
    }

    Rectangle { // Drop target for an empty zone while editing
        visible: root.editing && !root.hasContent
        anchors {
            fill: parent
            topMargin: 6
            bottomMargin: 6
            leftMargin: 4
            rightMargin: 4
        }
        radius: Appearance.rounding.small
        color: "transparent"
        border.width: 1
        border.color: Appearance.colors.colOutline
        MaterialSymbol {
            anchors.centerIn: parent
            text: "add"
            iconSize: 16
            color: Appearance.colors.colSubtext
        }
    }

    RowLayout {
        id: rowLayout
        anchors {
            fill: parent
            leftMargin: root.startPadding
            rightMargin: root.endPadding
        }
        spacing: root.spacing

        Item { // Free space before the items
            visible: !root.anyFill && (root.align === "end" || root.align === "center")
            Layout.fillWidth: true
        }

        Repeater {
            id: repeater
            model: ScriptModel {
                values: root.segments
                comparisonMode: ObjectComparison.Structure
            }
            delegate: BarSegment {
                required property var modelData
                segment: modelData
                factory: root.factory
                vertical: root.vertical
                tier: root.tier
                zoneHovered: root.hovered
                editing: root.editing
                Layout.fillWidth: fills
            }
        }

        Item { // Free space after the items
            visible: !root.anyFill && (root.align === "start" || root.align === "center")
            Layout.fillWidth: true
        }
    }
}
