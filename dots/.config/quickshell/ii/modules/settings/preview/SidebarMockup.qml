import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * The right sidebar drawn from its settings: sections in their order with their real contents
 * (which toggles, how many columns, which tabs). Drag a section up or down and the others make room;
 * click one to pick it; the eye hides it, and hidden sections stay as a thin line so they can come back.
 */
Rectangle {
    id: root
    property string selected: ""
    property bool editable: true // Drag to move and the eye to hide; off, a click only picks a section
    signal sectionClicked(string type)

    readonly property real widthFactor: Appearance.sizes.sidebarWidth / 460
    readonly property real padding: 8
    readonly property real gap: 6
    implicitWidth: Math.round(300 * root.widthFactor)
    implicitHeight: 620
    radius: 20
    color: Appearance.colors.colLayer0
    border.width: 1
    border.color: Appearance.colors.colLayer0Border

    readonly property var sections: SidebarLayout.sections
    readonly property var shownTypes: root.sections.filter(s => SidebarLayout.sectionShown(s.type)).map(s => s.type)
    readonly property string filling: root.shownTypes.includes("notifications") ? "notifications" : root.shownTypes.includes("widgets") ? "widgets" : ""

    // Heights: fixed for most, the filling section takes what's left
    readonly property real hiddenHeight: 22
    readonly property var slidersShown: {
        const s = Config.options.sidebar.quickSliders;
        return [s.showBrightness ? "brightness_6" : "", s.showVolume ? "volume_up" : "", s.showMic ? "mic" : ""].filter(i => i.length > 0);
    }
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
    function fixedHeight(type) {
        if (!SidebarLayout.sectionShown(type)) return root.hiddenHeight;
        if (type === "header") return 30;
        if (type === "sliders") return Math.max(1, root.slidersShown.length) * 20 + 10;
        if (type === "toggles") return root.classic ? 40 : Math.max(1, root.toggleRows.length) * 34 + 10;
        if (type === "widgets" && root.filling !== "widgets") return Math.round((root.height - root.padding * 2) * Math.max(0.2, Math.min(0.7, Config.options.sidebar.right.widgets.height)));
        return -1;
    }
    function heightOf(type) {
        const fixed = root.fixedHeight(type);
        if (fixed >= 0) return fixed;
        const others = root.sections.filter(s => s.type !== type).reduce((sum, s) => sum + Math.max(0, root.fixedHeight(s.type)), 0);
        return Math.max(40, root.height - root.padding * 2 - root.gap * (root.sections.length - 1) - others);
    }

    // Dragging a section: the others slide out of its way while it follows the pointer
    property string dragType: ""
    property int dragTarget: -1 // Index among the sections without the dragged one
    property real dragY: 0
    readonly property var order: root.sections.map(section => section.type)
    readonly property var previewOrder: {
        if (root.dragType.length === 0 || root.dragTarget < 0) return root.order;
        let others = root.order.filter(type => type !== root.dragType);
        others.splice(root.dragTarget, 0, root.dragType);
        return others;
    }
    function topOf(type, list) {
        let y = 0;
        for (const t of list) {
            if (t === type) return y;
            y += root.heightOf(t) + root.gap;
        }
        return y;
    }
    // Where a section whose middle is at `center` would land: after the header, between the others
    function targetFor(type, center) {
        const others = root.order.filter(t => t !== type);
        let y = 0;
        let index = 0;
        for (const t of others) {
            const h = root.heightOf(t);
            if (center > y + h / 2) index++;
            y += h + root.gap;
        }
        return Math.max(1, index);
    }

    Item {
        id: column
        anchors {
            fill: parent
            margins: root.padding
        }

        Repeater {
            id: repeater
            model: root.sections
            delegate: Rectangle {
                id: card
                required property var modelData
                required property int index
                readonly property string type: modelData.type
                readonly property bool shown: SidebarLayout.sectionShown(card.type)
                readonly property bool picked: root.selected === card.type
                readonly property bool fixedPlace: SidebarCatalog.section(card.type)?.fixed ?? false
                readonly property bool dragging: root.dragType === card.type
                width: column.width
                height: root.heightOf(card.type)
                y: card.dragging ? root.dragY : root.topOf(card.type, root.previewOrder)
                Behavior on y {
                    enabled: !card.dragging
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                radius: card.shown ? 12 : height / 2
                color: !card.shown ? "transparent" : card.type === "header" ? "transparent" : Appearance.colors.colLayer1
                border.width: card.picked || card.dragging ? 2 : (card.shown ? 0 : 1)
                border.color: card.picked || card.dragging ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                z: card.dragging ? 5 : 1
                scale: card.dragging ? 1.03 : 1
                Behavior on scale {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on height {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                // Contents
                Loader {
                    anchors {
                        fill: parent
                        margins: card.type === "header" ? 0 : 6
                    }
                    active: card.shown
                    sourceComponent: ({ "header": headerContent, "sliders": slidersContent, "toggles": togglesContent,
                        "notifications": notificationsContent, "widgets": widgetsContent })[card.type]
                }
                StyledText {
                    visible: !card.shown
                    anchors.centerIn: parent
                    text: Translation.tr("%1 (hidden)").arg(SidebarCatalog.section(card.type)?.name ?? "")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                }

                MouseArea {
                    id: cardArea
                    anchors.fill: parent
                    hoverEnabled: true
                    preventStealing: true // The settings page must not scroll away with the drag
                    cursorShape: card.fixedPlace || !root.editable ? Qt.PointingHandCursor : (card.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
                    property real startY: 0
                    property real grabOffset: 0
                    onPressed: mouse => {
                        startY = mapToItem(column, mouse.x, mouse.y).y;
                        grabOffset = startY - card.y;
                    }
                    onPositionChanged: mouse => {
                        if (!pressed || card.fixedPlace || !root.editable) return;
                        const y = mapToItem(column, mouse.x, mouse.y).y;
                        if (!card.dragging && Math.abs(y - startY) < 5) return;
                        root.dragY = Math.max(0, Math.min(column.height - card.height, y - grabOffset));
                        root.dragTarget = root.targetFor(card.type, root.dragY + card.height / 2);
                        root.dragType = card.type;
                    }
                    onReleased: {
                        // Reset first: moving rebuilds this card
                        const moved = card.dragging;
                        const type = card.type;
                        const target = root.dragTarget;
                        root.dragType = "";
                        root.dragTarget = -1;
                        if (moved) SidebarLayout.moveSection(type, target);
                        else root.sectionClicked(type);
                    }
                    onCanceled: {
                        root.dragType = "";
                        root.dragTarget = -1;
                    }
                }

                // Eye: show or hide
                RippleButton {
                    visible: root.editable && !card.fixedPlace && !card.dragging && (cardArea.containsMouse || card.picked || !card.shown)
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
                    onClicked: SidebarLayout.setSectionShown(card.type, !card.shown)
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

    // ---- Section drawings ----

    Component {
        id: headerContent
        RowLayout {
            spacing: 4
            Rectangle {
                visible: Config.options.sidebar.right.header.showUptime
                implicitWidth: 64
                implicitHeight: 24
                radius: 12
                color: Appearance.colors.colLayer1
                StyledText {
                    anchors.centerIn: parent
                    text: Translation.tr("Up %1").arg("3h")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colOnLayer1
                }
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                implicitWidth: buttonsRow.implicitWidth + 10
                implicitHeight: 24
                radius: 12
                color: Appearance.colors.colLayer1
                visible: buttonsRow.children.length > 1
                Row {
                    id: buttonsRow
                    anchors.centerIn: parent
                    spacing: 4
                    Repeater {
                        model: SidebarCatalog.headerButtons.filter(b => Config.options.sidebar.right.header.buttons.includes(b.id)
                            && (b.id !== "edit" || !root.classic))
                        MaterialSymbol {
                            required property var modelData
                            text: modelData.icon
                            iconSize: 13
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                }
            }
        }
    }

    Component {
        id: slidersContent
        Column {
            spacing: 4
            Repeater {
                model: root.slidersShown.length > 0 ? root.slidersShown : ["tune"]
                Row {
                    required property string modelData
                    required property int index
                    spacing: 6
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData
                        iconSize: 12
                        color: Appearance.colors.colOnLayer1
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: column.width - 40
                        height: 8
                        radius: 4
                        color: Appearance.colors.colSecondaryContainer
                        Rectangle {
                            width: parent.width * [0.6, 0.4, 0.75][index % 3]
                            height: parent.height
                            radius: 4
                            color: Appearance.colors.colPrimary
                        }
                    }
                }
            }
        }
    }

    Component {
        id: togglesContent
        Item {
            id: togglesArea
            // Android: the real grid, wide toggles with their name
            Column {
                visible: !root.classic
                anchors.fill: parent
                spacing: 4
                readonly property real cell: (width - 4 * (root.columns - 1)) / root.columns
                id: grid
                Repeater {
                    model: root.toggleRows
                    Row {
                        required property var modelData
                        spacing: 4
                        Repeater {
                            model: modelData
                            Rectangle {
                                required property var modelData
                                required property int index
                                width: grid.cell * modelData.size + 4 * (modelData.size - 1)
                                height: 30
                                radius: modelData.size > 1 ? 15 : 10
                                color: index % 3 === 0 ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                                Row {
                                    anchors {
                                        left: parent.left
                                        leftMargin: modelData.size > 1 ? 8 : 0
                                        horizontalCenter: modelData.size > 1 ? undefined : parent.horizontalCenter
                                        verticalCenter: parent.verticalCenter
                                    }
                                    spacing: 4
                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: SidebarCatalog.toggle(modelData.type)?.icon ?? "help"
                                        iconSize: 14
                                        fill: 1
                                        color: index % 3 === 0 ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                                    }
                                    StyledText {
                                        visible: modelData.size > 1
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: grid.cell * modelData.size - 34
                                        elide: Text.ElideRight
                                        text: SidebarCatalog.toggle(modelData.type)?.name ?? ""
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: index % 3 === 0 ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                                    }
                                }
                            }
                        }
                    }
                }
            }
            // Classic: a row of round buttons
            Row {
                visible: root.classic
                anchors.centerIn: parent
                spacing: 4
                Repeater {
                    model: SidebarLayout.classicToggles()
                    Rectangle {
                        required property string modelData
                        required property int index
                        width: Math.min(26, (togglesArea.width - 4 * 7) / 8)
                        height: width
                        radius: width / 2
                        color: index % 3 === 0 ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: SidebarCatalog.toggle(modelData)?.icon ?? "help"
                            iconSize: 13
                            fill: 1
                            color: index % 3 === 0 ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                        }
                    }
                }
            }
        }
    }

    Component {
        id: notificationsContent
        Column {
            spacing: 6
            clip: true
            Repeater {
                model: 6
                Row {
                    required property int index
                    spacing: 6
                    Rectangle {
                        width: 18
                        height: 18
                        radius: 9
                        color: [Appearance.colors.colPrimary, Appearance.colors.colTertiary, Appearance.colors.colSecondary][index % 3]
                    }
                    Column {
                        spacing: 3
                        Rectangle { width: column.width * [0.45, 0.3, 0.38][index % 3]; height: 5; radius: 2.5; color: Appearance.colors.colOnLayer1; opacity: 0.7 }
                        Rectangle { width: column.width * [0.7, 0.62, 0.55][index % 3]; height: 4; radius: 2; color: Appearance.colors.colOnLayer1; opacity: 0.35 }
                    }
                }
            }
        }
    }

    Component {
        id: widgetsContent
        RowLayout {
            spacing: 8
            // Tab rail
            Column {
                Layout.alignment: Qt.AlignVCenter
                spacing: 8
                Repeater {
                    model: Config.options.sidebar.right.widgets.tabs.map(t => SidebarCatalog.widgetTab(t)).filter(t => t)
                    Rectangle {
                        required property var modelData
                        required property int index
                        width: 26
                        height: 16
                        radius: 8
                        color: index === 0 ? Appearance.colors.colSecondaryContainer : "transparent"
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: modelData.icon
                            iconSize: 12
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                }
            }
            // What the first tab shows
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                readonly property string first: Config.options.sidebar.right.widgets.tabs[0] ?? "calendar"
                Grid {
                    visible: parent.first === "calendar"
                    anchors.centerIn: parent
                    columns: 7
                    spacing: 5
                    Repeater {
                        model: 35
                        Rectangle {
                            required property int index
                            width: 7
                            height: 7
                            radius: 3.5
                            color: index === 17 ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                            opacity: index === 17 ? 1 : 0.3
                        }
                    }
                }
                Column {
                    visible: parent.first === "todo"
                    anchors.centerIn: parent
                    spacing: 6
                    Repeater {
                        model: 4
                        Row {
                            required property int index
                            spacing: 5
                            Rectangle { width: 8; height: 8; radius: 2; border.width: 1; border.color: Appearance.colors.colOnLayer1; color: "transparent" }
                            Rectangle { width: [70, 50, 62, 40][index]; height: 5; radius: 2.5; color: Appearance.colors.colOnLayer1; opacity: 0.4; anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                }
                Rectangle {
                    visible: parent.first === "timer"
                    anchors.centerIn: parent
                    width: Math.min(parent.width, parent.height) * 0.7
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.width: 3
                    border.color: Appearance.colors.colPrimary
                    StyledText {
                        anchors.centerIn: parent
                        text: "05:00"
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }
        }
    }
}
