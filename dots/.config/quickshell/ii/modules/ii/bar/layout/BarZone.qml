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
    property real fixedLength: -1 // Set when the center is balanced
    property real outerPadding: 0 // Toward the screen edge
    property real innerPadding: 0 // Toward the center
    property real spacing: 4
    property bool packToEnd: false // Without elastic widgets, items gather at the far end
    property string outerSide: "" // "left" or "right": where the scroll hint goes

    readonly property var segments: BarLayoutUtils.segments(items)
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
    readonly property real endPadding: outerSide === "right" ? outerPadding : innerPadding

    implicitWidth: fixedLength >= 0 ? fixedLength : (rowLayout.implicitWidth + startPadding + endPadding)
    implicitHeight: Appearance.sizes.baseBarHeight
    Behavior on implicitWidth {
        enabled: root.fixedLength >= 0
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    acceptedButtons: (actions.click && actions.click !== "none" ? Qt.LeftButton : Qt.NoButton)
        | (actions.middleClick && actions.middleClick !== "none" ? Qt.MiddleButton : Qt.NoButton)

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

    RowLayout {
        id: rowLayout
        anchors {
            fill: parent
            leftMargin: root.startPadding
            rightMargin: root.endPadding
        }
        spacing: root.spacing

        Item { // Pushes everything to the far end when nothing else takes the free space
            visible: root.packToEnd && !root.anyFill
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
                Layout.fillWidth: fills || (root.fixedLength >= 0 && root.shownSegments.length === 1)
            }
        }
    }
}
