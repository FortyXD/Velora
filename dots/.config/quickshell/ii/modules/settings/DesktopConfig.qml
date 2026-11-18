import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.settings.preview
import qs.modules.settings.desktop

/**
 * Windows, the dock, the overview and hot corners, around a live miniature of the desktop
 * that shows every change as it's made.
 */
SettingsDetailPage {
    id: rootPage
    sectionTitles: ({
        windows: Translation.tr("Windows"),
        dock: Translation.tr("Dock"),
        dockApps: Translation.tr("Dock apps"),
        workspaces: Translation.tr("Workspaces and overview"),
        corners: Translation.tr("Hot corners")
    })
    readonly property var dock: Config.options.dock
    readonly property var hotCorners: Config.options.hotCorners

    function findChild(node, name) {
        if (!node) return null;
        if (node.objectName === name) return node;
        for (const child of node.children ?? []) {
            const found = rootPage.findChild(child, name);
            if (found) return found;
        }
        return null;
    }
    readonly property string dockMode: !rootPage.dock.enable ? "off"
        : rootPage.dock.pinnedOnStartup ? "always"
        : rootPage.dock.hoverToReveal ? "hover" : "empty"

    function setDockMode(mode) {
        Config.options.dock.enable = mode !== "off";
        if (mode === "off") return;
        Config.options.dock.pinnedOnStartup = mode === "always";
        Config.options.dock.hoverToReveal = mode === "hover";
    }

    sectionParents: ({ dockApps: "dock" })

    component DockSize: ConfigSlider {
        enabled: rootPage.dock.enable
        buttonIcon: "photo_size_select_large"
        text: Translation.tr("Size")
        usePercentTooltip: false
        from: 40
        to: 96
        defaultValue: 60
        defaultValueText: "60 px"
        value: rootPage.dock.height
        valueText: `${Math.round(value)} px`
        onMoved: Config.options.dock.height = Math.round(value)
    }

    component WindowModes: GridLayout {
        id: modes
        columns: width >= 540 ? 4 : 2
        uniformCellWidths: true
        Layout.fillWidth: true
        columnSpacing: 4
        readonly property bool free: HyprlandSettings.windowMode !== "tiling"
        readonly property string current: free ? HyprlandSettings.windowMode : HyprlandSettings.get("general:layout", "dwindle")
        // Changed by the shell, so windows rearrange under its transition
        function setMode(mode) {
            Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "windowMode", "set", mode]);
        }
        SchemeTile {
            id: dwindleTile
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 1
            frameWidth: Math.min(96, Math.max(54, (modes.width - 12) / modes.columns - 20))
            frameHeight: frameWidth * 60 / 96
            label: Translation.tr("Dwindle")
            selected: parent.current === "dwindle"
            onClicked: {
                HyprlandSettings.set("general:layout", "dwindle");
                if (parent.free) parent.setMode("tiling");
            }
            Item {
                width: 96; height: 60
                transformOrigin: Item.TopLeft
                scale: dwindleTile.frameWidth / width
                Block { x: 6; y: 6; width: 40; height: 48; color: dwindleTile.ink }
                Block { x: 50; y: 6; width: 40; height: 22; color: dwindleTile.faint }
                Block { x: 50; y: 32; width: 19; height: 22; color: dwindleTile.faint }
                Block { x: 71; y: 32; width: 19; height: 22; color: dwindleTile.faint }
            }
        }
        SchemeTile {
            id: masterTile
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 1
            frameWidth: Math.min(96, Math.max(54, (modes.width - 12) / modes.columns - 20))
            frameHeight: frameWidth * 60 / 96
            label: Translation.tr("Master")
            selected: parent.current === "master"
            onClicked: {
                HyprlandSettings.set("general:layout", "master");
                if (parent.free) parent.setMode("tiling");
            }
            Item {
                width: 96; height: 60
                transformOrigin: Item.TopLeft
                scale: masterTile.frameWidth / width
                Block { x: 6; y: 6; width: 50; height: 48; color: masterTile.ink }
                Block { x: 60; y: 6; width: 30; height: 14; color: masterTile.faint }
                Block { x: 60; y: 23; width: 30; height: 14; color: masterTile.faint }
                Block { x: 60; y: 40; width: 30; height: 14; color: masterTile.faint }
            }
        }
        SchemeTile {
            id: freeTile
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 1
            frameWidth: Math.min(96, Math.max(54, (modes.width - 12) / modes.columns - 20))
            frameHeight: frameWidth * 60 / 96
            label: Translation.tr("Free windows")
            selected: parent.current === "floating"
            onClicked: parent.setMode("floating")
            Item {
                width: 96; height: 60
                transformOrigin: Item.TopLeft
                scale: freeTile.frameWidth / width
                Block { x: 8; y: 8; width: 48; height: 30; color: freeTile.faint }
                Block { x: 30; y: 20; width: 54; height: 34; color: freeTile.ink }
            }
        }
        SchemeTile {
            id: canvasTile
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.preferredWidth: 1
            frameWidth: freeTile.frameWidth
            frameHeight: freeTile.frameHeight
            label: Translation.tr("Infinite canvas")
            selected: modes.current === "canvas"
            onClicked: modes.setMode("canvas")
            Item {
                width: 96; height: 60
                transformOrigin: Item.TopLeft
                scale: canvasTile.frameWidth / width
                Block { x: 5; y: 12; width: 28; height: 20; color: canvasTile.faint }
                Block { x: 39; y: 6; width: 44; height: 28; color: canvasTile.ink }
                Block { x: 54; y: 39; width: 34; height: 16; color: canvasTile.faint }
            }
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        SettingsBranch {
            id: overviewBranch
            key: "overview"
            page: rootPage

            GridLayout {
                id: desktopGrid
                Layout.fillWidth: true
                columns: width >= 590 ? 2 : 1
                uniformCellWidths: true
                columnSpacing: 16
                rowSpacing: 12

                ContentSection {
                    id: desktopPreviewSection
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    card: false
                    icon: "desktop_windows"
                    title: Translation.tr("Your desktop")
                    searchText: title + " " + Translation.tr("Preview")
                    Loader {
                        Layout.fillWidth: true
                        Layout.maximumWidth: desktopGrid.columns === 1 ? 380 : Infinity
                        Layout.alignment: Qt.AlignHCenter
                        active: rootPage.pageShown && overviewBranch.shown
                        sourceComponent: DesktopPreview {
                            // Opens that corner's list of actions in the Hot corners section
                            onCornerClicked: corner => {
                                rootPage.tab = "corners";
                                const choice = rootPage.findChild(hotCornersSection, "hotCorner-" + corner);
                                if (choice) {
                                    rootPage.revealItem(choice, false);
                                    Qt.callLater(() => choice.openPopup());
                                }
                            }
                        }
                    }
                }
                ContentSection {
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    minimumCardHeight: desktopGrid.columns === 2 ? desktopPreviewSection.naturalCardHeight : 0
                    title: Translation.tr("How windows behave")
                    ContentSubsection {
                        enabled: HyprlandSettings.ready
                        WindowModes {}
                        StyledText {
                            visible: HyprlandSettings.windowMode === "canvas"
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            color: Appearance.colors.colSubtext
                            text: Translation.tr("Super + middle drag pans. Super + scroll zooms. Super + Home fits all windows. Super + End returns to 100%.")
                        }
                    }
                    HyprSlider {
                        visible: desktopGrid.width >= 700
                        option: "general:gaps_in"
                        fallback: 5
                        integer: true
                        from: 0; to: 30
                        textWidth: 84
                        buttonIcon: "border_inner"
                        text: Translation.tr("Gaps between windows")
                    }
                    SettingsBranchLink {
                        branch: windowsBranch
                        title: Translation.tr("Window settings")
                        buttonIcon: "view_quilt"
                        summary: HyprlandSettings.windowMode === "canvas" ? Translation.tr("Infinite canvas")
                            : HyprlandSettings.windowMode === "floating" ? Translation.tr("Free windows")
                            : HyprlandSettings.get("general:layout", "dwindle") === "master" ? Translation.tr("Master") : Translation.tr("Dwindle")
                        detail: Translation.tr("Borders, gaps and focus")
                    }
                }
            }
            ContentSection {
                title: Translation.tr("Dock")
                ConfigComboRow {
                    icon: "visibility"
                    text: Translation.tr("When it shows")
                    currentValue: rootPage.dockMode
                    options: [
                        { displayName: Translation.tr("Always"), value: "always" },
                        { displayName: Translation.tr("On hover"), value: "hover" },
                        { displayName: Translation.tr("On an empty desktop"), value: "empty" },
                        { displayName: Translation.tr("Off"), value: "off" }
                    ]
                    onSelected: value => rootPage.setDockMode(value)
                }
                DockSize {}
                SettingsBranchLink {
                    branch: dockBranch
                    title: Translation.tr("Appearance and apps")
                    buttonIcon: "dock_to_bottom"
                    summary: Translation.tr("%1 pinned · %2 hidden").arg(rootPage.dock.pinnedApps.filter(app => app !== "SEPARATOR").length).arg(rootPage.dock.ignoredAppRegexes.length)
                }
            }
            GridLayout {
                Layout.fillWidth: true
                columns: width >= 510 ? 2 : 1
                uniformCellWidths: true
                columnSpacing: 12
                rowSpacing: 8
                DesktopBranchTile {
                    id: workspaceTile
                    branch: workspacesBranch
                    accent: Appearance.colors.colTertiary
                    summary: Config.options.overview.enable ? Config.options.overview.rows + " × " + Config.options.overview.columns : Translation.tr("Off")
                    Grid {
                        anchors.centerIn: parent
                        columns: Math.max(1, Config.options.overview.columns)
                        spacing: 2
                        Repeater {
                            model: Config.options.overview.rows * Config.options.overview.columns
                            Rectangle {
                                required property int index
                                width: Math.max(1, (46 - 2 * (parent.columns - 1)) / parent.columns)
                                height: Math.min(12, Math.max(1, (30 - 2 * (Config.options.overview.rows - 1)) / Math.max(1, Config.options.overview.rows)))
                                radius: 2
                                color: index === 0 ? workspaceTile.accent : ColorUtils.mix(workspaceTile.accent, Appearance.colors.colLayer2, 0.44)
                            }
                        }
                    }
                }
                DesktopBranchTile {
                    id: cornerTile
                    branch: cornersBranch
                    summary: Translation.tr("%1 of 4 enabled").arg(HotCorners.cornerNames.filter(corner => rootPage.hotCorners[corner].action !== "none").length)
                    Rectangle {
                        anchors.centerIn: parent
                        width: 44; height: 28; radius: 4
                        border.width: 1
                        border.color: ColorUtils.mix(cornerTile.accent, Appearance.colors.colLayer2, 0.4)
                        color: "transparent"
                        Repeater {
                            model: HotCorners.cornerNames
                            Rectangle {
                                required property string modelData
                                x: modelData.endsWith("Left") ? -2 : parent.width - width + 2
                                y: modelData.startsWith("top") ? -2 : parent.height - height + 2
                                width: 7; height: 7; radius: 3
                                color: rootPage.hotCorners[modelData].action !== "none" ? cornerTile.accent : Appearance.colors.colOutlineVariant
                            }
                        }
                    }
                }
            }
        }

        SettingsBranch {
            id: windowsBranch
            key: "windows"
            page: rootPage

            ContentSection {
                icon: "view_quilt"
                title: Translation.tr("Windows")
                description: Translation.tr("Free windows stay where you put them, as on Windows and macOS. Tiling puts new windows next to each other automatically.")

                ContentSubsection {
                    title: Translation.tr("How windows behave")
                    enabled: HyprlandSettings.ready
                    WindowModes {}
                    StyledText {
                        visible: HyprlandSettings.windowMode === "canvas"
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: Appearance.colors.colSubtext
                        text: Translation.tr("Super + middle drag pans. Super + scroll zooms. Super + Home fits all windows. Super + End returns to 100%.")
                    }
                }

                HyprSlider {
                    option: "general:gaps_in"
                    fallback: 5
                    integer: true
                    from: 0
                    to: 30
                    buttonIcon: "border_inner"
                    text: Translation.tr("Gaps between windows")
                }
                HyprSlider {
                    option: "general:gaps_out"
                    fallback: 10
                    integer: true
                    from: 0
                    to: 60
                    buttonIcon: "border_outer"
                    text: Translation.tr("Gaps around the screen")
                }
                HyprSlider {
                    option: "general:border_size"
                    fallback: 1
                    integer: true
                    from: 0
                    to: 8
                    buttonIcon: "border_style"
                    text: Translation.tr("Border width")
                }
                HyprSwitch {
                    option: "general:resize_on_border"
                    fallback: true
                    buttonIcon: "open_in_full"
                    text: Translation.tr("Resize by dragging the border")
                }
                HyprSwitch {
                    option: "general:snap:enabled"
                    fallback: true
                    buttonIcon: "grid_guides"
                    text: Translation.tr("Snap floating windows")
                }
                HyprSwitch {
                    option: "dwindle:preserve_split"
                    fallback: true
                    buttonIcon: "splitscreen_vertical_add"
                    text: Translation.tr("Keep split direction")
                    description: Translation.tr("A split stays horizontal or vertical when windows are resized")
                }
                HyprSwitch {
                    option: "misc:focus_on_activate"
                    fallback: true
                    buttonIcon: "ads_click"
                    text: Translation.tr("Focus apps that ask for attention")
                }
                HyprSwitch {
                    option: "misc:enable_swallow"
                    buttonIcon: "terminal"
                    text: Translation.tr("Terminal swallowing")
                    description: Translation.tr("An app started from a terminal takes the terminal's place")
                }
            }
        }

        SettingsBranch {
            id: dockBranch
            key: "dock"
            page: rootPage

            ContentSection {
                icon: "dock_to_bottom"
                title: Translation.tr("Dock")
                description: Translation.tr("Pinned and running apps at the bottom of the screen")

                ContentSubsection {
                    title: Translation.tr("When it shows")
                    Flow {
                        Layout.fillWidth: true
                        spacing: 4
                        SchemeTile {
                            id: alwaysTile
                            label: Translation.tr("Always")
                            selected: rootPage.dockMode === "always"
                            onClicked: rootPage.setDockMode("always")
                            Block { x: 6; y: 6; width: 84; height: 32; color: alwaysTile.faint }
                            Block { x: 26; y: 43; width: 44; height: 11; radius: 4; color: alwaysTile.ink }
                        }
                        SchemeTile {
                            id: hoverTile
                            label: Translation.tr("On hover")
                            selected: rootPage.dockMode === "hover"
                            onClicked: rootPage.setDockMode("hover")
                            Block { x: 6; y: 6; width: 84; height: 48; color: hoverTile.faint }
                            Block { x: 26; y: 43; width: 44; height: 11; radius: 4; color: hoverTile.ink }
                            MaterialSymbol { x: 62; y: 36; text: "arrow_selector_tool"; iconSize: 16; fill: 1; color: hoverTile.ink }
                        }
                        SchemeTile {
                            id: emptyTile
                            label: Translation.tr("On an empty desktop")
                            selected: rootPage.dockMode === "empty"
                            onClicked: rootPage.setDockMode("empty")
                            Block { x: 26; y: 43; width: 44; height: 11; radius: 4; color: emptyTile.ink }
                        }
                        SchemeTile {
                            id: offTile
                            label: Translation.tr("Off")
                            selected: rootPage.dockMode === "off"
                            onClicked: rootPage.setDockMode("off")
                            Block { x: 6; y: 6; width: 84; height: 48; color: offTile.faint }
                        }
                    }
                }

                DockSize {}
                ConfigSwitch {
                    enabled: rootPage.dock.enable
                    buttonIcon: "zoom_in"
                    text: Translation.tr("Magnification")
                    description: Translation.tr("Enlarge icons as the pointer passes over the dock")
                    autoToggle: false
                    checked: rootPage.dock.magnification
                    onClicked: Config.options.dock.magnification = !rootPage.dock.magnification
                }
                ConfigSlider {
                    visible: rootPage.dock.magnification
                    enabled: rootPage.dock.enable
                    buttonIcon: "open_in_full"
                    text: Translation.tr("Magnified size")
                    from: 1.2
                    to: 2
                    defaultValue: 1.6
                    defaultValueText: "160%"
                    value: rootPage.dock.magnificationScale
                    valueText: `${Math.round(value * 100)}%`
                    onMoved: Config.options.dock.magnificationScale = Math.round(value * 20) / 20
                }
                ConfigSwitch {
                    enabled: rootPage.dock.enable
                    buttonIcon: "colors"
                    text: Translation.tr("Tint app icons")
                    autoToggle: false
                    checked: rootPage.dock.monochromeIcons
                    onClicked: Config.options.dock.monochromeIcons = !rootPage.dock.monochromeIcons
                }

                SettingsBranchLink {
                    branch: dockAppsBranch
                    buttonIcon: "apps"
                    summary: Translation.tr("%1 pinned · %2 hidden").arg(rootPage.dock.pinnedApps.filter(app => app !== "SEPARATOR").length).arg(rootPage.dock.ignoredAppRegexes.length)
                }
            }
        }

        SettingsBranch {
            id: dockAppsBranch
            key: "dockApps"
            page: rootPage

            ContentSection {
                title: Translation.tr("Dock apps")
                ContentSubsection {
                    title: Translation.tr("Pinned apps")
                    description: Translation.tr("Always in the dock, running or not. Hover one to move or unpin it.")
                    PinnedAppsEditor {}
                }

                ContentSubsection {
                    title: Translation.tr("Hidden from the dock")
                    description: Translation.tr("These apps don't show in the dock even while they run")
                    HiddenAppsEditor {}
                }
            }
        }

        SettingsBranch {
            id: workspacesBranch
            key: "workspaces"
            page: rootPage

            GridLayout {
                id: workspaceGrid
                Layout.fillWidth: true
                columns: width >= 590 ? 2 : 1
                uniformCellWidths: true
                columnSpacing: 16
                rowSpacing: 14
                ContentSection {
                    id: gridSection
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    minimumCardHeight: workspaceGrid.columns === 2 ? orderSection.naturalCardHeight : 0
                    icon: "overview_key"
                    title: Translation.tr("Workspace overview")
                    searchText: `${title} ${Translation.tr("Workspaces in the overview")} Super Tab`
                    ConfigSwitch {
                        buttonIcon: "overview_key"
                        text: Translation.tr("Enable overview")
                        autoToggle: false
                        checked: Config.options.overview.enable
                        onClicked: Config.options.overview.enable = !checked
                    }
                    GridSizePicker {
                        enabled: Config.options.overview.enable
                        rows: Config.options.overview.rows
                        columns: Config.options.overview.columns
                        rightToLeft: Config.options.overview.orderRightLeft
                        bottomUp: Config.options.overview.orderBottomUp
                        onPicked: (rows, columns) => {
                            Config.options.overview.rows = rows;
                            Config.options.overview.columns = columns;
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.margins: 10
                        spacing: 6
                        KeyboardKey { key: "Super" }
                        StyledText { text: "+"; color: Appearance.colors.colSubtext }
                        KeyboardKey { key: "Tab" }
                        Item { Layout.fillWidth: true }
                        DialogButton {
                            buttonText: Translation.tr("Open overview")
                            enabled: Config.options.overview.enable
                            onClicked: Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "search", "open"])
                        }
                    }
                }
                ContentSection {
                    id: orderSection
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    minimumCardHeight: workspaceGrid.columns === 2 ? gridSection.naturalCardHeight : 0
                    title: Translation.tr("Order and appearance")
                    enabled: Config.options.overview.enable
                    ConfigComboRow {
                        maximumWidth: 144
                        icon: "swap_horiz"
                        text: Translation.tr("Columns")
                        currentValue: Config.options.overview.orderRightLeft
                        options: [{displayName: Translation.tr("Rightwards"), description: Translation.tr("Left to right"), value: false}, {displayName: Translation.tr("Leftwards"), description: Translation.tr("Right to left"), value: true}]
                        onSelected: value => Config.options.overview.orderRightLeft = value
                    }
                    ConfigComboRow {
                        maximumWidth: 144
                        icon: "swap_vert"
                        text: Translation.tr("Rows")
                        currentValue: Config.options.overview.orderBottomUp
                        options: [{displayName: Translation.tr("Downwards"), description: Translation.tr("Top-down"), value: false}, {displayName: Translation.tr("Upwards"), description: Translation.tr("Bottom-up"), value: true}]
                        onSelected: value => Config.options.overview.orderBottomUp = value
                    }
                    ConfigSwitch {
                        buttonIcon: "center_focus_strong"
                        text: Translation.tr("Center icons")
                        autoToggle: false
                        checked: Config.options.overview.centerIcons
                        onClicked: Config.options.overview.centerIcons = !checked
                    }
                    ConfigSlider {
                        enabled: Config.options.overview.enable
                        textWidth: 84
                        buttonIcon: "loupe"
                        text: Translation.tr("Size of each workspace")
                        from: 0.08; to: 0.4
                        defaultValue: 0.18
                        defaultValueText: "18%"
                        value: Config.options.overview.scale
                        valueText: Math.round(value * 100) + "%"
                        onMoved: Config.options.overview.scale = Math.round(value * 100) / 100
                    }
                }
            }

            ContentSection {
                icon: "workspaces"
                title: Translation.tr("Workspace navigation")

                HyprSlider {
                    option: "general:gaps_workspaces"
                    fallback: 50
                    integer: true
                    from: 0
                    to: 200
                    buttonIcon: "width"
                    text: Translation.tr("Space between workspaces")
                    description: Translation.tr("Seen while switching workspaces")
                }
                ConfigNavRow {
                    buttonIcon: "workspaces"
                    title: Translation.tr("Workspace indicator")
                    description: Translation.tr("How many are shown in the bar and how they're numbered")
                    onClicked: ApplicationWindow.window?.openPage("bar", Translation.tr("Widget settings"))
                }
                ConfigNavRow {
                    buttonIcon: "swipe"
                    title: Translation.tr("Swipe gestures")
                    onClicked: ApplicationWindow.window?.openPage("mouse", Translation.tr("Gestures"))
                }
            }
        }

        SettingsBranch {
            id: cornersBranch
            key: "corners"
            page: rootPage

            ContentSection {
                id: hotCornersSection
                icon: "south_east"
                title: Translation.tr("Hot corners")
                description: Translation.tr("Push the pointer into a corner of the screen to do something. Each corner can do anything you like.")

                Rectangle { // The screen, with each corner's action in that corner
                    id: cornerScreen
                    Layout.fillWidth: true
                    implicitHeight: 210
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer2
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant
                    clip: true

                    StyledText {
                        anchors.centerIn: parent
                        text: Translation.tr("Your screen")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }

                    Repeater {
                        model: HotCorners.cornerNames
                        delegate: Item {
                            id: cornerSpot
                            required property string modelData
                            readonly property bool isTop: modelData.startsWith("top")
                            readonly property bool isLeft: modelData.endsWith("Left")
                            readonly property string action: rootPage.hotCorners[modelData]?.action ?? "none"
                            anchors.fill: parent

                            Rectangle { // The corner's glow, as on the real screen
                                readonly property real glowRadius: cornerSpot.action !== "none" ? 34 : 0
                                width: glowRadius * 2
                                height: glowRadius * 2
                                radius: glowRadius
                                x: cornerSpot.isLeft ? -glowRadius : parent.width - glowRadius
                                y: cornerSpot.isTop ? -glowRadius : parent.height - glowRadius
                                color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.6)
                                Behavior on width {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                }
                                Behavior on height {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                }
                            }
                            ChoiceDropdown {
                                id: cornerChoice
                                objectName: `hotCorner-${cornerSpot.modelData}`
                                anchors {
                                    top: cornerSpot.isTop ? parent.top : undefined
                                    bottom: cornerSpot.isTop ? undefined : parent.bottom
                                    left: cornerSpot.isLeft ? parent.left : undefined
                                    right: cornerSpot.isLeft ? undefined : parent.right
                                    margins: 14
                                }
                                options: HotCorners.actions
                                currentValue: cornerSpot.action
                                onSelected: value => Config.options.hotCorners[cornerSpot.modelData].action = value
                            }
                        }
                    }
                }

                Repeater { // Commands for corners set to run one
                    model: HotCorners.cornerNames.filter(name => rootPage.hotCorners[name]?.action === "command")
                    delegate: ConfigTextRow {
                        required property string modelData
                        icon: "terminal"
                        inline: true
                        label: {
                            switch (modelData) {
                            case "topLeft": return Translation.tr("Command for the top left corner");
                            case "topRight": return Translation.tr("Command for the top right corner");
                            case "bottomLeft": return Translation.tr("Command for the bottom left corner");
                            default: return Translation.tr("Command for the bottom right corner");
                            }
                        }
                        value: rootPage.hotCorners[modelData]?.command ?? ""
                        placeholderText: "kitty"
                        onEditingFinished: Config.options.hotCorners[modelData].command = value
                    }
                }

                ContentSubsection {
                    title: Translation.tr("How a corner reacts")
                    searchText: `${title} ${Translation.tr("Touch the corner")} ${Translation.tr("Click in the corner")}`
                    Flow {
                        Layout.fillWidth: true
                        spacing: 4
                        SchemeTile {
                            id: touchCornerTile
                            label: Translation.tr("Touch the corner")
                            selected: rootPage.hotCorners.trigger !== "click"
                            onClicked: Config.options.hotCorners.trigger = "hover"
                            CornerGlow { x: 82; y: -14; color: touchCornerTile.ink }
                            MaterialSymbol { x: 58; y: 10; text: "arrow_selector_tool"; iconSize: 20; fill: 1; color: touchCornerTile.ink }
                        }
                        SchemeTile {
                            id: clickTile
                            label: Translation.tr("Click in the corner")
                            selected: rootPage.hotCorners.trigger === "click"
                            onClicked: Config.options.hotCorners.trigger = "click"
                            CornerGlow { x: 82; y: -14; color: clickTile.ink }
                            MaterialSymbol { x: 58; y: 10; text: "left_click"; iconSize: 20; fill: 1; color: clickTile.ink }
                        }
                    }
                }

                ConfigSwitch {
                    buttonIcon: "flare"
                    text: Translation.tr("Show where the corners are")
                    description: Translation.tr("A small glow sits in each corner that does something, and grows when you reach it")
                    autoToggle: false
                    checked: rootPage.hotCorners.hint
                    onClicked: Config.options.hotCorners.hint = !rootPage.hotCorners.hint
                }
                ConfigSwitch {
                    buttonIcon: "fullscreen"
                    text: Translation.tr("Also over fullscreen apps and games")
                    autoToggle: false
                    checked: rootPage.hotCorners.inFullscreen
                    onClicked: Config.options.hotCorners.inFullscreen = !rootPage.hotCorners.inFullscreen
                }
                ConfigSwitch {
                    buttonIcon: "unfold_more_double"
                    text: Translation.tr("Scroll in a corner")
                    description: Translation.tr("Left corners change brightness, right corners the volume")
                    autoToggle: false
                    checked: rootPage.hotCorners.scroll
                    onClicked: Config.options.hotCorners.scroll = !rootPage.hotCorners.scroll
                }
                ConfigExpander {
                    title: Translation.tr("More corner options")
                    ConfigSlider {
                        buttonIcon: "crop_square"
                        text: Translation.tr("Size of the corner")
                        description: Translation.tr("Bigger is easier to reach, but can get in the way of window buttons")
                        usePercentTooltip: false
                        from: 2
                        to: 40
                        defaultValue: 12
                        defaultValueText: "12 px"
                        value: rootPage.hotCorners.size
                        valueText: `${Math.round(value)} px`
                        onMoved: Config.options.hotCorners.size = Math.round(value)
                    }
                }
            }
        }
    }

    // Drawing pieces for the scheme tiles
    component Block: Rectangle {
        radius: 3
    }
    component CornerGlow: Rectangle {
        width: 28
        height: 28
        radius: 14
        opacity: 0.8
    }
}
