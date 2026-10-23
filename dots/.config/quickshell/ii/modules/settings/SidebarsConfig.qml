import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.settings.preview

/**
 * Both sidebars drawn from their settings. Right: click a section to change it, drag it to move it,
 * the eye hides it. Left: the tabs, their order and how it opens.
 */
ContentPage {
    id: page
    property string side: "right"
    property string selected: "toggles" // Section of the right sidebar whose settings show
    property string leftSelected: "ai"
    readonly property var selectedSection: SidebarCatalog.section(page.selected)
    readonly property var screen: Quickshell.screens[0] ?? null

    // A chip that switches something on or off
    component ToggleChip: RippleButton {
        id: chip
        property string buttonIcon
        property bool active
        readonly property bool settingsSearchable: true
        property string searchText: chip.text
        implicitHeight: 36
        leftPadding: 12
        rightPadding: 14
        buttonRadius: Appearance.rounding.full
        colBackground: chip.active ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer3
        colBackgroundHover: chip.active ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer3Hover
        contentItem: RowLayout {
            spacing: 6
            MaterialSymbol {
                text: chip.active ? "check" : chip.buttonIcon
                iconSize: 18
                color: chip.active ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer3
            }
            StyledText {
                text: chip.text
                font.pixelSize: Appearance.font.pixelSize.small
                color: chip.active ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer3
            }
        }
    }

    // Where the sidebar opens on the screen, in proportion
    component Placement: MiniScreen {
        id: placement
        property bool onLeft: false
        property real panelWidth: Appearance.sizes.sidebarWidth
        readonly property real panelFraction: placement.panelWidth / (page.screen?.width ?? 1920)
        Rectangle {
            x: placement.onLeft ? 4 : parent.width - width - 4
            y: 4
            width: Math.max(8, parent.width * placement.panelFraction - 4)
            height: parent.height - 8
            radius: 6
            color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.1)
            border.width: 1
            border.color: Appearance.colors.colPrimary
            Behavior on width {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }

    ContentSection {
        icon: "side_navigation"
        title: Translation.tr("Sidebars")
        card: false
        searchText: `${title} ${Translation.tr("Right sidebar")} ${Translation.tr("Left sidebar")}`

        ConfigSelectionArray {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: false
            currentValue: page.side
            onSelected: newValue => page.side = newValue
            options: [
                { displayName: Translation.tr("Left sidebar"), icon: "left_panel_open", value: "left" },
                { displayName: Translation.tr("Right sidebar"), icon: "right_panel_open", value: "right" }
            ]
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 20

            ColumnLayout {
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 240
                Layout.maximumWidth: 240
                Layout.fillWidth: false
                spacing: 10
                Placement {
                    Layout.preferredWidth: 240
                    width: 240
                    onLeft: page.side === "left"
                    panelWidth: page.side === "left" && Config.options.sidebar.left.extendedByDefault ? Appearance.sizes.sidebarWidthExtended : Appearance.sizes.sidebarWidth
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: page.side === "right"
                        ? Translation.tr("Opens from the right edge: click the bar's right side or Super+N. Click a section on the right to change it, drag it to move it, the eye hides it.")
                        : Translation.tr("Opens from the left edge: click the bar's left side or Super+A. Inside it, Ctrl+O makes it wider, Ctrl+P keeps it open beside windows and Ctrl+D turns it into a window.")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
                // The sections by name, top to bottom, as another way to pick one
                Repeater {
                    model: page.side === "right" ? SidebarLayout.sections : []
                    delegate: RippleButton {
                        id: sectionButton
                        required property var modelData
                        readonly property var info: SidebarCatalog.section(modelData.type)
                        readonly property bool picked: page.selected === modelData.type
                        readonly property bool shown: SidebarLayout.sectionShown(modelData.type)
                        Layout.fillWidth: true
                        implicitHeight: 34
                        buttonRadius: Appearance.rounding.full
                        colBackground: sectionButton.picked ? Appearance.colors.colSecondaryContainer : "transparent"
                        colBackgroundHover: sectionButton.picked ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer1Hover
                        onClicked: page.selected = modelData.type
                        contentItem: RowLayout {
                            spacing: 8
                            MaterialSymbol {
                                Layout.leftMargin: 6
                                text: sectionButton.info?.icon ?? ""
                                iconSize: 18
                                fill: sectionButton.shown ? 1 : 0
                                color: sectionButton.shown ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: sectionButton.info?.name ?? ""
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: sectionButton.shown ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                            }
                            StyledText {
                                visible: !sectionButton.shown
                                Layout.rightMargin: 8
                                text: Translation.tr("hidden")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                        }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 620
                SidebarMockup {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: page.side === "right"
                    width: Math.min(parent.width, implicitWidth)
                    height: 620
                    selected: page.selected
                    onSectionClicked: type => page.selected = type
                }
                LeftSidebarMockup {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: page.side === "left"
                    width: Math.min(parent.width, implicitWidth)
                    height: 620
                    selected: page.leftSelected
                    onTabClicked: id => page.leftSelected = id
                }
            }
        }

        ConfigSlider {
            buttonIcon: "width"
            text: Translation.tr("Width")
            description: page.side === "left" ? Translation.tr("Shared with the right sidebar; Ctrl+O widens the left one") : ""
            usePercentTooltip: false
            from: 340
            to: 640
            value: Config.options.sidebar.width
            valueText: `${Math.round(value)} px`
            onMoved: Config.options.sidebar.width = Math.round(value / 10) * 10
        }
    }

    // ---- Right sidebar: the picked section ----

    ContentSection {
        visible: page.side === "right"
        icon: page.selectedSection?.icon ?? ""
        title: page.selectedSection?.name ?? ""
        description: page.selectedSection?.description ?? ""

        ConfigSwitch {
            visible: !(page.selectedSection?.fixed ?? false)
            buttonIcon: "visibility"
            text: Translation.tr("Show this section")
            autoToggle: false
            checked: SidebarLayout.sectionShown(page.selected)
            onClicked: SidebarLayout.setSectionShown(page.selected, !SidebarLayout.sectionShown(page.selected))
        }

        // Top row
        ConfigSwitch {
            visible: page.selected === "header"
            buttonIcon: "timer"
            text: Translation.tr("Uptime")
            autoToggle: false
            checked: Config.options.sidebar.right.header.showUptime
            onClicked: Config.options.sidebar.right.header.showUptime = !Config.options.sidebar.right.header.showUptime
        }
        ContentSubsection {
            visible: page.selected === "header"
            title: Translation.tr("Buttons")
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: SidebarCatalog.headerButtons
                    delegate: ToggleChip {
                        required property var modelData
                        buttonIcon: modelData.icon
                        text: modelData.name
                        active: Config.options.sidebar.right.header.buttons.includes(modelData.id)
                        onClicked: SidebarLayout.toggleInList("sidebar.right.header.buttons", modelData.id)
                    }
                }
            }
        }

        // Sliders
        ConfigRow {
            visible: page.selected === "sliders"
            uniform: true
            ConfigSwitch {
                enabled: Config.options.sidebar.quickSliders.enable
                buttonIcon: "brightness_6"
                text: Translation.tr("Brightness")
                autoToggle: false
                checked: Config.options.sidebar.quickSliders.showBrightness
                onClicked: Config.options.sidebar.quickSliders.showBrightness = !Config.options.sidebar.quickSliders.showBrightness
            }
            ConfigSwitch {
                enabled: Config.options.sidebar.quickSliders.enable
                buttonIcon: "volume_up"
                text: Translation.tr("Volume")
                autoToggle: false
                checked: Config.options.sidebar.quickSliders.showVolume
                onClicked: Config.options.sidebar.quickSliders.showVolume = !Config.options.sidebar.quickSliders.showVolume
            }
            ConfigSwitch {
                enabled: Config.options.sidebar.quickSliders.enable
                buttonIcon: "mic"
                text: Translation.tr("Microphone")
                autoToggle: false
                checked: Config.options.sidebar.quickSliders.showMic
                onClicked: Config.options.sidebar.quickSliders.showMic = !Config.options.sidebar.quickSliders.showMic
            }
        }

        // Quick toggles
        ContentSubsection {
            visible: page.selected === "toggles"
            title: Translation.tr("Style")
            searchText: `${title} ${Translation.tr("Tiles")} ${Translation.tr("Round buttons")}`
            Flow {
                Layout.fillWidth: true
                spacing: 4
                SchemeTile {
                    id: androidTile
                    label: Translation.tr("Tiles")
                    frameWidth: 112
                    frameHeight: 70
                    selected: Config.options.sidebar.quickToggles.style === "android"
                    onClicked: Config.options.sidebar.quickToggles.style = "android"
                    Grid {
                        anchors.centerIn: parent
                        columns: 3
                        spacing: 4
                        Rectangle { width: 54; height: 16; radius: 8; color: androidTile.ink }
                        Rectangle { width: 25; height: 16; radius: 6; color: androidTile.faint }
                        Rectangle { width: 0; height: 0; visible: false }
                        Rectangle { width: 25; height: 16; radius: 6; color: androidTile.faint }
                        Rectangle { width: 54; height: 16; radius: 8; color: androidTile.faint }
                    }
                }
                SchemeTile {
                    id: classicTile
                    label: Translation.tr("Round buttons")
                    frameWidth: 112
                    frameHeight: 70
                    selected: Config.options.sidebar.quickToggles.style === "classic"
                    onClicked: Config.options.sidebar.quickToggles.style = "classic"
                    Row {
                        anchors.centerIn: parent
                        spacing: 4
                        Repeater {
                            model: 5
                            Rectangle {
                                required property int index
                                width: 16
                                height: 16
                                radius: 8
                                color: index === 0 ? classicTile.ink : classicTile.faint
                            }
                        }
                    }
                }
            }
        }
        ConfigSlider {
            visible: page.selected === "toggles" && Config.options.sidebar.quickToggles.style === "android"
            buttonIcon: "view_column"
            text: Translation.tr("Columns")
            usePercentTooltip: false
            from: 2
            to: 8
            value: Config.options.sidebar.quickToggles.android.columns
            valueText: `${Math.round(value)}`
            onMoved: Config.options.sidebar.quickToggles.android.columns = Math.round(value)
        }
        QuickTogglesEditor {
            visible: page.selected === "toggles"
            Layout.topMargin: 6
            Layout.bottomMargin: 10
        }

        // Notifications
        StyledText {
            visible: page.selected === "notifications"
            Layout.fillWidth: true
            Layout.margins: 12
            wrapMode: Text.Wrap
            text: Translation.tr("Which apps may show banners, and Do Not Disturb, are on the Notifications page.")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }
        ConfigNavRow {
            visible: page.selected === "notifications"
            buttonIcon: "notifications"
            title: Translation.tr("Notifications")
            description: Translation.tr("Per app rules and Do Not Disturb")
            onClicked: ApplicationWindow.window?.openPage("notifications", Translation.tr("Notifications"))
        }

        // Calendar and tools
        ContentSubsection {
            visible: page.selected === "widgets"
            title: Translation.tr("Tabs")
            description: Translation.tr("In this order; switch them with Ctrl+PageUp/PageDown")
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: SidebarCatalog.widgetTabs
                    delegate: ToggleChip {
                        required property var modelData
                        buttonIcon: modelData.icon
                        text: modelData.name
                        active: Config.options.sidebar.right.widgets.tabs.includes(modelData.type)
                        onClicked: SidebarLayout.toggleInList("sidebar.right.widgets.tabs", modelData.type)
                    }
                }
            }
        }
        ConfigSlider {
            visible: page.selected === "widgets"
            enabled: SidebarLayout.sectionShown("notifications")
            buttonIcon: "height"
            text: Translation.tr("Height")
            description: SidebarLayout.sectionShown("notifications") ? "" : Translation.tr("Takes all the free height while the notifications are hidden")
            from: 0.2
            to: 0.7
            value: Config.options.sidebar.right.widgets.height
            valueText: `${Math.round(value * 100)}%`
            onMoved: Config.options.sidebar.right.widgets.height = Math.round(value * 100) / 100
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 8
            Item { Layout.fillWidth: true }
            RippleButton {
                implicitHeight: 34
                leftPadding: 12
                rightPadding: 14
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer3
                colBackgroundHover: Appearance.colors.colLayer3Hover
                onClicked: SidebarLayout.resetSections()
                contentItem: RowLayout {
                    spacing: 6
                    MaterialSymbol {
                        text: "restart_alt"
                        iconSize: 16
                        color: Appearance.colors.colOnLayer3
                    }
                    StyledText {
                        text: Translation.tr("Default order")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer3
                    }
                }
            }
        }
    }

    ContentSection {
        visible: page.side === "right"
        icon: "speed"
        title: Translation.tr("Opening")

        ConfigNavRow {
            buttonIcon: "south_east"
            title: Translation.tr("Hot corners")
            description: Translation.tr("Open sidebars from the corners of the screen")
            onClicked: ApplicationWindow.window?.openPage("desktop", Translation.tr("Hot corners"))
        }
        ConfigExpander {
            ConfigSwitch {
                buttonIcon: "memory"
                text: Translation.tr("Keep the right sidebar loaded")
                description: Translation.tr("Opens faster at the cost of around 15MB of RAM")
                autoToggle: false
                checked: Config.options.sidebar.keepRightSidebarLoaded
                onClicked: Config.options.sidebar.keepRightSidebarLoaded = !Config.options.sidebar.keepRightSidebarLoaded
            }
        }
    }

    // ---- Left sidebar ----

    ContentSection {
        visible: page.side === "left"
        icon: "tab"
        title: Translation.tr("Tabs")
        description: Translation.tr("Use the arrows to change the order")

        Repeater {
            model: {
                const known = SidebarCatalog.leftTabs.map(tab => tab.id);
                const given = (Config.options.sidebar.left.order ?? []).filter(id => known.includes(id));
                return [...given, ...known.filter(id => !given.includes(id))];
            }
            delegate: RowLayout {
                id: tabRow
                required property string modelData
                required property int index
                readonly property var info: SidebarCatalog.leftTabs.find(t => t.id === modelData)
                readonly property bool on: tabRow.modelData === "ai" ? Config.options.policies.ai !== 0
                    : tabRow.modelData === "translator" ? Config.options.sidebar.translator.enable : Config.options.policies.weeb !== 0
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                spacing: 4

                function move(offset) {
                    const list = [...SidebarLayout.listAt("sidebar.left.order")];
                    const order = list.length === 3 ? list : SidebarCatalog.leftTabs.map(t => t.id);
                    SidebarLayout.setList("sidebar.left.order", order);
                    SidebarLayout.moveInList("sidebar.left.order", tabRow.modelData, tabRow.index + offset);
                }

                ColumnLayout {
                    spacing: 0
                    RippleButton {
                        implicitWidth: 26
                        implicitHeight: 20
                        buttonRadius: 6
                        enabled: tabRow.index > 0
                        opacity: enabled ? 1 : 0.3
                        onClicked: tabRow.move(-1)
                        contentItem: MaterialSymbol { horizontalAlignment: Text.AlignHCenter; text: "keyboard_arrow_up"; iconSize: 18; color: Appearance.colors.colOnLayer2 }
                    }
                    RippleButton {
                        implicitWidth: 26
                        implicitHeight: 20
                        buttonRadius: 6
                        enabled: tabRow.index < 2
                        opacity: enabled ? 1 : 0.3
                        onClicked: tabRow.move(1)
                        contentItem: MaterialSymbol { horizontalAlignment: Text.AlignHCenter; text: "keyboard_arrow_down"; iconSize: 18; color: Appearance.colors.colOnLayer2 }
                    }
                }
                ConfigSwitch {
                    Layout.fillWidth: true
                    buttonIcon: tabRow.info?.icon ?? ""
                    text: tabRow.info?.name ?? ""
                    description: tabRow.modelData === "ai" ? Translation.tr("Chat with an assistant; keys and models are on the Search & AI page")
                        : tabRow.modelData === "translator" ? Translation.tr("Translates as you type")
                        : Translation.tr("Wallhaven and booru image browser")
                    autoToggle: false
                    checked: tabRow.on
                    onClicked: {
                        if (tabRow.modelData === "ai") Config.options.policies.ai = tabRow.on ? 0 : 1;
                        else if (tabRow.modelData === "translator") Config.options.sidebar.translator.enable = !tabRow.on;
                        else Config.options.policies.weeb = tabRow.on ? 0 : 1;
                    }
                }
            }
        }
        ContentSubsection {
            title: Translation.tr("Opens on")
            ConfigSelectionArray {
                currentValue: Config.options.sidebar.left.startTab
                onSelected: newValue => Config.options.sidebar.left.startTab = newValue
                options: [
                    { displayName: Translation.tr("Where I left it"), icon: "history", value: "last" },
                    ...SidebarCatalog.leftTabs.map(tab => ({ displayName: tab.name, icon: tab.icon, value: tab.id }))
                ]
            }
        }
        ConfigSwitch {
            buttonIcon: "width_wide"
            text: Translation.tr("Open it wide")
            description: Translation.tr("Ctrl+O switches the width while it's open")
            autoToggle: false
            checked: Config.options.sidebar.left.extendedByDefault
            onClicked: Config.options.sidebar.left.extendedByDefault = !Config.options.sidebar.left.extendedByDefault
        }
    }

    ContentSection {
        visible: page.side === "left"
        icon: "tune"
        title: Translation.tr("Tab settings")

        ConfigNavRow {
            buttonIcon: "neurology"
            title: Translation.tr("Assistant")
            description: Translation.tr("AI features, keys and the system prompt")
            onClicked: ApplicationWindow.window?.openPage("search", Translation.tr("Assistant"))
        }
        ConfigSwitch {
            buttonIcon: "gradient"
            text: Translation.tr("Fade in the assistant's text")
            autoToggle: false
            checked: Config.options.sidebar.ai.textFadeIn
            onClicked: Config.options.sidebar.ai.textFadeIn = !Config.options.sidebar.ai.textFadeIn
        }
        ConfigSlider {
            buttonIcon: "translate"
            text: Translation.tr("Translate after a pause of")
            usePercentTooltip: false
            from: 100
            to: 1500
            value: Config.options.sidebar.translator.delay
            valueText: Translation.tr("%1 ms").arg(Math.round(value))
            onMoved: Config.options.sidebar.translator.delay = Math.round(value / 50) * 50
        }
        ContentSubsection {
            title: Translation.tr("Anime image browser")
            description: Translation.tr("Hidden keeps the page (swipe to it) but removes its tab")
            ConfigSelectionArray {
                currentValue: Config.options.policies.weeb
                onSelected: newValue => Config.options.policies.weeb = newValue
                options: [
                    { displayName: Translation.tr("Off"), icon: "block", value: 0 },
                    { displayName: Translation.tr("On"), icon: "check", value: 1 },
                    { displayName: Translation.tr("Hidden"), icon: "visibility_off", value: 2 }
                ]
            }
        }
        ConfigSpinBox {
            enabled: Config.options.policies.weeb !== 0
            visible: enabled
            icon: "photo_library"
            text: Translation.tr("Images per page")
            value: Config.options.sidebar.booru.limit
            from: 5
            to: 100
            stepSize: 5
            onValueChanged: Config.options.sidebar.booru.limit = value
        }
    }
}
