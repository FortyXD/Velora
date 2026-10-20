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
ContentPage {
    id: page
    readonly property var dock: Config.options.dock
    readonly property var corners: Config.options.sidebar.cornerOpen
    readonly property string dockMode: !page.dock.enable ? "off"
        : page.dock.pinnedOnStartup ? "always"
        : page.dock.hoverToReveal ? "hover" : "empty"

    function setDockMode(mode) {
        Config.options.dock.enable = mode !== "off";
        if (mode === "off") return;
        Config.options.dock.pinnedOnStartup = mode === "always";
        Config.options.dock.hoverToReveal = mode === "hover";
    }

    ContentSection {
        icon: "desktop_windows"
        title: Translation.tr("Your desktop")
        card: false
        searchText: `${title} ${Translation.tr("Preview")}`

        DesktopPreview {
            Layout.fillWidth: true
            onCornerClicked: bottom => Config.options.sidebar.cornerOpen.bottom = bottom
        }
    }

    ContentSection {
        icon: "view_quilt"
        title: Translation.tr("Windows")
        description: Translation.tr("Tiling puts new windows next to each other automatically. Snapping helps align floating ones.")

        ContentSubsection {
            title: Translation.tr("Tiling layout")
            enabled: HyprlandSettings.ready
            Flow {
                Layout.fillWidth: true
                spacing: 4
                readonly property string current: HyprlandSettings.get("general:layout", "dwindle")
                SchemeTile {
                    id: dwindleTile
                    label: Translation.tr("Dwindle")
                    selected: parent.current === "dwindle"
                    onClicked: HyprlandSettings.set("general:layout", "dwindle")
                    Block { x: 6; y: 6; width: 40; height: 48; color: dwindleTile.ink }
                    Block { x: 50; y: 6; width: 40; height: 22; color: dwindleTile.faint }
                    Block { x: 50; y: 32; width: 19; height: 22; color: dwindleTile.faint }
                    Block { x: 71; y: 32; width: 19; height: 22; color: dwindleTile.faint }
                }
                SchemeTile {
                    id: masterTile
                    label: Translation.tr("Master")
                    selected: parent.current === "master"
                    onClicked: HyprlandSettings.set("general:layout", "master")
                    Block { x: 6; y: 6; width: 50; height: 48; color: masterTile.ink }
                    Block { x: 60; y: 6; width: 30; height: 14; color: masterTile.faint }
                    Block { x: 60; y: 23; width: 30; height: 14; color: masterTile.faint }
                    Block { x: 60; y: 40; width: 30; height: 14; color: masterTile.faint }
                }
            }
        }

        HyprSlider {
            option: "general:gaps_in"
            fallback: 4
            integer: true
            from: 0
            to: 30
            buttonIcon: "border_inner"
            text: Translation.tr("Gaps between windows")
        }
        HyprSlider {
            option: "general:gaps_out"
            fallback: 5
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
                    selected: page.dockMode === "always"
                    onClicked: page.setDockMode("always")
                    Block { x: 6; y: 6; width: 84; height: 32; color: alwaysTile.faint }
                    Block { x: 26; y: 43; width: 44; height: 11; radius: 4; color: alwaysTile.ink }
                }
                SchemeTile {
                    id: hoverTile
                    label: Translation.tr("On hover")
                    selected: page.dockMode === "hover"
                    onClicked: page.setDockMode("hover")
                    Block { x: 6; y: 6; width: 84; height: 48; color: hoverTile.faint }
                    Block { x: 26; y: 43; width: 44; height: 11; radius: 4; color: hoverTile.ink }
                    MaterialSymbol { x: 62; y: 36; text: "arrow_selector_tool"; iconSize: 16; fill: 1; color: hoverTile.ink }
                }
                SchemeTile {
                    id: emptyTile
                    label: Translation.tr("On an empty desktop")
                    selected: page.dockMode === "empty"
                    onClicked: page.setDockMode("empty")
                    Block { x: 26; y: 43; width: 44; height: 11; radius: 4; color: emptyTile.ink }
                }
                SchemeTile {
                    id: offTile
                    label: Translation.tr("Off")
                    selected: page.dockMode === "off"
                    onClicked: page.setDockMode("off")
                    Block { x: 6; y: 6; width: 84; height: 48; color: offTile.faint }
                }
            }
        }

        ConfigSlider {
            enabled: page.dock.enable
            buttonIcon: "photo_size_select_large"
            text: Translation.tr("Size")
            usePercentTooltip: false
            from: 40
            to: 96
            value: page.dock.height
            valueText: `${Math.round(value)} px`
            onMoved: Config.options.dock.height = Math.round(value)
        }
        ConfigSwitch {
            enabled: page.dock.enable
            buttonIcon: "zoom_in"
            text: Translation.tr("Magnification")
            description: Translation.tr("Icons grow as the pointer passes over them; try it on the dock above")
            autoToggle: false
            checked: page.dock.magnification
            onClicked: Config.options.dock.magnification = !page.dock.magnification
        }
        ConfigSlider {
            visible: page.dock.magnification
            enabled: page.dock.enable
            buttonIcon: "open_in_full"
            text: Translation.tr("Magnified size")
            from: 1.2
            to: 2
            value: page.dock.magnificationScale
            valueText: `${Math.round(value * 100)}%`
            onMoved: Config.options.dock.magnificationScale = Math.round(value * 20) / 20
        }
        ConfigSwitch {
            enabled: page.dock.enable
            buttonIcon: "colors"
            text: Translation.tr("Tint app icons")
            autoToggle: false
            checked: page.dock.monochromeIcons
            onClicked: Config.options.dock.monochromeIcons = !page.dock.monochromeIcons
        }

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

    ContentSection {
        icon: "overview_key"
        title: Translation.tr("Workspace overview")
        description: Translation.tr("Search and all your workspaces at a glance, on one key")
        searchText: `${title} ${Translation.tr("Overview")} Super ${Translation.tr("Search")} ${Translation.tr("Workspaces")}`

        // What the overview is: a sketch of it, the keys that open it and a way to try it
        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 12
            spacing: 16

            Rectangle {
                id: overviewSketch
                readonly property int rows: Config.options.overview.rows
                readonly property int columns: Config.options.overview.columns
                implicitWidth: 210
                implicitHeight: 132
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer3

                Rectangle { // Search field
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 10
                    width: 110
                    height: 16
                    radius: 8
                    color: Appearance.colors.colLayer1
                    MaterialSymbol {
                        x: 5
                        anchors.verticalCenter: parent.verticalCenter
                        text: "search"
                        iconSize: 11
                        color: Appearance.colors.colSubtext
                    }
                }
                Grid { // The workspaces, with a window or two in some
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 34
                    columns: overviewSketch.columns
                    spacing: 3
                    Repeater {
                        model: overviewSketch.rows * overviewSketch.columns
                        delegate: Rectangle {
                            required property int index
                            width: Math.min(34, (190 - 3 * (overviewSketch.columns - 1)) / overviewSketch.columns)
                            height: Math.min(width * 0.62, (88 - 3 * (overviewSketch.rows - 1)) / overviewSketch.rows)
                            radius: 3
                            color: index === 0 ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1
                            border.width: index === 0 ? 1 : 0
                            border.color: Appearance.colors.colPrimary
                            Rectangle {
                                visible: index % 3 !== 2
                                x: 2
                                y: 2
                                width: index % 3 === 0 ? parent.width / 2 - 3 : parent.width - 4
                                height: parent.height - 4
                                radius: 2
                                color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.75)
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: Translation.tr("A screen with a search field and every workspace in small, with its windows. Type to find an app or a file, click a workspace to go there, drag a window to move it to another one.")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer2
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    StyledText {
                        height: 26
                        verticalAlignment: Text.AlignVCenter
                        text: Translation.tr("Opens with")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                    KeyboardKey {
                        key: "Super"
                    }
                    StyledText {
                        height: 26
                        verticalAlignment: Text.AlignVCenter
                        text: Translation.tr("tapped, or")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                    KeyboardKey {
                        key: "Super"
                    }
                    StyledText {
                        height: 26
                        verticalAlignment: Text.AlignVCenter
                        text: "+"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                    KeyboardKey {
                        key: "Tab"
                    }
                }
                DialogButton {
                    buttonText: Translation.tr("Open it now")
                    enabled: Config.options.overview.enable
                    onClicked: Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "search", "open"])
                }
            }
        }

        ConfigSwitch {
            buttonIcon: "overview_key"
            text: Translation.tr("Enable overview")
            autoToggle: false
            checked: Config.options.overview.enable
            onClicked: Config.options.overview.enable = !Config.options.overview.enable
        }

        ContentSubsection {
            enabled: Config.options.overview.enable
            title: Translation.tr("Workspaces in the overview")
            description: Translation.tr("Hover the grid to pick rows and columns")
            GridSizePicker {
                rows: Config.options.overview.rows
                columns: Config.options.overview.columns
                onPicked: (rows, columns) => {
                    Config.options.overview.rows = rows;
                    Config.options.overview.columns = columns;
                }
            }
        }

        ConfigSlider {
            enabled: Config.options.overview.enable
            buttonIcon: "loupe"
            text: Translation.tr("Size of each workspace")
            from: 0.08
            to: 0.4
            value: Config.options.overview.scale
            valueText: `${Math.round(value * 100)}%`
            onMoved: Config.options.overview.scale = Math.round(value * 100) / 100
        }
        ConfigSwitch {
            enabled: Config.options.overview.enable
            buttonIcon: "center_focus_strong"
            text: Translation.tr("Center icons")
            autoToggle: false
            checked: Config.options.overview.centerIcons
            onClicked: Config.options.overview.centerIcons = !Config.options.overview.centerIcons
        }
        ContentSubsection {
            enabled: Config.options.overview.enable
            title: Translation.tr("Order")
            ConfigSelectionArray {
                currentValue: Config.options.overview.orderRightLeft
                onSelected: newValue => Config.options.overview.orderRightLeft = newValue
                options: [
                    { displayName: Translation.tr("Left to right"), icon: "arrow_forward", value: false },
                    { displayName: Translation.tr("Right to left"), icon: "arrow_back", value: true }
                ]
            }
            ConfigSelectionArray {
                currentValue: Config.options.overview.orderBottomUp
                onSelected: newValue => Config.options.overview.orderBottomUp = newValue
                options: [
                    { displayName: Translation.tr("Top-down"), icon: "arrow_downward", value: false },
                    { displayName: Translation.tr("Bottom-up"), icon: "arrow_upward", value: true }
                ]
            }
        }
    }

    ContentSection {
        icon: "south_east"
        title: Translation.tr("Hot corners")
        description: Translation.tr("Open sidebars by clicking or hovering screen corners regardless of bar position. You can also click a corner of the desktop above.")

        ConfigSwitch {
            buttonIcon: "south_east"
            text: Translation.tr("Open sidebars from corners")
            autoToggle: false
            checked: page.corners.enable
            onClicked: Config.options.sidebar.cornerOpen.enable = !page.corners.enable
        }

        ContentSubsection {
            visible: page.corners.enable
            title: Translation.tr("Corners")
            Flow {
                Layout.fillWidth: true
                spacing: 4
                SchemeTile {
                    id: topCornersTile
                    label: Translation.tr("Top corners")
                    selected: !page.corners.bottom
                    onClicked: Config.options.sidebar.cornerOpen.bottom = false
                    CornerGlow { x: -14; y: -14; color: topCornersTile.ink }
                    CornerGlow { x: 82; y: -14; color: topCornersTile.ink }
                }
                SchemeTile {
                    id: bottomCornersTile
                    label: Translation.tr("Bottom corners")
                    selected: page.corners.bottom
                    onClicked: Config.options.sidebar.cornerOpen.bottom = true
                    CornerGlow { x: -14; y: 46; color: bottomCornersTile.ink }
                    CornerGlow { x: 82; y: 46; color: bottomCornersTile.ink }
                }
            }
        }

        ConfigSwitch {
            visible: page.corners.enable
            buttonIcon: "highlight_mouse_cursor"
            text: Translation.tr("Hover to trigger")
            description: Translation.tr("When this is off you'll have to click")
            autoToggle: false
            checked: page.corners.clickless
            onClicked: Config.options.sidebar.cornerOpen.clickless = !page.corners.clickless
        }
        ConfigSwitch {
            visible: page.corners.enable && !page.corners.clickless
            buttonIcon: "south_east"
            text: Translation.tr("Force hover open at absolute corner")
            description: Translation.tr("You can still hover the very corner to open the sidebar, and the rest of the area scrolls volume and brightness")
            autoToggle: false
            checked: page.corners.clicklessCornerEnd
            onClicked: Config.options.sidebar.cornerOpen.clicklessCornerEnd = !page.corners.clicklessCornerEnd
        }
        ConfigSlider {
            visible: page.corners.enable && !page.corners.clickless && page.corners.clicklessCornerEnd
            buttonIcon: "arrow_cool_down"
            text: Translation.tr("Vertical offset of the corner end")
            usePercentTooltip: false
            from: 0
            to: 20
            value: page.corners.clicklessCornerVerticalOffset
            valueText: `${Math.round(value)} px`
            onMoved: Config.options.sidebar.cornerOpen.clicklessCornerVerticalOffset = Math.round(value)
        }
        ConfigSwitch {
            visible: page.corners.enable
            buttonIcon: "unfold_more_double"
            text: Translation.tr("Value scroll")
            description: Translation.tr("Scroll on the corner to change brightness and volume")
            autoToggle: false
            checked: page.corners.valueScroll
            onClicked: Config.options.sidebar.cornerOpen.valueScroll = !page.corners.valueScroll
        }
        ConfigSwitch {
            visible: page.corners.enable
            buttonIcon: "visibility"
            text: Translation.tr("Visualize region")
            autoToggle: false
            checked: page.corners.visualize
            onClicked: Config.options.sidebar.cornerOpen.visualize = !page.corners.visualize
        }
        ConfigSlider {
            visible: page.corners.enable
            buttonIcon: "arrow_range"
            text: Translation.tr("Region width")
            usePercentTooltip: false
            from: 1
            to: 300
            value: page.corners.cornerRegionWidth
            valueText: `${Math.round(value)} px`
            onMoved: Config.options.sidebar.cornerOpen.cornerRegionWidth = Math.round(value)
        }
        ConfigSlider {
            visible: page.corners.enable
            buttonIcon: "height"
            text: Translation.tr("Region height")
            usePercentTooltip: false
            from: 1
            to: 300
            value: page.corners.cornerRegionHeight
            valueText: `${Math.round(value)} px`
            onMoved: Config.options.sidebar.cornerOpen.cornerRegionHeight = Math.round(value)
        }
    }

    ContentSection {
        icon: "workspaces"
        title: Translation.tr("Workspaces")

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
