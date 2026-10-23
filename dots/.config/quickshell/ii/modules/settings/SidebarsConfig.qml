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
 * The sidebars, part by part. Each card below is one part, in the order the sidebar shows them:
 * the arrows move it, the switch shows or hides it, and its own settings are right inside it.
 * The picture at the top follows every change; clicking a part there jumps to its card.
 */
ContentPage {
    id: page
    property string side: "right"
    readonly property var screen: Quickshell.screens[0] ?? null

    function cardFor(type) {
        for (let i = 0; i < rightCards.count; i++) {
            const card = rightCards.itemAt(i);
            if (card?.type === type) return card;
        }
        return null;
    }

    // One part of a sidebar: number, name, what it is, arrows to move it and a switch to show it
    component PartCard: Rectangle {
        id: partCard
        property int number: 1
        property string icon
        property string title
        property string description
        property bool shown: true
        property bool canHide: true
        property bool canMoveUp: true
        property bool canMoveDown: true
        property bool highlighted: false
        signal moveUp()
        signal moveDown()
        signal toggled()
        default property alias body: bodyColumn.data

        readonly property bool settingsSearchable: true
        property string searchText: `${partCard.title} ${partCard.description}`

        Layout.fillWidth: true
        implicitHeight: cardColumn.implicitHeight + 16
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer2
        border.width: partCard.highlighted ? 2 : 0
        border.color: Appearance.colors.colPrimary
        Behavior on implicitHeight {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        ColumnLayout {
            id: cardColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 8
            }
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                spacing: 12

                Item {
                    implicitWidth: 40
                    implicitHeight: 40
                    MaterialShape {
                        anchors.fill: parent
                        shape: MaterialShape.Shape.Cookie7Sided
                        color: partCard.shown ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer3
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: partCard.icon
                        iconSize: 20
                        fill: partCard.shown ? 1 : 0
                        color: partCard.shown ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                    }
                    Rectangle { // Its place from the top
                        anchors {
                            right: parent.right
                            bottom: parent.bottom
                            margins: -4
                        }
                        width: 18
                        height: 18
                        radius: 9
                        color: Appearance.colors.colPrimary
                        StyledText {
                            anchors.centerIn: parent
                            text: partCard.number
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: partCard.title
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Medium
                        color: partCard.shown ? Appearance.colors.colOnLayer2 : Appearance.colors.colSubtext
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: partCard.shown ? partCard.description : Translation.tr("Hidden. Turn the switch on to show it.")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
                ArrowButton {
                    visible: partCard.canMoveUp || partCard.canMoveDown
                    symbol: "arrow_upward"
                    enabled: partCard.canMoveUp
                    tip: Translation.tr("Move up")
                    onClicked: partCard.moveUp()
                }
                ArrowButton {
                    visible: partCard.canMoveUp || partCard.canMoveDown
                    symbol: "arrow_downward"
                    enabled: partCard.canMoveDown
                    tip: Translation.tr("Move down")
                    onClicked: partCard.moveDown()
                }
                StyledSwitch {
                    visible: partCard.canHide
                    Layout.rightMargin: 6
                    checkable: false // Follows the setting; a click asks to change it
                    checked: partCard.shown
                    onClicked: partCard.toggled()
                    StyledToolTip {
                        text: partCard.shown ? Translation.tr("Hide") : Translation.tr("Show")
                    }
                }
            }

            ColumnLayout {
                id: bodyColumn
                Layout.fillWidth: true
                visible: partCard.shown && children.length > 0
                spacing: 2
            }
        }
    }

    component ArrowButton: RippleButton {
        id: arrowButton
        property string symbol
        property string tip
        implicitWidth: 34
        implicitHeight: 34
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colLayer3
        colBackgroundHover: Appearance.colors.colLayer3Hover
        opacity: enabled ? 1 : 0.35
        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            text: arrowButton.symbol
            iconSize: 18
            color: Appearance.colors.colOnLayer3
        }
        StyledToolTip {
            text: arrowButton.tip
        }
    }

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

    // ---- Overview ----

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
                Layout.preferredWidth: 260
                Layout.maximumWidth: 260
                Layout.fillWidth: false
                spacing: 12
                Placement {
                    Layout.preferredWidth: 260
                    width: 260
                    onLeft: page.side === "left"
                    panelWidth: page.side === "left" && Config.options.sidebar.left.extendedByDefault ? Appearance.sizes.sidebarWidthExtended : Appearance.sizes.sidebarWidth
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: page.side === "right"
                        ? Translation.tr("Opens from the right: click the right side of the bar or press Super+N.")
                        : Translation.tr("Opens from the left: click the left side of the bar or press Super+A. Inside it, Ctrl+O makes it wider, Ctrl+P keeps it open next to windows, Ctrl+D turns it into a window.")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: page.side === "right"
                        ? Translation.tr("Drag a part up or down in the picture to move it, the eye hides it. Click a part to jump to its settings below, where the arrows and switches do the same.")
                        : Translation.tr("Every tab is a card below, in the order of the tab bar. Move tabs with the arrows, turn them on or off with the switch.")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 560
                SidebarMockup {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: page.side === "right"
                    width: Math.min(parent.width, implicitWidth)
                    height: 560
                    onSectionClicked: type => page.revealItem(page.cardFor(type))
                }
                LeftSidebarMockup {
                    id: leftMockup
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: page.side === "left"
                    width: Math.min(parent.width, implicitWidth)
                    height: 560
                    onTabClicked: id => leftMockup.selected = id
                }
            }
        }

        ConfigSlider {
            buttonIcon: "width"
            text: Translation.tr("Width")
            description: page.side === "left" ? Translation.tr("The same for both sidebars; the left one can open wider (below)") : Translation.tr("The same for both sidebars")
            usePercentTooltip: false
            from: 340
            to: 640
            value: Config.options.sidebar.width
            valueText: `${Math.round(value)} px`
            onMoved: Config.options.sidebar.width = Math.round(value / 10) * 10
        }
    }

    // ---- Right sidebar: one card per part ----

    ContentSection {
        visible: page.side === "right"
        icon: "right_panel_open"
        title: Translation.tr("Parts of the right sidebar")
        card: false

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 10
            Repeater {
                id: rightCards
                model: SidebarLayout.sections
                delegate: PartCard {
                    id: sectionCard
                    required property var modelData
                    required property int index
                    readonly property string type: modelData.type
                    readonly property var info: SidebarCatalog.section(type)
                    readonly property bool fixed: info?.fixed ?? false
                    number: index + 1
                    icon: info?.icon ?? ""
                    title: info?.name ?? type
                    description: info?.description ?? ""
                    shown: SidebarLayout.sectionShown(type)
                    canHide: !fixed
                    canMoveUp: !fixed && index > 1
                    canMoveDown: !fixed && index < SidebarLayout.sections.length - 1
                    onMoveUp: SidebarLayout.moveSection(type, index - 1)
                    onMoveDown: SidebarLayout.moveSection(type, index + 1)
                    onToggled: SidebarLayout.setSectionShown(type, !shown)

                    Loader {
                        Layout.fillWidth: true
                        active: sectionCard.shown
                        sourceComponent: ({ "header": headerSettings, "sliders": slidersSettings, "toggles": togglesSettings,
                            "notifications": notificationsSettings, "widgets": widgetsSettings })[sectionCard.type] ?? null
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            RippleButton {
                implicitHeight: 34
                leftPadding: 12
                rightPadding: 14
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onClicked: SidebarLayout.resetSections()
                contentItem: RowLayout {
                    spacing: 6
                    MaterialSymbol {
                        text: "restart_alt"
                        iconSize: 16
                        color: Appearance.colors.colOnLayer2
                    }
                    StyledText {
                        text: Translation.tr("Default order")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer2
                    }
                }
            }
        }
    }

    Component {
        id: headerSettings
        ColumnLayout {
            spacing: 4
            ConfigSwitch {
                buttonIcon: "timer"
                text: Translation.tr("Uptime")
                autoToggle: false
                checked: Config.options.sidebar.right.header.showUptime
                onClicked: Config.options.sidebar.right.header.showUptime = !Config.options.sidebar.right.header.showUptime
            }
            Flow {
                Layout.fillWidth: true
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                Layout.bottomMargin: 6
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
    }

    Component {
        id: slidersSettings
        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.bottomMargin: 6
            spacing: 6
            ToggleChip {
                buttonIcon: "brightness_6"
                text: Translation.tr("Brightness")
                active: Config.options.sidebar.quickSliders.showBrightness
                onClicked: Config.options.sidebar.quickSliders.showBrightness = !active
            }
            ToggleChip {
                buttonIcon: "volume_up"
                text: Translation.tr("Volume")
                active: Config.options.sidebar.quickSliders.showVolume
                onClicked: Config.options.sidebar.quickSliders.showVolume = !active
            }
            ToggleChip {
                buttonIcon: "mic"
                text: Translation.tr("Microphone")
                active: Config.options.sidebar.quickSliders.showMic
                onClicked: Config.options.sidebar.quickSliders.showMic = !active
            }
        }
    }

    Component {
        id: togglesSettings
        ColumnLayout {
            spacing: 8
            Flow {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                spacing: 4
                SchemeTile {
                    id: androidTile
                    label: Translation.tr("Tiles")
                    frameWidth: 112
                    frameHeight: 64
                    selected: Config.options.sidebar.quickToggles.style === "android"
                    onClicked: Config.options.sidebar.quickToggles.style = "android"
                    Grid {
                        anchors.centerIn: parent
                        columns: 2
                        spacing: 4
                        Rectangle { width: 54; height: 16; radius: 8; color: androidTile.ink }
                        Rectangle { width: 25; height: 16; radius: 6; color: androidTile.faint }
                        Rectangle { width: 25; height: 16; radius: 6; color: androidTile.faint }
                        Rectangle { width: 54; height: 16; radius: 8; color: androidTile.faint }
                    }
                }
                SchemeTile {
                    id: classicTile
                    label: Translation.tr("Round buttons")
                    frameWidth: 112
                    frameHeight: 64
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
            ConfigSlider {
                visible: Config.options.sidebar.quickToggles.style === "android"
                buttonIcon: "view_column"
                text: Translation.tr("Columns")
                usePercentTooltip: false
                from: 2
                to: 8
                value: Config.options.sidebar.quickToggles.android.columns
                valueText: `${Math.round(value)}`
                onMoved: Config.options.sidebar.quickToggles.android.columns = Math.round(value)
            }
            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                wrapMode: Text.Wrap
                text: Config.options.sidebar.quickToggles.style === "android"
                    ? Translation.tr("Drag a toggle to move it, click it to make it wide or narrow, × removes it. Add more from the list under it.")
                    : Translation.tr("Drag a button to move it, × removes it. Add more from the list under it.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            QuickTogglesEditor {
                Layout.bottomMargin: 8
            }
        }
    }

    Component {
        id: notificationsSettings
        ConfigNavRow {
            buttonIcon: "notifications"
            title: Translation.tr("Which apps may notify")
            description: Translation.tr("Banners, sounds and Do Not Disturb are on the Notifications page")
            onClicked: ApplicationWindow.window?.openPage("notifications", Translation.tr("Notifications"))
        }
    }

    Component {
        id: widgetsSettings
        ColumnLayout {
            spacing: 4
            StyledText {
                Layout.leftMargin: 12
                text: Translation.tr("Tabs")
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer2
            }
            Flow {
                Layout.fillWidth: true
                Layout.leftMargin: 12
                Layout.rightMargin: 12
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
            ConfigSlider {
                visible: SidebarLayout.sectionShown("notifications")
                buttonIcon: "height"
                text: Translation.tr("Height")
                description: Translation.tr("Of the whole sidebar; the notifications take the rest")
                from: 0.2
                to: 0.7
                value: Config.options.sidebar.right.widgets.height
                valueText: `${Math.round(value * 100)}%`
                onMoved: Config.options.sidebar.right.widgets.height = Math.round(value * 100) / 100
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
            description: Translation.tr("Open sidebars by pushing the pointer into a corner of the screen")
            onClicked: ApplicationWindow.window?.openPage("desktop", Translation.tr("Hot corners"))
        }
        ConfigSwitch {
            buttonIcon: "memory"
            text: Translation.tr("Open it instantly")
            description: Translation.tr("Keeps the right sidebar ready in memory (about 15 MB)")
            autoToggle: false
            checked: Config.options.sidebar.keepRightSidebarLoaded
            onClicked: Config.options.sidebar.keepRightSidebarLoaded = !Config.options.sidebar.keepRightSidebarLoaded
        }
    }

    // ---- Left sidebar: one card per tab ----

    ContentSection {
        visible: page.side === "left"
        icon: "left_panel_open"
        title: Translation.tr("Tabs of the left sidebar")
        card: false

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 10
            Repeater {
                model: {
                    const known = SidebarCatalog.leftTabs.map(tab => tab.id);
                    const given = (Config.options.sidebar.left.order ?? []).filter(id => known.includes(id));
                    return [...given, ...known.filter(id => !given.includes(id))];
                }
                delegate: PartCard {
                    id: tabCard
                    required property string modelData
                    required property int index
                    readonly property var info: SidebarCatalog.leftTabs.find(t => t.id === modelData)
                    number: index + 1
                    icon: info?.icon ?? ""
                    title: info?.name ?? modelData
                    description: modelData === "ai" ? Translation.tr("Chat with an assistant about anything on your screen")
                        : modelData === "translator" ? Translation.tr("Translates as you type")
                        : Translation.tr("Wallhaven and booru image browser")
                    highlighted: leftMockup.selected === modelData
                    shown: modelData === "ai" ? Config.options.policies.ai !== 0
                        : modelData === "translator" ? Config.options.sidebar.translator.enable : Config.options.policies.weeb !== 0
                    canMoveUp: index > 0
                    canMoveDown: index < SidebarCatalog.leftTabs.length - 1

                    function move(offset) {
                        const order = [...SidebarLayout.listAt("sidebar.left.order")];
                        SidebarLayout.setList("sidebar.left.order", order.length === SidebarCatalog.leftTabs.length ? order : SidebarCatalog.leftTabs.map(t => t.id));
                        SidebarLayout.moveInList("sidebar.left.order", tabCard.modelData, tabCard.index + offset);
                    }
                    onMoveUp: tabCard.move(-1)
                    onMoveDown: tabCard.move(1)
                    onToggled: {
                        if (modelData === "ai") Config.options.policies.ai = shown ? 0 : 1;
                        else if (modelData === "translator") Config.options.sidebar.translator.enable = !shown;
                        else Config.options.policies.weeb = shown ? 0 : 1;
                    }

                    Loader {
                        Layout.fillWidth: true
                        active: tabCard.shown
                        sourceComponent: ({ "ai": aiSettings, "translator": translatorSettings, "anime": animeSettings })[tabCard.modelData] ?? null
                    }
                }
            }
        }
    }

    Component {
        id: aiSettings
        ColumnLayout {
            spacing: 2
            ConfigSwitch {
                buttonIcon: "gradient"
                text: Translation.tr("Fade in the answers")
                autoToggle: false
                checked: Config.options.sidebar.ai.textFadeIn
                onClicked: Config.options.sidebar.ai.textFadeIn = !Config.options.sidebar.ai.textFadeIn
            }
            ConfigNavRow {
                buttonIcon: "neurology"
                title: Translation.tr("Models, keys and the system prompt")
                description: Translation.tr("On the Search & AI page")
                onClicked: ApplicationWindow.window?.openPage("search", Translation.tr("Assistant"))
            }
        }
    }

    Component {
        id: translatorSettings
        ConfigSlider {
            buttonIcon: "hourglass_empty"
            text: Translation.tr("Translate after a pause of")
            usePercentTooltip: false
            from: 100
            to: 1500
            value: Config.options.sidebar.translator.delay
            valueText: Translation.tr("%1 ms").arg(Math.round(value))
            onMoved: Config.options.sidebar.translator.delay = Math.round(value / 50) * 50
        }
    }

    Component {
        id: animeSettings
        ColumnLayout {
            spacing: 2
            ConfigSwitch {
                buttonIcon: "visibility_off"
                text: Translation.tr("No tab, swipe to it")
                description: Translation.tr("Keeps the browser but leaves it out of the tab bar")
                autoToggle: false
                checked: Config.options.policies.weeb === 2
                onClicked: Config.options.policies.weeb = Config.options.policies.weeb === 2 ? 1 : 2
            }
            ConfigSpinBox {
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

    ContentSection {
        visible: page.side === "left"
        icon: "tune"
        title: Translation.tr("Opening")

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
        ConfigNavRow {
            buttonIcon: "south_west"
            title: Translation.tr("Hot corners")
            description: Translation.tr("Open sidebars by pushing the pointer into a corner of the screen")
            onClicked: ApplicationWindow.window?.openPage("desktop", Translation.tr("Hot corners"))
        }
    }
}
