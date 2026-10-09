import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    ContentSection {
        title: Translation.tr("Windows")
        description: Translation.tr("Tiling puts new windows next to each other automatically. Snapping helps align floating ones.")

        HyprChoice {
            option: "general:layout"
            fallback: "dwindle"
            title: Translation.tr("Tiling layout")
            description: Translation.tr("Dwindle splits the space in half each time, master keeps one big window and stacks the rest")
            choices: [
                { displayName: Translation.tr("Dwindle"), icon: "view_quilt", value: "dwindle" },
                { displayName: Translation.tr("Master"), icon: "view_sidebar", value: "master" }
            ]
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
            onClicked: ApplicationWindow.window?.openPage("bar", Translation.tr("Workspaces"))
        }
        ConfigNavRow {
            buttonIcon: "swipe"
            title: Translation.tr("Swipe gestures")
            onClicked: ApplicationWindow.window?.openPage("mouse", Translation.tr("Gestures"))
        }
    }

    ContentSection {
        title: Translation.tr("Dock")
        description: Translation.tr("Pinned and running apps at the bottom of the screen")

        ConfigSwitch {
            buttonIcon: "call_to_action"
            text: Translation.tr("Show dock")
            autoToggle: false
            checked: Config.options.dock.enable
            onClicked: Config.options.dock.enable = !Config.options.dock.enable
        }
        ConfigSwitch {
            enabled: Config.options.dock.enable
            buttonIcon: "highlight_mouse_cursor"
            text: Translation.tr("Hover to reveal")
            checked: Config.options.dock.hoverToReveal
            onCheckedChanged: {
                Config.options.dock.hoverToReveal = checked;
            }
        }
        ConfigSwitch {
            enabled: Config.options.dock.enable
            buttonIcon: "keep"
            text: Translation.tr("Always show the dock")
            description: Translation.tr("Windows make room for it instead of going under it")
            checked: Config.options.dock.pinnedOnStartup
            onCheckedChanged: {
                Config.options.dock.pinnedOnStartup = checked;
            }
        }
        ConfigSwitch {
            enabled: Config.options.dock.enable
            buttonIcon: "zoom_in"
            text: Translation.tr("Magnification")
            description: Translation.tr("Icons grow as the pointer passes over them")
            checked: Config.options.dock.magnification
            onCheckedChanged: {
                Config.options.dock.magnification = checked;
            }
        }
        ConfigSlider {
            enabled: Config.options.dock.enable && Config.options.dock.magnification
            buttonIcon: "open_in_full"
            text: Translation.tr("Magnified size")
            from: 1.2
            to: 2
            value: Config.options.dock.magnificationScale
            valueText: `${Math.round(value * 100)}%`
            onMoved: {
                Config.options.dock.magnificationScale = Math.round(value * 20) / 20;
            }
        }
        ConfigSwitch {
            enabled: Config.options.dock.enable
            buttonIcon: "colors"
            text: Translation.tr("Tint app icons")
            checked: Config.options.dock.monochromeIcons
            onCheckedChanged: {
                Config.options.dock.monochromeIcons = checked;
            }
        }
    }

    ContentSection {
        title: Translation.tr("Overview")
        description: Translation.tr("All workspaces with live window previews and app search")

        ConfigSwitch {
            buttonIcon: "overview_key"
            text: Translation.tr("Enable overview")
            autoToggle: false
            checked: Config.options.overview.enable
            onClicked: Config.options.overview.enable = !Config.options.overview.enable
        }
        ConfigSwitch {
            enabled: Config.options.overview.enable
            buttonIcon: "center_focus_strong"
            text: Translation.tr("Center icons")
            checked: Config.options.overview.centerIcons
            onCheckedChanged: {
                Config.options.overview.centerIcons = checked;
            }
        }
        ConfigSpinBox {
            enabled: Config.options.overview.enable
            icon: "loupe"
            text: Translation.tr("Scale (%)")
            value: Config.options.overview.scale * 100
            from: 1
            to: 100
            stepSize: 1
            onValueChanged: {
                Config.options.overview.scale = value / 100;
            }
        }
        ConfigSpinBox {
            enabled: Config.options.overview.enable
            icon: "splitscreen_bottom"
            text: Translation.tr("Rows")
            value: Config.options.overview.rows
            from: 1
            to: 20
            stepSize: 1
            onValueChanged: {
                Config.options.overview.rows = value;
            }
        }
        ConfigSpinBox {
            enabled: Config.options.overview.enable
            icon: "splitscreen_right"
            text: Translation.tr("Columns")
            value: Config.options.overview.columns
            from: 1
            to: 20
            stepSize: 1
            onValueChanged: {
                Config.options.overview.columns = value;
            }
        }
        ContentSubsection {
            enabled: Config.options.overview.enable
            title: Translation.tr("Order")
            ConfigSelectionArray {
                currentValue: Config.options.overview.orderRightLeft
                onSelected: newValue => {
                    Config.options.overview.orderRightLeft = newValue
                }
                options: [
                    { displayName: Translation.tr("Left to right"), icon: "arrow_forward", value: 0 },
                    { displayName: Translation.tr("Right to left"), icon: "arrow_back", value: 1 }
                ]
            }
            ConfigSelectionArray {
                currentValue: Config.options.overview.orderBottomUp
                onSelected: newValue => {
                    Config.options.overview.orderBottomUp = newValue
                }
                options: [
                    { displayName: Translation.tr("Top-down"), icon: "arrow_downward", value: 0 },
                    { displayName: Translation.tr("Bottom-up"), icon: "arrow_upward", value: 1 }
                ]
            }
        }
    }

    ContentSection {
        title: Translation.tr("Hot corners")
        description: Translation.tr("Open sidebars by clicking or hovering screen corners regardless of bar position")

        ConfigSwitch {
            buttonIcon: "south_east"
            text: Translation.tr("Open sidebars from corners")
            checked: Config.options.sidebar.cornerOpen.enable
            onCheckedChanged: {
                Config.options.sidebar.cornerOpen.enable = checked;
            }
        }
        ConfigRow {
            enabled: Config.options.sidebar.cornerOpen.enable
            ConfigSwitch {
                buttonIcon: "highlight_mouse_cursor"
                text: Translation.tr("Hover to trigger")
                description: Translation.tr("When this is off you'll have to click")
                checked: Config.options.sidebar.cornerOpen.clickless
                onCheckedChanged: {
                    Config.options.sidebar.cornerOpen.clickless = checked;
                }
            }
            ConfigSwitch {
                enabled: !Config.options.sidebar.cornerOpen.clickless
                buttonIcon: "south_east"
                text: Translation.tr("Force hover open at absolute corner")
                description: Translation.tr("You can still hover the very corner to open the sidebar, and the rest of the area scrolls volume and brightness")
                checked: Config.options.sidebar.cornerOpen.clicklessCornerEnd
                onCheckedChanged: {
                    Config.options.sidebar.cornerOpen.clicklessCornerEnd = checked;
                }
            }
            ConfigSpinBox {
                enabled: !Config.options.sidebar.cornerOpen.clickless && Config.options.sidebar.cornerOpen.clicklessCornerEnd
                icon: "arrow_cool_down"
                text: Translation.tr("Vertical offset of the corner end")
                description: Translation.tr("For non-0 values, it won't trigger when you reach the screen corner along the horizontal edge, but it will when you do along the vertical edge")
                value: Config.options.sidebar.cornerOpen.clicklessCornerVerticalOffset
                from: 0
                to: 20
                stepSize: 1
                onValueChanged: {
                    Config.options.sidebar.cornerOpen.clicklessCornerVerticalOffset = value;
                }
            }
            ConfigSwitch {
                buttonIcon: "vertical_align_bottom"
                text: Translation.tr("Place at bottom")
                description: Translation.tr("Place the corners to trigger at the bottom")
                checked: Config.options.sidebar.cornerOpen.bottom
                onCheckedChanged: {
                    Config.options.sidebar.cornerOpen.bottom = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "unfold_more_double"
                text: Translation.tr("Value scroll")
                description: Translation.tr("Scroll on the corner to change brightness and volume")
                checked: Config.options.sidebar.cornerOpen.valueScroll
                onCheckedChanged: {
                    Config.options.sidebar.cornerOpen.valueScroll = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "visibility"
                text: Translation.tr("Visualize region")
                checked: Config.options.sidebar.cornerOpen.visualize
                onCheckedChanged: {
                    Config.options.sidebar.cornerOpen.visualize = checked;
                }
            }
            ConfigSpinBox {
                icon: "arrow_range"
                text: Translation.tr("Region width")
                value: Config.options.sidebar.cornerOpen.cornerRegionWidth
                from: 1
                to: 300
                stepSize: 1
                onValueChanged: {
                    Config.options.sidebar.cornerOpen.cornerRegionWidth = value;
                }
            }
            ConfigSpinBox {
                icon: "height"
                text: Translation.tr("Region height")
                value: Config.options.sidebar.cornerOpen.cornerRegionHeight
                from: 1
                to: 300
                stepSize: 1
                onValueChanged: {
                    Config.options.sidebar.cornerOpen.cornerRegionHeight = value;
                }
            }
        }
    }
}
