import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.settings.barLayout

ContentPage {
    id: page

    property string orientation: Config.options.bar.vertical ? "vertical" : "horizontal"
    readonly property bool isVertical: orientation === "vertical"
    readonly property var layout: isVertical ? BarLayout.vertical : BarLayout.horizontal
    readonly property bool isCustom: isVertical ? BarLayout.verticalIsCustom : BarLayout.horizontalIsCustom
    property string selectedUid: ""
    readonly property var selected: selectedUid.length > 0 ? BarLayout.find(layout, selectedUid) : null
    readonly property var selectedMeta: selected ? BarWidgetCatalog.get(selected.item.type) : null
    property string addZone: "end"

    readonly property var zoneInfo: [
        { "zone": "start", "title": isVertical ? Translation.tr("Top") : Translation.tr("Left edge"), "icon": isVertical ? "vertical_align_top" : "align_horizontal_left" },
        { "zone": "centerStart", "title": isVertical ? Translation.tr("Above center") : Translation.tr("Left of center"), "icon": isVertical ? "arrow_upward" : "arrow_back" },
        { "zone": "center", "title": Translation.tr("Center"), "icon": isVertical ? "align_vertical_center" : "align_horizontal_center" },
        { "zone": "centerEnd", "title": isVertical ? Translation.tr("Below center") : Translation.tr("Right of center"), "icon": isVertical ? "arrow_downward" : "arrow_forward" },
        { "zone": "end", "title": isVertical ? Translation.tr("Bottom") : Translation.tr("Right edge"), "icon": isVertical ? "vertical_align_bottom" : "align_horizontal_right" },
    ]

    function zoneTitle(zone) {
        return page.zoneInfo.find(info => info.zone === zone)?.title ?? zone;
    }

    function usableTypes() {
        return Object.keys(BarWidgetCatalog.widgets).filter(type => {
            const meta = BarWidgetCatalog.get(type);
            if (page.isVertical && !meta.vertical) return false;
            if (meta.unique && BarLayout.zoneNames.some(zone => page.layout.zones[zone].some(item => item.type === type))) return false;
            return true;
        });
    }

    function addWidget(type, zone, index) {
        page.selectedUid = BarLayout.insert(page.orientation, type, zone, index);
    }

    // Dragging chips: from a lane (move) or from the palette (add)
    property var dragState: null // { mode: "move"|"add", uid, type }
    function dragStart(state, sceneX, sceneY, offsetX, offsetY) {
        const meta = BarWidgetCatalog.get(state.type);
        ghost.label = meta?.name ?? state.type;
        ghost.icon = meta?.icon ?? "help";
        ghost.pill = !!state.pill;
        ghost.offsetX = offsetX;
        ghost.offsetY = offsetY;
        page.dragState = state;
        page.dragMove(sceneX, sceneY);
    }
    function dragMove(sceneX, sceneY) {
        const local = ghost.parent.mapFromItem(null, sceneX, sceneY);
        ghost.x = local.x - ghost.offsetX;
        ghost.y = local.y - ghost.offsetY;
        for (let i = 0; i < laneRepeater.count; i++) {
            const lane = laneRepeater.itemAt(i);
            lane.dropIndex = lane.containsScene(sceneX, sceneY) ? lane.indexAt(sceneX, sceneY) : -1;
        }
    }
    function dragEnd(sceneX, sceneY) {
        const state = page.dragState;
        let target = null;
        for (let i = 0; i < laneRepeater.count; i++) {
            const lane = laneRepeater.itemAt(i);
            if (lane.dropIndex >= 0 && sceneX >= 0) target = { "zone": lane.zone, "index": lane.dropIndex };
            lane.dropIndex = -1;
        }
        page.dragState = null;
        if (!state || !target) return;
        if (state.mode === "move") BarLayout.move(page.orientation, state.uid, target.zone, target.index);
        else page.addWidget(state.type, target.zone, target.index);
    }

    WidgetChip {
        id: ghost
        property real offsetX
        property real offsetY
        parent: Overlay.overlay
        visible: page.dragState !== null
        enabled: false
        z: 1000
        selected: true
    }

    ContentSection {
        icon: "view_column"
        title: Translation.tr("Layout")
        description: Translation.tr("Drag widgets between the parts of the bar. Click one to set it up.")

        ConfigRow {
            ContentSubsection {
                title: Translation.tr("Editing")
                ConfigSelectionArray {
                    currentValue: page.orientation
                    onSelected: newValue => {
                        page.orientation = newValue;
                        page.selectedUid = "";
                    }
                    options: [
                        { displayName: Translation.tr("Horizontal bar"), icon: "toolbar", value: "horizontal" },
                        { displayName: Translation.tr("Vertical bar"), icon: "side_navigation", value: "vertical" }
                    ]
                }
            }
            ContentSubsection {
                title: Translation.tr("Changes")
                RowLayout {
                    spacing: 6
                    DialogButton {
                        buttonText: Translation.tr("Undo")
                        enabled: BarLayout.canUndo
                        onClicked: BarLayout.undo()
                    }
                    DialogButton {
                        buttonText: Translation.tr("Edit on the bar")
                        onClicked: Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "bar", "edit"])
                    }
                    DialogButton {
                        buttonText: Translation.tr("Reset to default")
                        enabled: page.isCustom
                        onClicked: {
                            BarLayout.reset(page.orientation);
                            page.selectedUid = "";
                        }
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: page.isVertical !== Config.options.bar.vertical
            wrapMode: Text.Wrap
            text: page.isVertical ? Translation.tr("The bar is horizontal now; this layout is used when you move it to a side.")
                : Translation.tr("The bar is vertical now; this layout is used when you move it to the top or bottom.")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                id: laneRepeater
                model: page.zoneInfo
                delegate: ZoneLane {
                    required property var modelData
                    Layout.fillWidth: true
                    zone: modelData.zone
                    title: modelData.title
                    icon: modelData.icon
                    items: page.layout.zones[modelData.zone] ?? []
                    selectedUid: page.selectedUid
                    draggedUid: page.dragState?.mode === "move" ? page.dragState.uid : ""
                    highlighted: page.addZone === modelData.zone && !page.dragState
                    onChipClicked: item => page.selectedUid = (page.selectedUid === item.uid ? "" : item.uid)
                    onChipDragStarted: (item, sceneX, sceneY, offsetX, offsetY) => page.dragStart({ "mode": "move", "uid": item.uid, "type": item.type, "pill": item.pill }, sceneX, sceneY, offsetX, offsetY)
                    onChipDragMoved: (sceneX, sceneY) => page.dragMove(sceneX, sceneY)
                    onChipDragEnded: (sceneX, sceneY) => page.dragEnd(sceneX, sceneY)
                    onAddRequested: {
                        page.addZone = modelData.zone;
                        page.revealItem(paletteSection);
                    }
                }
            }
        }

        ConfigSwitch {
            buttonIcon: "align_justify_center"
            text: Translation.tr("Keep the center in the middle")
            description: Translation.tr("Both sides of the center get the same width, so the center widgets sit exactly in the middle of the screen")
            autoToggle: false
            checked: page.layout.balanceCenter
            onClicked: BarLayout.setBalanceCenter(page.orientation, !page.layout.balanceCenter)
        }
    }

    ContentSection {
        id: inspectorSection
        visible: page.selected !== null
        icon: page.selectedMeta?.icon ?? "widgets"
        title: page.selectedMeta?.name ?? Translation.tr("Widget")
        description: page.selectedMeta?.description ?? Translation.tr("This widget type is not known; it is kept but not shown")

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("In: %1").arg(page.selected ? page.zoneTitle(page.selected.zone) : "")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
            }
            DialogButton {
                visible: !(page.selectedMeta?.unique ?? false)
                buttonText: Translation.tr("Duplicate")
                onClicked: {
                    const item = page.selected.item;
                    page.selectedUid = BarLayout.insert(page.orientation, item.type, page.selected.zone, page.selected.index + 1, {
                        "pill": item.pill, "hideAt": item.hideAt, "options": item.options
                    });
                }
            }
            DialogButton {
                buttonText: Translation.tr("Remove")
                colEnabled: Appearance.colors.colError
                onClicked: {
                    BarLayout.remove(page.orientation, page.selectedUid);
                    page.selectedUid = "";
                }
            }
        }

        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "pill"
                text: Translation.tr("In a pill")
                description: Translation.tr("Neighbours in pills share one")
                autoToggle: false
                checked: !!page.selected?.item.pill
                onClicked: BarLayout.setItem(page.orientation, page.selectedUid, { "pill": page.selected.item.pill ? null : true, "pillBreak": null })
            }
            ConfigSwitch {
                visible: !!page.selected?.item.pill
                buttonIcon: "splitscreen_vertical_add"
                text: Translation.tr("Start a new pill")
                description: Translation.tr("Don't join the pill before it")
                autoToggle: false
                checked: !!page.selected?.item.pillBreak
                onClicked: BarLayout.setItem(page.orientation, page.selectedUid, { "pillBreak": page.selected.item.pillBreak ? null : true })
            }
        }

        ContentSubsection {
            title: Translation.tr("On narrow screens")
            ConfigSelectionArray {
                currentValue: page.selected?.item.hideAt ?? 0
                onSelected: newValue => BarLayout.setItem(page.orientation, page.selectedUid, { "hideAt": newValue === 0 ? null : newValue })
                options: [
                    { displayName: Translation.tr("Always show"), icon: "visibility", value: 0 },
                    { displayName: Translation.tr("Hide when narrow"), icon: "compress", value: 1 },
                    { displayName: Translation.tr("Hide when very narrow"), icon: "unfold_less", value: 2 }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Width")
            ConfigSelectionArray {
                currentValue: page.selected?.item.fill === undefined ? "auto" : page.selected.item.fill
                onSelected: newValue => BarLayout.setItem(page.orientation, page.selectedUid, { "fill": newValue === "auto" ? null : newValue })
                options: [
                    { displayName: Translation.tr("Automatic"), icon: "auto_awesome", value: "auto" },
                    { displayName: Translation.tr("Take free space"), icon: "expand", value: true },
                    { displayName: Translation.tr("Fit content"), icon: "fit_width", value: false }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Move to")
            ConfigSelectionArray {
                currentValue: page.selected?.zone ?? ""
                onSelected: newValue => BarLayout.move(page.orientation, page.selectedUid, newValue, 999)
                options: page.zoneInfo.map(info => ({ "displayName": info.title, "icon": info.icon, "value": info.zone }))
            }
        }

        BarWidgetOptionsForm {
            Layout.fillWidth: true
            orientation: page.orientation
            item: page.selected?.item ?? null
        }
    }

    ContentSection {
        id: paletteSection
        icon: "add_circle"
        title: Translation.tr("Add widgets")
        description: Translation.tr("Click to add to the chosen part of the bar, or drag onto any part")

        ContentSubsection {
            title: Translation.tr("Add to")
            ConfigSelectionArray {
                currentValue: page.addZone
                onSelected: newValue => page.addZone = newValue
                options: page.zoneInfo.map(info => ({ "displayName": info.title, "icon": info.icon, "value": info.zone }))
            }
        }

        Repeater {
            model: BarWidgetCatalog.categories
            delegate: ContentSubsection {
                id: categoryBlock
                required property var modelData
                readonly property var types: page.usableTypes().filter(type => BarWidgetCatalog.get(type).category === modelData.id)
                visible: types.length > 0
                title: modelData.name

                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: categoryBlock.types
                        delegate: WidgetChip {
                            required property string modelData
                            readonly property var meta: BarWidgetCatalog.get(modelData)
                            compact: true
                            label: meta.name
                            icon: meta.icon
                            pill: !!meta.defaults?.pill
                            onClicked: page.addWidget(modelData, page.addZone, -1)
                            onDragStarted: (sceneX, sceneY, offsetX, offsetY) => page.dragStart({ "mode": "add", "type": modelData, "pill": !!meta.defaults?.pill }, sceneX, sceneY, offsetX, offsetY)
                            onDragMoved: (sceneX, sceneY) => page.dragMove(sceneX, sceneY)
                            onDragEnded: (sceneX, sceneY) => page.dragEnd(sceneX, sceneY)
                            StyledToolTip {
                                text: parent.meta.description
                            }
                        }
                    }
                }
            }
        }
    }

    ContentSection {
        icon: "ads_click"
        title: Translation.tr("Clicks and scrolling")
        description: Translation.tr("What happens on the free space of each part of the bar")

        GridLayout {
            Layout.fillWidth: true
            columns: 4
            columnSpacing: 8
            rowSpacing: 6

            StyledText { text: "" }
            StyledText { text: Translation.tr("Click"); color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smaller }
            StyledText { text: Translation.tr("Middle click"); color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smaller }
            StyledText { text: Translation.tr("Scroll"); color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smaller }

            Repeater {
                model: page.zoneInfo
                delegate: StyledText {
                    required property var modelData
                    required property int index
                    Layout.row: index + 1
                    Layout.column: 0
                    Layout.fillWidth: true
                    text: modelData.title
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                }
            }
            Repeater {
                model: page.zoneInfo.length * 3
                delegate: ChoiceDropdown {
                    required property int index
                    readonly property var zone: page.zoneInfo[Math.floor(index / 3)].zone
                    readonly property string actionKey: ["click", "middleClick", "scroll"][index % 3]
                    Layout.row: Math.floor(index / 3) + 1
                    Layout.column: index % 3 + 1
                    maximumWidth: 200
                    minimumWidth: 150
                    currentValue: page.layout.actions[zone]?.[actionKey] ?? "none"
                    options: (actionKey === "scroll" ? BarWidgetCatalog.scrollActions : BarWidgetCatalog.clickActions)
                        .map(action => ({ "value": action.value, "displayName": action.name, "icon": action.icon }))
                    onSelected: value => {
                        let patch = {};
                        patch[actionKey] = value;
                        BarLayout.setActions(page.orientation, zone, patch);
                    }
                }
            }
        }
    }

    ContentSection {
        id: shareSection
        icon: "share"
        title: Translation.tr("Share a layout")
        description: Translation.tr("Copy this layout as text, or paste one from the clipboard")

        property var pasted: null

        RowLayout {
            spacing: 6
            DialogButton {
                buttonText: Translation.tr("Copy layout")
                onClicked: Quickshell.clipboardText = BarLayout.exportText(page.orientation)
            }
            DialogButton {
                buttonText: Translation.tr("Paste layout")
                onClicked: shareSection.pasted = BarLayout.parse(Quickshell.clipboardText)
            }
        }

        ColumnLayout {
            id: pastePreview
            readonly property var pasted: shareSection.pasted
            visible: pasted !== null
            Layout.fillWidth: true
            spacing: 6

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: pastePreview.pasted?.error ? Appearance.colors.colError : Appearance.colors.colOnLayer1
                text: pastePreview.pasted?.error ?? Translation.tr("A layout with %1 widgets is ready to use.").arg(
                    BarLayout.zoneNames.reduce((sum, zone) => sum + (pastePreview.pasted?.layout?.zones[zone].length ?? 0), 0))
            }
            StyledText {
                Layout.fillWidth: true
                visible: (pastePreview.pasted?.commands?.length ?? 0) > 0
                wrapMode: Text.Wrap
                color: Appearance.colors.colError
                text: Translation.tr("It runs these commands when you click its widgets. Use it only if you trust them:")
            }
            Repeater {
                model: pastePreview.pasted?.commands ?? []
                delegate: StyledText {
                    required property string modelData
                    Layout.fillWidth: true
                    wrapMode: Text.WrapAnywhere
                    text: modelData
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer1
                }
            }
            RowLayout {
                spacing: 6
                DialogButton {
                    visible: !!pastePreview.pasted?.layout
                    buttonText: Translation.tr("Use this layout")
                    onClicked: {
                        BarLayout.apply(page.orientation, pastePreview.pasted.layout);
                        shareSection.pasted = null;
                        page.selectedUid = "";
                    }
                }
                DialogButton {
                    buttonText: Translation.tr("Cancel")
                    onClicked: shareSection.pasted = null
                }
            }
        }
    }
}
