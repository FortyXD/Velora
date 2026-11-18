import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.settings.barLayout

/**
 * Everything about the bar on one page that never scrolls away from the bar itself: a strip of the
 * screen with the bar at its edge stays pinned (beside the page for a vertical bar), with tabs below
 * it. Widgets: the catalog to click or drag onto the bar, with a popup for the selected widget.
 * Look, Behavior, and Ready-made bars with sharing each scroll on their own.
 */
ContentPage {
    id: page
    readonly property bool canNavigateBack: page.tab !== "widgets" || page.selected !== null
    function navigateBack() { page.navigateToSection(""); }
    navigationTrail: {
        const trail = [{key: page.tab, title: ({widgets: Translation.tr("Widgets"), look: Translation.tr("Look"), behavior: Translation.tr("Behavior"), share: Translation.tr("Ready-made")})[page.tab]}];
        if (page.tab === "widgets" && page.selected)
            trail.push({key: page.selectedUid, title: BarWidgetCatalog.get(page.selected.item.type)?.name ?? Translation.tr("Widget")});
        return trail;
    }
    function navigateToSection(key) {
        if (key === page.selectedUid && key) return;
        page.tab = key || "widgets";
        if (page.tab === "widgets") page.selectedUid = "";
    }
    fitToWindow: true
    maxContentWidth: 1100

    readonly property string orientation: Config.options.bar.vertical ? "vertical" : "horizontal"
    readonly property bool isVertical: page.orientation === "vertical"
    readonly property alias popupPane: popupArea
    SettingsPopupArea {
        id: popupArea
        parent: page.Window.window?.settingsPageViewport ?? page
        column: page.isVertical ? editorColumn : null
    }
    readonly property var layout: page.isVertical ? BarLayout.vertical : BarLayout.horizontal
    readonly property bool isCustom: page.isVertical ? BarLayout.verticalIsCustom : BarLayout.horizontalIsCustom
    readonly property var barStyle: Config.options.bar.style
    property string selectedUid: ""
    property string addZone: "end"
    property int addIndex: -1
    onLayoutChanged: addIndex = -1
    property string tab: "widgets"
    onOrientationChanged: page.selectedUid = ""
    onSelectedUidChanged: if (page.selectedUid.length > 0) page.tab = "widgets"
    readonly property var selected: page.selectedUid.length > 0 ? BarLayout.find(page.layout, page.selectedUid) : null
    onSelectedChanged: if (page.selected) inspectorPopup.displayedSelection = page.selected

    readonly property var zoneInfo: BarLayout.zoneInfo(page.orientation)

    function zoneTitle(zone) {
        return page.zoneInfo.find(info => info.zone === zone)?.title ?? zone;
    }

    function catalogTypes(category) {
        return Object.keys(BarWidgetCatalog.widgets).filter(type => {
            const meta = BarWidgetCatalog.get(type);
            return meta.category === category && (!page.isVertical || meta.vertical);
        }).sort((a, b) => {
            const present = Number(!!page.placedOfType(b)) - Number(!!page.placedOfType(a));
            return present || BarWidgetCatalog.get(a).name.localeCompare(BarWidgetCatalog.get(b).name);
        });
    }

    function placedOfType(type) {
        for (const zone of BarLayout.zoneNames) {
            const item = page.layout.zones[zone].find(item => item.type === type);
            if (item) return { "zone": zone, "item": item };
        }
        return null;
    }

    function activateCatalogType(type) {
        const placed = page.placedOfType(type);
        if (placed) page.selectedUid = placed.item.uid;
        else page.addWidget(type, page.addZone, page.addIndex);
    }

    function addWidget(type, zone, index) {
        const existing = BarWidgetCatalog.get(type)?.unique ? page.placedOfType(type) : null;
        if (existing) {
            BarLayout.move(page.orientation, existing.item.uid, zone, index);
            page.selectedUid = existing.item.uid;
            return;
        }
        page.selectedUid = BarLayout.insert(page.orientation, type, zone, index);
    }

    // Dragging chips: from the canvas (move) or from the palette (add)
    property var dragState: null // { mode: "move"|"add", uid, type }
    function dragStart(state, sceneX, sceneY, offsetX, offsetY) {
        const meta = BarWidgetCatalog.get(state.type);
        ghost.label = meta?.name ?? state.type;
        ghost.icon = meta?.icon ?? "help";
        ghost.pill = !!state.pill;
        ghost.offsetX = offsetX;
        ghost.offsetY = offsetY;
        if (state.mode === "add" && meta?.unique)
            state.uid = page.placedOfType(state.type)?.item.uid ?? "";
        page.dragState = state;
        page.dragMove(sceneX, sceneY);
    }
    function dragMove(sceneX, sceneY) {
        const local = ghost.parent.mapFromItem(null, sceneX, sceneY);
        ghost.x = local.x - ghost.offsetX;
        ghost.y = local.y - ghost.offsetY;
        const target = canvas.editGuide.updateAt(sceneX, sceneY, true);
        // A widget from the bar taken off the strip (into the catalog, say) is removed when let go
        const onStrip = canvas.mapFromItem(null, sceneX, sceneY);
        const slack = 16;
        ghost.removing = page.dragState?.mode === "move" && target === null
            && (onStrip.x < -slack || onStrip.y < -slack || onStrip.x > canvas.width + slack || onStrip.y > canvas.height + slack);
    }
    function dragEnd(sceneX, sceneY) {
        const state = page.dragState;
        if (!state) return;
        const canceled = sceneX === -1 && sceneY === -1;
        if (!canceled) page.dragMove(sceneX, sceneY);
        const guide = canvas.editGuide;
        const target = guide.target;
        const removing = !canceled && ghost.removing;
        const points = guide.capture();
        const release = ghost.mapToItem(null, ghost.width / 2, ghost.height / 2);
        page.dragState = null;
        guide.clear();
        ghost.removing = false;
        if (canceled) return;
        if (state.mode === "move" && removing) {
            if (page.selectedUid === state.uid) page.selectedUid = "";
            BarLayout.remove(page.orientation, state.uid);
            guide.settle(points);
        } else if (target) {
            let uid = state.uid;
            if (state.mode === "move") {
                if (!target.noop) BarLayout.move(page.orientation, uid, target.zone, target.index);
            } else {
                page.addWidget(state.type, target.zone, target.index);
                uid = page.selectedUid;
            }
            guide.settle(points, uid, release);
        }
    }

    WidgetChip {
        id: ghost
        property real offsetX
        property real offsetY
        parent: page.Overlay.overlay ?? page.Window.window?.contentItem ?? page
        scale: page.dragState ? (removing ? 0.94 : 1.04) : 0.98
        opacity: page.dragState ? 0.96 : 0
        visible: opacity > 0
        Behavior on scale { NumberAnimation { duration: Appearance.scaledDuration(140); easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: Appearance.scaledDuration(100) } }
        enabled: false
        z: 1000
        selected: true
    }

    Shortcut {
        sequence: StandardKey.Delete
        enabled: page.pageShown && page.selectedUid.length > 0
        onActivated: {
            BarLayout.remove(page.orientation, page.selectedUid);
            page.selectedUid = "";
        }
    }
    Shortcut {
        sequence: StandardKey.Undo
        enabled: page.pageShown && BarLayout.canUndo
        onActivated: BarLayout.undo()
    }
    SettingsPanePopup {
        id: inspectorPopup
        objectName: "barWidgetPopup"
        // Keep the last card intact while the close transition finishes.
        property var displayedSelection: null
        pane: page.popupPane
        width: Math.min(560, Math.max(0, (parent?.width ?? 560) - 32))
        height: inspector.implicitHeight
        padding: 0
        visible: page.pageShown && page.tab === "widgets" && page.selected !== null && page.dragState === null
        onClosed: {
            page.selectedUid = "";
            displayedSelection = null;
        }
        background: Item {}
        contentItem: WidgetInspector {
            id: inspector
            orientation: page.orientation
            selected: inspectorPopup.displayedSelection
            zoneInfo: page.zoneInfo
            maximumHeight: Math.max(0, (inspectorPopup.parent?.height ?? 600) - 48)
            onCloseRequested: page.selectedUid = ""
            onSelectRequested: uid => page.selectedUid = uid
        }
    }

    GridLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        // A vertical bar stands beside the tabs, on its own side of the screen
        columns: page.isVertical ? 2 : 1
        layoutDirection: canvas.edge === "right" ? Qt.RightToLeft : Qt.LeftToRight
        columnSpacing: 16
        rowSpacing: 12

        Item { // The pinned bar; found by search as "Your bar"
            id: layoutSection
            readonly property bool settingsSearchable: true
            readonly property bool settingsSection: true
            readonly property string title: Translation.tr("Your bar")
            readonly property string icon: "toast"
            readonly property string searchText: `${title} ${Translation.tr("Layout")} ${Translation.tr("Bar position")} ${Translation.tr("Arrange widgets")}`
            Layout.fillWidth: !page.isVertical
            Layout.fillHeight: page.isVertical
            implicitWidth: canvas.implicitWidth
            implicitHeight: canvas.implicitHeight

            BarCanvas {
                id: canvas
                objectName: "barLayoutCanvas"
                anchors.fill: parent
                orientation: page.orientation
                layout: page.layout
                zoneInfo: page.zoneInfo
                selectedUid: page.selectedUid
                draggedUid: page.dragState?.uid ?? ""
                dragging: page.dragState !== null
                onSelectRequested: uid => page.selectedUid = uid
                onChipDragStarted: (item, sceneX, sceneY, offsetX, offsetY) => page.dragStart({ "mode": "move", "uid": item.uid, "type": item.type, "pill": item.pill }, sceneX, sceneY, offsetX, offsetY)
                onChipDragMoved: (sceneX, sceneY) => page.dragMove(sceneX, sceneY)
                onChipDragEnded: (sceneX, sceneY) => page.dragEnd(sceneX, sceneY)
                onAddRequested: (zone, index) => {
                    page.selectedUid = "";
                    page.addZone = zone;
                    page.addIndex = index;
                    page.tab = "widgets";
                }
            }
        }

        ColumnLayout {
            id: editorColumn
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                ConfigSelectionArray {
                    Layout.fillWidth: false
                    Layout.leftMargin: 0
                    Layout.rightMargin: 0
                    Layout.bottomMargin: 0
                    currentValue: page.tab
                    onSelected: newValue => page.tab = newValue
                    options: [
                        { "displayName": Translation.tr("Widgets"), "icon": "widgets", "value": "widgets" },
                        { "displayName": Translation.tr("Look"), "icon": "palette", "value": "look" },
                        { "displayName": Translation.tr("Behavior"), "icon": "touch_app", "value": "behavior" },
                        { "displayName": Translation.tr("Ready-made"), "icon": "dashboard_customize", "value": "share" },
                    ]
                }
                Item {
                    Layout.fillWidth: true
                }
                ToolbarIconButton {
                    symbol: "undo"
                    tip: Translation.tr("Undo")
                    enabled: BarLayout.canUndo
                    onClicked: BarLayout.undo()
                }
                ToolbarIconButton {
                    symbol: "restart_alt"
                    tip: Translation.tr("Reset to default")
                    enabled: page.isCustom
                    onClicked: {
                        BarLayout.reset(page.orientation);
                        page.selectedUid = "";
                    }
                }
                ToolbarIconButton {
                    symbol: "edit"
                    tip: Translation.tr("Edit on the bar")
                    onClicked: Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "bar", "edit"])
                }
            }

            Item {
                id: tabArea
                Layout.fillWidth: true
                Layout.fillHeight: true

                SettingsTabPage {
                    key: "widgets"
                    anchors.fill: parent
                    current: page.tab
                    onRevealRequested: key => page.tab = key

                    GridLayout {
                        id: widgetsTab
                        anchors.fill: parent
                        columns: 1
                        columnSpacing: 14
                        rowSpacing: 12

                        SettingsScrollPane {
                            id: paletteSection
                            Layout.row: 0
                            Layout.column: 0
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 16

                            Repeater {
                                model: BarWidgetCatalog.categories
                                delegate: ContentSubsection {
                                    id: categoryBlock
                                    required property var modelData
                                    readonly property var types: page.catalogTypes(modelData.id)
                                    visible: types.length > 0
                                    title: modelData.name

                                    Flow {
                                        Layout.fillWidth: true
                                        spacing: 6
                                        Repeater {
                                            model: categoryBlock.types
                                            delegate: WidgetChip {
                                                id: catalogChip
                                                required property string modelData
                                                objectName: "barCatalog-" + modelData
                                                readonly property var meta: BarWidgetCatalog.get(modelData)
                                                present: !!page.placedOfType(modelData)
                                                readonly property bool settingsSearchable: true
                                                readonly property string searchText: `${meta.name} ${meta.description} ${(meta.options ?? []).map(option => option.label).join(" ")}`
                                                function settingsReveal() {
                                                    const placed = page.placedOfType(modelData);
                                                    if (placed) page.selectedUid = placed.item.uid;
                                                    return false;
                                                }
                                                compact: true
                                                label: meta.name
                                                icon: meta.icon
                                                pill: present
                                                onClicked: page.activateCatalogType(modelData)
                                                onDragStarted: (sceneX, sceneY, offsetX, offsetY) => page.dragStart({ "mode": "add", "type": modelData, "pill": !!meta.defaults?.pill }, sceneX, sceneY, offsetX, offsetY)
                                                onDragMoved: (sceneX, sceneY) => page.dragMove(sceneX, sceneY)
                                                onDragEnded: (sceneX, sceneY) => page.dragEnd(sceneX, sceneY)
                                                StyledToolTip {
                                                    text: catalogChip.meta.description
                                                }
                                            }
                                        }
                                    }
                                }
                            }


                        }
                    }
                }

                SettingsTabPage {
                    key: "look"
                    anchors.fill: parent
                    current: page.tab
                    onRevealRequested: key => page.tab = key
                    SettingsScrollPane {
                        anchors.fill: parent
                    ContentSection {
                        icon: "palette"
                        title: Translation.tr("Look")
                        description: Translation.tr("Sizes left on Auto follow the theme")

                        ContentSubsection {
                            title: Translation.tr("Background")
                            Flow {
                                Layout.fillWidth: true
                                spacing: 4
                                readonly property var bar: Config.options.bar
                                readonly property var current: bar.style.islands ? "islands" : !bar.showBackground ? "none" : ["hug", "float", "rect"][bar.cornerStyle] ?? "hug"
                                Repeater {
                                    model: [
                                        { "variant": "hug", "label": Translation.tr("Hug") },
                                        { "variant": "float", "label": Translation.tr("Float") },
                                        { "variant": "rect", "label": Translation.tr("Rect") },
                                        { "variant": "islands", "label": Translation.tr("Islands") },
                                        { "variant": "none", "label": Translation.tr("None") },
                                    ]
                                    delegate: StyleTile {
                                        required property var modelData
                                        variant: modelData.variant
                                        label: modelData.label
                                        selected: parent.current === modelData.variant
                                        onClicked: {
                                            Config.options.bar.style.islands = modelData.variant === "islands";
                                            Config.options.bar.showBackground = modelData.variant !== "none";
                                            const corner = ["hug", "float", "rect"].indexOf(modelData.variant);
                                            if (corner >= 0) Config.options.bar.cornerStyle = corner;
                                        }
                                    }
                                }
                            }
                        }

                        ContentSubsection {
                            title: Translation.tr("Widget groups")
                            Flow {
                                Layout.fillWidth: true
                                spacing: 4
                                readonly property string current: Config.options.bar.borderless ? "bare" : page.barStyle.pillStyle === "none" ? "bare" : page.barStyle.pillStyle
                                Repeater {
                                    model: [
                                        { "variant": "filled", "value": "filled", "label": Translation.tr("Filled pills") },
                                        { "variant": "outlined", "value": "outlined", "label": Translation.tr("Outlined pills") },
                                        { "variant": "bare", "value": "none", "label": Translation.tr("No pills") },
                                    ]
                                    delegate: StyleTile {
                                        required property var modelData
                                        variant: modelData.variant
                                        label: modelData.label
                                        selected: parent.current === modelData.variant
                                        onClicked: {
                                            Config.options.bar.style.pillStyle = modelData.value;
                                            Config.options.bar.borderless = modelData.value === "none";
                                        }
                                    }
                                }
                            }
                        }

                        SizeSlider {
                            buttonIcon: "height"
                            text: Translation.tr("Thickness")
                            key: "thickness"
                            from: 24
                            to: 96
                            themeValue: page.isVertical ? 46 : 40
                        }
                        SizeSlider {
                            buttonIcon: "padding"
                            text: Translation.tr("Space at the screen edges")
                            key: "edgePadding"
                            from: 0
                            to: 80
                            themeValue: Appearance.rounding.screenRounding
                        }
                        SizeSlider {
                            buttonIcon: "margin"
                            text: Translation.tr("Gap around a floating bar")
                            key: "floatMargin"
                            from: 0
                            to: 60
                            themeValue: Appearance.sizes.hyprlandGapsOut
                        }
                        SizeSlider {
                            buttonIcon: "rounded_corner"
                            text: Translation.tr("Corner radius of floating bars and islands")
                            key: "radius"
                            from: 0
                            to: 60
                            themeValue: Appearance.rounding.windowRounding
                        }

                        ConfigSwitch {
                            buttonIcon: "opacity"
                            text: Translation.tr("Own transparency")
                            description: Translation.tr("Set the bar's opacity apart from the rest of the theme")
                            autoToggle: false
                            checked: page.barStyle.backgroundOpacity >= 0
                            onClicked: Config.options.bar.style.backgroundOpacity = checked ? -1 : Math.round(Appearance.colors.barOpacity * 100) / 100
                        }
                        ConfigSlider {
                            visible: page.barStyle.backgroundOpacity >= 0
                            buttonIcon: "gradient"
                            text: Translation.tr("Opacity")
                            defaultValue: Appearance.colors.themeBarOpacity
                            value: Math.max(0, page.barStyle.backgroundOpacity)
                            onMoved: Config.options.bar.style.backgroundOpacity = Math.round(value * 100) / 100
                        }
                        ConfigSwitch {
                            buttonIcon: "blur_on"
                            text: Translation.tr("Glass")
                            description: Translation.tr("Blur what's behind a see-through bar")
                            autoToggle: false
                            checked: page.barStyle.glass
                            onClicked: Config.options.bar.style.glass = !page.barStyle.glass
                        }
                        ConfigSwitch {
                            buttonIcon: "text_format"
                            text: Translation.tr("Text shadow")
                            description: Translation.tr("Keeps text readable over the wallpaper")
                            autoToggle: false
                            checked: page.barStyle.textShadow
                            onClicked: Config.options.bar.style.textShadow = !page.barStyle.textShadow
                        }
                        ConfigSwitch {
                            buttonIcon: "shadow"
                            text: Translation.tr("Shadow under floating bars and islands")
                            autoToggle: false
                            checked: Config.options.bar.floatStyleShadow
                            onClicked: Config.options.bar.floatStyleShadow = !Config.options.bar.floatStyleShadow
                        }
                    }
                    }
                }

                SettingsTabPage {
                    key: "behavior"
                    anchors.fill: parent
                    current: page.tab
                    onRevealRequested: key => page.tab = key
                    SettingsScrollPane {
                        anchors.fill: parent
                    ContentSection {
                        icon: "touch_app"
                        title: Translation.tr("Behavior")

                        ConfigSwitch {
                            buttonIcon: "visibility_off"
                            text: Translation.tr("Automatically hide")
                            description: Translation.tr("The bar appears when you move the pointer to its edge")
                            autoToggle: false
                            checked: Config.options.bar.autoHide.enable
                            onClicked: Config.options.bar.autoHide.enable = !Config.options.bar.autoHide.enable
                        }
                        ConfigSwitch {
                            visible: Config.options.bar.autoHide.enable
                            buttonIcon: "keyboard_command_key"
                            text: Translation.tr("Show it while Super is held")
                            autoToggle: false
                            checked: Config.options.bar.autoHide.showWhenPressingSuper.enable
                            onClicked: Config.options.bar.autoHide.showWhenPressingSuper.enable = !Config.options.bar.autoHide.showWhenPressingSuper.enable
                        }
                        ConfigSlider {
                            visible: Config.options.bar.autoHide.enable && Config.options.bar.autoHide.showWhenPressingSuper.enable
                            buttonIcon: "timer"
                            text: Translation.tr("After holding Super for")
                            usePercentTooltip: false
                            from: 0
                            to: 1000
                            defaultValue: 140
                            defaultValueText: "140 ms"
                            value: Config.options.bar.autoHide.showWhenPressingSuper.delay
                            valueText: `${Math.round(value)} ms`
                            onMoved: Config.options.bar.autoHide.showWhenPressingSuper.delay = Math.round(value / 10) * 10
                        }
                        ConfigSlider {
                            visible: Config.options.bar.autoHide.enable
                            buttonIcon: "border_outer"
                            text: Translation.tr("Edge that reveals it")
                            usePercentTooltip: false
                            from: 1
                            to: 20
                            defaultValue: 2
                            defaultValueText: "2 px"
                            value: Config.options.bar.autoHide.hoverRegionWidth
                            valueText: `${Math.round(value)} px`
                            onMoved: Config.options.bar.autoHide.hoverRegionWidth = Math.round(value)
                        }
                        ConfigSwitch {
                            visible: Config.options.bar.autoHide.enable
                            buttonIcon: "width_normal"
                            text: Translation.tr("Make room for it when it shows")
                            description: Translation.tr("Windows move aside instead of being covered")
                            autoToggle: false
                            checked: Config.options.bar.autoHide.pushWindows
                            onClicked: Config.options.bar.autoHide.pushWindows = !Config.options.bar.autoHide.pushWindows
                        }
                        ConfigSwitch {
                            buttonIcon: "align_justify_center"
                            text: Translation.tr("Keep the center in the middle")
                            description: Translation.tr("Both sides of the center get the same width, so the center widgets sit exactly in the middle of the screen")
                            autoToggle: false
                            checked: page.layout.balanceCenter
                            onClicked: BarLayout.setBalanceCenter(page.orientation, !page.layout.balanceCenter)
                        }
                        ConfigSwitch {
                            buttonIcon: "ads_click"
                            text: Translation.tr("Open popups on click")
                            description: Translation.tr("Popups of bar items open on click instead of hover")
                            autoToggle: false
                            checked: Config.options.bar.tooltips.clickToShow
                            onClicked: Config.options.bar.tooltips.clickToShow = !Config.options.bar.tooltips.clickToShow
                        }
                        ConfigSwitch {
                            buttonIcon: "motion_play"
                            text: Translation.tr("Micro-animations")
                            description: Translation.tr("Rolling numbers, popup transitions, press feedback and scrolling titles. Turn off on slow hardware")
                            autoToggle: false
                            checked: Config.options.bar.microAnimations
                            onClicked: Config.options.bar.microAnimations = !Config.options.bar.microAnimations
                        }

                        ContentSubsection {
                            title: Translation.tr("Clicks and scrolling")
                            description: Translation.tr("What happens on the free space of each part of the bar")

                            GridLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: 12
                                Layout.rightMargin: 12
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
                                        minimumWidth: 140
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
                    }
                    }
                }

                SettingsTabPage {
                    key: "share"
                    anchors.fill: parent
                    current: page.tab
                    onRevealRequested: key => page.tab = key
                    SettingsScrollPane {
                        anchors.fill: parent
                    ContentSection {
                        id: shareSection
                        icon: "dashboard_customize"
                        title: Translation.tr("Ready-made bars and sharing")
                        description: Translation.tr("Start from a preset, or pass a layout around as text")

                        property var pasted: null

                        Flow {
                            Layout.fillWidth: true
                            Layout.margins: 8
                            spacing: 6
                            Repeater {
                                model: Presets.presets.filter(preset => {
                                    const categories = Presets.categoriesOf(preset);
                                    return categories.length === 1 && categories[0] === "bar";
                                })
                                delegate: WidgetChip {
                                    required property var modelData
                                    label: Translation.tr(modelData.name)
                                    icon: modelData.icon ?? "toast"
                                    onClicked: {
                                        Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "presets", "apply", modelData.id, "bar"]);
                                        page.selectedUid = "";
                                    }
                                    StyledToolTip {
                                        text: Translation.tr(parent.modelData.description ?? "")
                                    }
                                }
                            }
                        }
                        ConfigNavRow {
                            buttonIcon: "auto_awesome_mosaic"
                            title: Translation.tr("All presets")
                            description: Translation.tr("Whole looks with theme, dock and motion, and saving your own")
                            onClicked: ApplicationWindow.window?.openPage("presets")
                        }

                        RowLayout {
                            Layout.margins: 8
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
                            Layout.margins: 12
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
                                text: Translation.tr("Bar widgets can run the commands below automatically or when you interact with them.")
                            }
                            Repeater {
                                model: pastePreview.pasted?.commands ?? []
                                delegate: StyledText {
                                    required property string modelData
                                    Layout.fillWidth: true
                                    wrapMode: Text.WrapAnywhere
                                    text: modelData
                                    textFormat: Text.PlainText
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
                }
            }
        }
    }

    // Round icon button in the row of tabs
    component ToolbarIconButton: RippleButton {
        id: iconButton
        property string symbol
        property string tip
        implicitWidth: 36
        implicitHeight: 36
        buttonRadius: Appearance.rounding.full
        colBackgroundHover: Appearance.colors.colLayer1Hover
        opacity: iconButton.enabled ? 1 : 0.4
        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            text: iconButton.symbol
            iconSize: 20
            color: Appearance.colors.colOnLayer1
        }
        StyledToolTip {
            text: iconButton.tip
        }
    }

    // A size of the bar style: -1 in the config means "follow the theme" (Auto)
    component SizeSlider: ConfigSlider {
        id: sizeSlider
        required property string key
        property real themeValue: 0
        readonly property bool isAuto: !(page.barStyle[sizeSlider.key] >= 0)
        usePercentTooltip: false
        defaultValue: sizeSlider.themeValue
        value: sizeSlider.isAuto ? sizeSlider.themeValue : page.barStyle[sizeSlider.key]
        valueText: sizeSlider.isAuto ? Translation.tr("Auto") : `${Math.round(sizeSlider.value)}`
        onMoved: Config.options.bar.style[sizeSlider.key] = Math.round(sizeSlider.value)

        RippleButton {
            visible: !sizeSlider.isAuto
            implicitWidth: 30
            implicitHeight: 30
            buttonRadius: Appearance.rounding.full
            colBackgroundHover: Appearance.colors.colLayer2Hover
            onClicked: {
                Config.options.bar.style[sizeSlider.key] = -1;
                sizeSlider.value = Qt.binding(() => sizeSlider.isAuto ? sizeSlider.themeValue : page.barStyle[sizeSlider.key]);
            }
            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter
                text: "restart_alt"
                iconSize: 18
                color: Appearance.colors.colSubtext
            }
            StyledToolTip {
                text: Translation.tr("Back to Auto")
            }
        }
    }
}
