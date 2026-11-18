pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * A sidebar drawn from its settings (SidebarLayout), for either side: its parts in their order, sized like
 * the real one (parts that fill share what's left), each with a sketch of what it shows. Drag a part up or
 * down and the others make room; click one (or a tab of tabs) to pick it; the eye hides it, and hidden parts
 * stay as a thin line so they can come back. Dragged out of the picture, a part turns red and is removed
 * when let go.
 */
Rectangle {
    id: root
    required property string side
    property string selectedUid: ""
    property bool editable: true
    property var catalogTarget: null
    signal partClicked(string uid)
    signal partRemoved(string uid)

    readonly property real padding: 8
    readonly property real gap: 6
    readonly property real hiddenHeight: 22
    radius: 20
    color: Appearance.colors.colLayer0
    border.width: 1
    border.color: Appearance.colors.colLayer0Border

    readonly property var parts: SidebarLayout.parts(root.side)
    readonly property var shownParts: root.parts.filter(part => SidebarLayout.shown(part))
    readonly property bool hasRest: root.shownParts.some(part => root.fills(part) && root.shareOf(part) <= 0)
    readonly property real innerHeight: root.height - root.padding * 2

    function fills(part) {
        return (SidebarCatalog.part(part.type)?.fill ?? false) && !root.isFolded(part);
    }
    function shareOf(part) {
        return part.type === "tabs" ? (part.options?.share ?? 0) : 0;
    }
    function isFolded(part) {
        return part.type === "tabs" && part.options?.style === "rail" && part.options?.collapsible && SidebarLayout.tabState(part.uid).collapsed;
    }

    // Quick toggles, laid out as in the sidebar
    readonly property int columns: Config.options.sidebar.quickToggles.android.columns
    readonly property bool classic: Config.options.sidebar.quickToggles.style === "classic"
    readonly property var toggleRows: {
        let rows = [];
        let row = [];
        let used = 0;
        for (const t of SidebarLayout.androidToggles()) {
            const size = Math.min(t.size, root.columns);
            if (used + size > root.columns && row.length > 0) {
                rows.push(row);
                row = [];
                used = 0;
            }
            row.push({ "type": t.type, "size": size });
            used += size;
        }
        if (row.length > 0) rows.push(row);
        return rows;
    }
    readonly property var slidersShown: {
        const s = Config.options.sidebar.quickSliders;
        return [s.showBrightness ? "brightness_6" : "", s.showVolume ? "volume_up" : "", s.showMic ? "mic" : ""].filter(i => i.length > 0);
    }

    // The height a part gets: its own for most, a share or the rest for parts that fill
    function fixedHeight(part) {
        if (!SidebarLayout.shown(part)) return root.hiddenHeight;
        const options = SidebarLayout.optionsOf(part);
        switch (part.type) {
            case "header": return 30;
            case "sliders": return Math.max(1, root.slidersShown.length) * 20 + 10;
            case "toggles": return root.classic ? 40 : Math.max(1, root.toggleRows.length) * 34 + 10;
            case "media": return 64;
            case "weather": return 46 + (options.showHours ? 34 : 0) + (options.showDays ? 48 : 0) + (options.showDetails ? 52 : 0);
            case "system": return 74;
            case "tools": return Math.ceil((options.items ?? SidebarCatalog.defaultTools).length / Math.max(3, options.columns ?? 4)) * (options.labels ? 38 : 30) + 10;
        }
        if (root.isFolded(part)) return 34;
        if (root.shareOf(part) > 0 && root.hasRest) return Math.round(root.innerHeight * root.shareOf(part));
        return -1;
    }
    function heightOf(part) {
        const fixed = root.fixedHeight(part);
        if (fixed >= 0) return fixed;
        const others = root.parts.filter(p => p.uid !== part.uid).reduce((sum, p) => sum + Math.max(0, root.fixedHeight(p)), 0);
        const restCount = Math.max(1, root.parts.filter(p => root.fixedHeight(p) < 0).length);
        return Math.max(40, (root.innerHeight - root.gap * (root.parts.length - 1) - others) / restCount);
    }

    // Dragging a part: the others slide out of its way while it follows the pointer
    property string dragUid: ""
    property int dragTarget: -1 // Index among the parts without the dragged one
    property real dragY: 0
    property real dragX: 0
    property bool dragRemoving: false // Out of the picture: the others close the gap
    readonly property var order: root.parts.map(part => part.uid)
    readonly property var previewOrder: {
        if (root.dragUid.length === 0 || root.dragTarget < 0) return root.order;
        let others = root.order.filter(uid => uid !== root.dragUid);
        if (root.dragRemoving) return others;
        others.splice(root.dragTarget, 0, root.dragUid);
        return others;
    }
    function partOf(uid) {
        return root.parts.find(part => part.uid === uid) ?? null;
    }
    function topOf(uid, list) {
        let y = 0;
        for (const u of list) {
            if (u === uid) return y;
            y += root.heightOf(root.partOf(u)) + root.gap;
        }
        return y;
    }
    function targetFor(uid, center) {
        let y = 0;
        let index = 0;
        for (const u of root.order.filter(u => u !== uid)) {
            const h = root.heightOf(root.partOf(u));
            if (center > y + h / 2) index++;
            y += h + root.gap;
        }
        return index;
    }

    // The middle of a tab group accepts a page; its top and bottom edges stay available for insertion.
    function catalogTargetAt(sceneX, sceneY, type) {
        const p = root.mapFromItem(null, sceneX, sceneY);
        if (!root.enabled || !root.contains(p)) return null;
        const tabbable = SidebarCatalog.part(type)?.tabbable;
        let lineY = root.padding / 2;
        for (let i = 0; i < cards.count; i++) {
            const card = cards.itemAt(i);
            if (!card) continue;
            const top = root.padding + card.y - column.contentY;
            const edge = Math.min(16, card.height / 4);
            if (tabbable && card.type === "tabs" && !card.modelData.hidden && p.y >= top + edge && p.y < top + card.height - edge) {
                const visibleTop = Math.max(root.padding, top);
                return {groupUid: card.uid, index: (card.modelData.tabs ?? []).length, pointerY: p.y,
                    y: visibleTop, height: Math.max(2, Math.min(root.height - root.padding, top + card.height) - visibleTop)};
            }
            if (p.y < top + card.height / 2) return {groupUid: "", index: i, pointerY: p.y, y: lineY, height: 3};
            lineY = Math.max(3, Math.min(root.height - 4, top + card.height + root.gap / 2));
        }
        return {groupUid: "", index: root.parts.length, pointerY: p.y, y: lineY, height: 3};
    }

    StyledText {
        visible: root.parts.length === 0
        anchors.centerIn: parent
        width: parent.width - 40
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: Translation.tr("Empty. Add parts from the list beside it.")
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colSubtext
    }

    StyledFlickable {
        id: column
        objectName: "sidebarPreviewScroll"
        anchors {
            fill: parent
            margins: root.padding
        }
        contentWidth: width
        contentHeight: Math.max(height, root.parts.reduce((h, part) => h + root.heightOf(part) + root.gap, -root.gap))
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: root.dragUid === ""

        Timer {
            readonly property real step: !root.catalogTarget ? 0
                : root.catalogTarget.pointerY < 26 ? -8 : root.catalogTarget.pointerY > root.height - 26 ? 8 : 0
            running: (step < 0 && column.contentY > 0) || (step > 0 && column.contentY < column.contentHeight - column.height)
            interval: 20; repeat: true
            onTriggered: column.contentY = Math.max(0, Math.min(column.contentHeight - column.height, column.contentY + step))
        }

        Repeater {
            id: cards
            model: root.parts
            delegate: Rectangle {
                id: card
                required property var modelData
                readonly property string uid: modelData.uid
                readonly property string type: modelData.type
                readonly property bool shown: SidebarLayout.shown(modelData)
                readonly property bool picked: root.selectedUid === card.uid || (modelData.tabs ?? []).some(tab => tab.uid === root.selectedUid)
                readonly property bool dragging: root.dragUid === card.uid
                readonly property bool removing: card.dragging && root.dragRemoving
                width: column.width
                height: root.heightOf(modelData)
                x: card.dragging ? root.dragX : 0
                y: card.dragging ? root.dragY : root.topOf(card.uid, root.previewOrder)
                Behavior on x {
                    enabled: !card.dragging
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on y {
                    enabled: !card.dragging
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on height {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                radius: card.shown ? 12 : height / 2
                color: card.removing ? Appearance.colors.colErrorContainer
                    : !card.shown || card.type === "header" ? "transparent" : Appearance.colors.colLayer1
                border.width: card.picked || card.dragging ? 2 : (card.shown ? 0 : 1)
                border.color: card.removing ? Appearance.colors.colError
                    : card.picked || card.dragging ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                z: card.dragging ? 5 : 1
                scale: card.dragging ? 1.03 : 1
                Behavior on scale {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                clip: true

                MouseArea {
                    id: cardArea
                    anchors.fill: parent
                    hoverEnabled: true
                    preventStealing: true // The settings page must not scroll away with the drag
                    cursorShape: !root.editable ? Qt.PointingHandCursor : (card.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
                    property point start
                    property point grabOffset
                    onPressed: mouse => {
                        start = mapToItem(column.contentItem, mouse.x, mouse.y);
                        grabOffset = Qt.point(start.x - card.x, start.y - card.y);
                    }
                    onPositionChanged: mouse => {
                        if (!pressed || !root.editable) return;
                        const p = mapToItem(column.contentItem, mouse.x, mouse.y);
                        if (!card.dragging && Math.hypot(p.x - start.x, p.y - start.y) < 5) return;
                        const outside = mapToItem(root, mouse.x, mouse.y);
                        const slack = 24;
                        root.dragRemoving = outside.x < -slack || outside.y < -slack || outside.x > root.width + slack || outside.y > root.height + slack;
                        // Inside it only moves up and down; out of it, it follows the pointer
                        root.dragX = root.dragRemoving ? p.x - grabOffset.x : 0;
                        root.dragY = root.dragRemoving ? p.y - grabOffset.y : Math.max(0, Math.min(column.contentHeight - card.height, p.y - grabOffset.y));
                        root.dragTarget = root.targetFor(card.uid, root.dragY + card.height / 2);
                        root.dragUid = card.uid;
                    }
                    onReleased: {
                        // Reset first: moving rebuilds this card
                        const moved = card.dragging;
                        const removing = card.removing;
                        const uid = card.uid;
                        const target = root.dragTarget;
                        root.dragUid = "";
                        root.dragTarget = -1;
                        root.dragRemoving = false;
                        if (removing) {
                            root.partRemoved(uid);
                            SidebarLayout.remove(uid);
                        }
                        else if (moved) SidebarLayout.move(uid, root.side, target);
                        else root.partClicked(uid);
                    }
                    onCanceled: {
                        root.dragUid = "";
                        root.dragTarget = -1;
                        root.dragRemoving = false;
                    }
                }

                // What it shows
                PartSketch {
                    anchors {
                        fill: parent
                        margins: card.type === "header" ? 0 : 6
                    }
                    visible: card.shown
                    opacity: card.removing ? 0.3 : 1
                    part: card.modelData
                    mockup: root
                }
                Row { // Out of the picture: it goes away when let go
                    visible: card.removing
                    anchors.centerIn: parent
                    spacing: 6
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "delete"
                        iconSize: 22
                        color: Appearance.colors.colOnErrorContainer
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Translation.tr("Release to remove")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnErrorContainer
                    }
                }
                StyledText {
                    visible: !card.shown
                    anchors.centerIn: parent
                    text: Translation.tr("%1 (hidden)").arg(SidebarCatalog.part(card.type)?.name ?? "")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }

                RippleButton { // Eye: show or hide
                    visible: root.editable && !card.dragging && (cardArea.containsMouse || card.picked || !card.shown)
                    anchors {
                        right: parent.right
                        verticalCenter: card.shown ? undefined : parent.verticalCenter
                        top: card.shown ? parent.top : undefined
                        margins: card.shown ? 4 : 0
                        rightMargin: 4
                    }
                    implicitWidth: 22
                    implicitHeight: 22
                    buttonRadius: 11
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    onClicked: SidebarLayout.setHidden(card.uid, card.shown)
                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        text: card.shown ? "visibility" : "visibility_off"
                        iconSize: 14
                        color: Appearance.colors.colOnLayer2
                    }
                    StyledToolTip {
                        text: card.shown ? Translation.tr("Hide") : Translation.tr("Show")
                    }
                }
            }
        }
    }
    Rectangle {
        id: placement
        objectName: "sidebarInsertionGuide"
        visible: root.catalogTarget !== null
        readonly property bool intoTabs: !!root.catalogTarget?.groupUid
        x: root.padding
        y: root.catalogTarget?.y ?? 0
        width: parent.width - 2 * root.padding
        height: root.catalogTarget?.height ?? 0
        radius: intoTabs ? 12 : 2
        color: intoTabs ? ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.14) : Appearance.colors.colPrimary
        border.width: intoTabs ? 2 : 0
        border.color: Appearance.colors.colPrimary
        Rectangle {
            visible: placement.intoTabs
            anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 5
            width: hint.implicitWidth + 14; height: hint.implicitHeight + 4; radius: height / 2
            color: Appearance.colors.colPrimary
            StyledText {
                id: hint; anchors.centerIn: parent
                text: Translation.tr("Into tabs")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnPrimary
            }
        }
    }
}
