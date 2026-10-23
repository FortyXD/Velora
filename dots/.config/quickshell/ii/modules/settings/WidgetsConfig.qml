import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.settings.preview

/**
 * Desktop widgets: a card for each one to switch it on, and below them the settings of the card
 * you clicked. Only one widget's settings show at a time; search still finds the others and opens them.
 */
ContentPage {
    id: root

    readonly property var widgetsConfig: Config.options.background.widgets
    readonly property var widgetEntries: [
        { key: "clock", icon: "nest_clock_farsight_analog", shape: MaterialShape.Shape.Cookie12Sided, name: Translation.tr("Clock"), description: Translation.tr("Analog cookie or big digital clock") },
        { key: "weather", icon: "partly_cloudy_day", shape: MaterialShape.Shape.Pill, name: Translation.tr("Weather"), description: Translation.tr("Current temperature and conditions") },
        { key: "systemMonitor", icon: "monitor_heart", shape: MaterialShape.Shape.Cookie7Sided, name: Translation.tr("System monitor"), description: Translation.tr("CPU, memory, temperature, disk and network") },
        { key: "media", icon: "music_note", shape: MaterialShape.Shape.Circle, name: Translation.tr("Media"), description: Translation.tr("Cover art and controls of what's playing") },
        { key: "calendar", icon: "calendar_month", shape: MaterialShape.Shape.Square, name: Translation.tr("Calendar"), description: Translation.tr("This month at a glance") },
        { key: "countdown", icon: "hourglass_top", shape: MaterialShape.Shape.Gem, name: Translation.tr("Countdown"), description: Translation.tr("Days left until a date you care about") },
        { key: "note", icon: "sticky_note_2", shape: MaterialShape.Shape.Slanted, name: Translation.tr("Note"), description: Translation.tr("A sticky note you can edit on the desktop") },
        { key: "pomodoro", icon: "timer", shape: MaterialShape.Shape.Sunny, name: Translation.tr("Pomodoro"), description: Translation.tr("Focus timer with breaks") }
    ]
    property string selectedKey: "clock" // Whose settings show under the cards

    function entryFor(key) {
        return root.widgetEntries.find(entry => entry.key === key);
    }

    function toggleWidget(key) {
        root.widgetsConfig[key].enable = !root.widgetsConfig[key].enable;
    }

    function selectWidget(key) {
        root.selectedKey = key;
        scrollToDetailsTimer.restart();
    }

    function dateString(date) {
        const pad = n => n.toString().padStart(2, "0");
        return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
    }

    Timer { // Brings the settings into view when they open below the visible part of the page
        id: scrollToDetailsTimer
        interval: 50
        onTriggered: {
            const top = detailsHost.mapToItem(root.contentItem, 0, 0).y;
            if (top > root.contentY + root.height - 160) root.revealItem(detailsHost, false);
        }
    }

    component WidgetTile: RippleButton {
        id: tile
        required property var modelData
        readonly property bool active: root.widgetsConfig[modelData.key].enable
        readonly property bool selected: root.selectedKey === modelData.key
        readonly property bool settingsSearchable: true
        property string searchText: `${modelData.name} ${modelData.description}`
        text: modelData.name

        Layout.fillWidth: true
        Layout.fillHeight: true
        implicitWidth: 140 // Long descriptions must not widen the grid
        implicitHeight: 156
        padding: 14
        buttonRadius: Appearance.rounding.large
        colBackground: tile.active ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer3
        colBackgroundHover: tile.active ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer3Hover
        colRipple: tile.active ? Appearance.colors.colPrimaryContainerActive : Appearance.colors.colLayer3Active
        onClicked: root.selectWidget(modelData.key)

        Rectangle { // Marks whose settings are open below
            anchors.fill: parent
            radius: Appearance.rounding.large
            color: "transparent"
            border.width: tile.selected ? 2 : 0
            border.color: Appearance.colors.colPrimary
        }

        contentItem: ColumnLayout {
            spacing: 4
            RowLayout {
                Layout.fillWidth: true
                Item {
                    implicitWidth: 48
                    implicitHeight: 48
                    MaterialShape {
                        anchors.fill: parent
                        shape: tile.modelData.shape
                        color: tile.active ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                        rotation: tile.hovered ? 30 : 0
                        Behavior on rotation {
                            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                        }
                        Behavior on color {
                            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                        }
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: tile.modelData.icon
                        iconSize: 24
                        fill: 1
                        color: tile.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                    }
                }
                Item { Layout.fillWidth: true }
                StyledSwitch {
                    Layout.alignment: Qt.AlignTop
                    checkable: false
                    checked: tile.active
                    onClicked: root.toggleWidget(tile.modelData.key)
                    StyledToolTip {
                        text: tile.active ? Translation.tr("Hide from the desktop") : Translation.tr("Show on the desktop")
                    }
                }
            }
            Item { Layout.fillHeight: true }
            StyledText {
                Layout.fillWidth: true
                text: tile.modelData.name
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Medium
                color: tile.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer3
            }
            StyledText {
                Layout.fillWidth: true
                text: tile.modelData.description
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: tile.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                opacity: tile.active ? 0.85 : 1
            }
        }
    }

    // The settings of one widget. All of them are built, but only the selected one takes space;
    // the others are only clipped, so search finds their options and selecting one opens it.
    component WidgetDetails: Item {
        id: details
        required property string widgetKey
        property string description: ""
        default property alias contentData: detailSection.contentData
        readonly property var entry: root.entryFor(details.widgetKey)
        readonly property bool shown: root.selectedKey === details.widgetKey

        function settingsReveal() {
            if (details.shown) return false;
            root.selectedKey = details.widgetKey;
            return true;
        }

        Layout.fillWidth: true
        // Set for the layout too: with an implicit height of 0 it keeps the item's last height
        implicitHeight: details.shown ? detailSection.implicitHeight : 0
        Layout.preferredHeight: details.implicitHeight
        clip: true
        enabled: details.shown
        opacity: details.shown ? 1 : 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        ContentSection {
            id: detailSection
            width: details.width
            icon: details.entry.icon
            title: details.entry.name
            description: details.description

            ConfigSwitch {
                buttonIcon: details.entry.icon
                text: Translation.tr("Show on desktop")
                description: details.entry.description
                autoToggle: false
                checked: root.widgetsConfig[details.widgetKey].enable
                onClicked: root.toggleWidget(details.widgetKey)
            }
            ContentSubsection {
                title: Translation.tr("Position")
                description: Translation.tr("Drag a free widget anywhere on the desktop; it stays there. The other two find the emptiest or busiest part of the wallpaper.")
                ConfigSelectionArray {
                    currentValue: root.widgetsConfig[details.widgetKey].placementStrategy
                    onSelected: newValue => root.widgetsConfig[details.widgetKey].placementStrategy = newValue
                    options: [
                        { displayName: Translation.tr("Free"), icon: "drag_pan", value: "free" },
                        { displayName: Translation.tr("Emptiest spot"), icon: "category", value: "leastBusy" },
                        { displayName: Translation.tr("Busiest spot"), icon: "shapes", value: "mostBusy" }
                    ]
                }
            }
        }
    }

    // On/off option shown as a chip, for a set of things to show
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
        colRipple: chip.active ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colLayer3Active

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

    component ClockStyleTile: SchemeTile {
        id: clockTile
        required property string styleValue
        property string current
        label: clockTile.styleValue === "digital" ? Translation.tr("Digital") : Translation.tr("Cookie")
        selected: clockTile.current === clockTile.styleValue
        frameWidth: 76
        frameHeight: 50

        StyledText {
            visible: clockTile.styleValue === "digital"
            anchors.centerIn: parent
            text: "12:30"
            font.pixelSize: 17
            font.weight: Font.DemiBold
            color: clockTile.ink
        }
        Item {
            visible: clockTile.styleValue === "cookie"
            anchors.centerIn: parent
            width: 40
            height: 40
            MaterialShape {
                anchors.fill: parent
                shape: MaterialShape.Shape.Cookie9Sided
                color: clockTile.faint
            }
            Rectangle { // Hour hand
                x: parent.width / 2 - 2
                y: parent.height / 2 - 10
                width: 4
                height: 12
                radius: 2
                color: clockTile.ink
            }
            Rectangle { // Minute hand
                x: parent.width / 2 - 1.5
                y: parent.height / 2 - 1.5
                width: 15
                height: 3
                radius: 1.5
                color: clockTile.ink
            }
        }
    }

    // A card in each style, as the shared look of most widgets
    component CardStyleTile: SchemeTile {
        id: cardTile
        required property string styleValue
        selected: root.widgetsConfig.cardStyle === cardTile.styleValue
        onClicked: Config.options.background.widgets.cardStyle = cardTile.styleValue
        Rectangle {
            anchors.centerIn: parent
            width: 58
            height: 40
            radius: 8
            color: cardTile.styleValue === "tonal" ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.6)
                : cardTile.styleValue === "surface" ? ColorUtils.transparentize(cardTile.ink, 0.75) : "transparent"
            border.width: cardTile.styleValue === "transparent" ? 1 : 0
            border.color: cardTile.faint
            Rectangle { x: 8; y: 9; width: 24; height: 6; radius: 3; color: cardTile.ink }
            Rectangle { x: 8; y: 21; width: 40; height: 4; radius: 2; color: cardTile.faint }
            Rectangle { x: 8; y: 29; width: 30; height: 4; radius: 2; color: cardTile.faint }
        }
    }

    ContentSection {
        icon: "dashboard_customize"
        title: Translation.tr("Desktop widgets")
        description: Translation.tr("Turn widgets on with their switch and click a card to set it up. Free widgets can be dragged right on the desktop.")

        GridLayout {
            Layout.fillWidth: true
            Layout.margins: 6
            columns: width >= 700 ? 4 : width >= 470 ? 3 : 2
            columnSpacing: 6
            rowSpacing: 6
            uniformCellWidths: true
            uniformCellHeights: true

            Repeater {
                model: root.widgetEntries
                delegate: WidgetTile {}
            }
        }
    }

    ColumnLayout { // Settings of the selected widget
        id: detailsHost
        Layout.fillWidth: true
        spacing: 0

        WidgetDetails {
            id: clockDetails
            widgetKey: "clock"
            description: Translation.tr("The clock on your wallpaper and lock screen")

            function stylePresent(styleName) {
                const clock = root.widgetsConfig.clock;
                return (!clock.showOnlyWhenLocked && clock.style === styleName) || clock.styleLocked === styleName;
            }
            readonly property bool digitalPresent: stylePresent("digital")
            readonly property bool cookiePresent: stylePresent("cookie")

            ConfigSwitch {
                buttonIcon: "lock_clock"
                text: Translation.tr("Only on the lock screen")
                autoToggle: false
                checked: root.widgetsConfig.clock.showOnlyWhenLocked
                onClicked: Config.options.background.widgets.clock.showOnlyWhenLocked = !root.widgetsConfig.clock.showOnlyWhenLocked
            }
            ConfigRow {
                ContentSubsection {
                    visible: !root.widgetsConfig.clock.showOnlyWhenLocked
                    title: Translation.tr("Style on the desktop")
                    Flow {
                        Layout.fillWidth: true
                        spacing: 4
                        Repeater {
                            model: ["digital", "cookie"]
                            delegate: ClockStyleTile {
                                required property string modelData
                                styleValue: modelData
                                current: root.widgetsConfig.clock.style
                                onClicked: Config.options.background.widgets.clock.style = modelData
                            }
                        }
                    }
                }
                ContentSubsection {
                    title: Translation.tr("Style on the lock screen")
                    Flow {
                        Layout.fillWidth: true
                        spacing: 4
                        Repeater {
                            model: ["digital", "cookie"]
                            delegate: ClockStyleTile {
                                required property string modelData
                                styleValue: modelData
                                current: root.widgetsConfig.clock.styleLocked
                                onClicked: Config.options.background.widgets.clock.styleLocked = modelData
                            }
                        }
                    }
                }
            }
            ConfigSwitch {
                buttonIcon: "format_quote"
                text: Translation.tr("Show a quote under the clock")
                autoToggle: false
                checked: root.widgetsConfig.clock.quote.enable
                onClicked: Config.options.background.widgets.clock.quote.enable = !root.widgetsConfig.clock.quote.enable
            }
            ConfigTextRow {
                visible: root.widgetsConfig.clock.quote.enable
                placeholderText: Translation.tr("Quote")
                value: root.widgetsConfig.clock.quote.text
                onValueChanged: Config.options.background.widgets.clock.quote.text = value
            }

            ConfigExpander {
                visible: clockDetails.digitalPresent
                buttonIcon: "timer_10"
                title: Translation.tr("Digital clock look")
                description: Translation.tr("Font, size, date and layout")

                ConfigRow {
                    uniform: true
                    ConfigSwitch {
                        buttonIcon: "vertical_distribute"
                        text: Translation.tr("Vertical")
                        checked: Config.options.background.widgets.clock.digital.vertical
                        onCheckedChanged: Config.options.background.widgets.clock.digital.vertical = checked
                    }
                    ConfigSwitch {
                        buttonIcon: "animation"
                        text: Translation.tr("Animate time change")
                        checked: Config.options.background.widgets.clock.digital.animateChange
                        onCheckedChanged: Config.options.background.widgets.clock.digital.animateChange = checked
                    }
                }
                ConfigRow {
                    uniform: true
                    ConfigSwitch {
                        buttonIcon: "date_range"
                        text: Translation.tr("Show date")
                        checked: Config.options.background.widgets.clock.digital.showDate
                        onCheckedChanged: Config.options.background.widgets.clock.digital.showDate = checked
                    }
                    ConfigSwitch {
                        buttonIcon: "activity_zone"
                        text: Translation.tr("Use adaptive alignment")
                        description: Translation.tr("Aligns the date and quote to left, center or right depending on its position on the screen.")
                        checked: Config.options.background.widgets.clock.digital.adaptiveAlignment
                        onCheckedChanged: Config.options.background.widgets.clock.digital.adaptiveAlignment = checked
                    }
                }
                ConfigFontRow {
                    icon: "font_download"
                    text: Translation.tr("Font family")
                    description: Translation.tr("Width and roundness only work with some fonts, like Google Sans Flex")
                    value: Config.options.background.widgets.clock.digital.font.family
                    onPicked: family => Config.options.background.widgets.clock.digital.font.family = family
                }
                ConfigSlider {
                    text: Translation.tr("Font weight")
                    value: Config.options.background.widgets.clock.digital.font.weight
                    usePercentTooltip: false
                    buttonIcon: "format_bold"
                    from: 1
                    to: 1000
                    stopIndicatorValues: [350]
                    onValueChanged: Config.options.background.widgets.clock.digital.font.weight = value
                }
                ConfigSlider {
                    text: Translation.tr("Font size")
                    value: Config.options.background.widgets.clock.digital.font.size
                    usePercentTooltip: false
                    buttonIcon: "format_size"
                    from: 50
                    to: 700
                    stopIndicatorValues: [90]
                    onValueChanged: Config.options.background.widgets.clock.digital.font.size = value
                }
                ConfigSlider {
                    text: Translation.tr("Font width")
                    value: Config.options.background.widgets.clock.digital.font.width
                    usePercentTooltip: false
                    buttonIcon: "fit_width"
                    from: 25
                    to: 125
                    stopIndicatorValues: [100]
                    onValueChanged: Config.options.background.widgets.clock.digital.font.width = value
                }
                ConfigSlider {
                    text: Translation.tr("Font roundness")
                    value: Config.options.background.widgets.clock.digital.font.roundness
                    usePercentTooltip: false
                    buttonIcon: "line_curve"
                    from: 0
                    to: 100
                    onValueChanged: Config.options.background.widgets.clock.digital.font.roundness = value
                }
            }

            ConfigExpander {
                visible: clockDetails.cookiePresent
                buttonIcon: "cookie"
                title: Translation.tr("Cookie clock look")
                description: Translation.tr("Dial, hands, date and shape")

                ContentSubsection {
                    title: Translation.tr("Dial style")
                    ConfigSelectionArray {
                        currentValue: Config.options.background.widgets.clock.cookie.dialNumberStyle
                        onSelected: newValue => {
                            Config.options.background.widgets.clock.cookie.dialNumberStyle = newValue;
                            if (newValue !== "dots" && newValue !== "full") {
                                Config.options.background.widgets.clock.cookie.hourMarks = false;
                            }
                            if (newValue === "numbers") {
                                Config.options.background.widgets.clock.cookie.timeIndicators = false;
                            }
                        }
                        options: [
                            { displayName: "", icon: "block", value: "none" },
                            { displayName: Translation.tr("Dots"), icon: "graph_6", value: "dots" },
                            { displayName: Translation.tr("Full"), icon: "history_toggle_off", value: "full" },
                            { displayName: Translation.tr("Numbers"), icon: "counter_1", value: "numbers" }
                        ]
                    }
                }
                ConfigRow {
                    ContentSubsection {
                        title: Translation.tr("Hour hand")
                        ConfigSelectionArray {
                            currentValue: Config.options.background.widgets.clock.cookie.hourHandStyle
                            onSelected: newValue => Config.options.background.widgets.clock.cookie.hourHandStyle = newValue
                            options: [
                                { displayName: "", icon: "block", value: "hide" },
                                { displayName: Translation.tr("Classic"), icon: "radio", value: "classic" },
                                { displayName: Translation.tr("Hollow"), icon: "circle", value: "hollow" },
                                { displayName: Translation.tr("Fill"), icon: "eraser_size_5", value: "fill" }
                            ]
                        }
                    }
                    ContentSubsection {
                        title: Translation.tr("Second hand")
                        ConfigSelectionArray {
                            currentValue: Config.options.background.widgets.clock.cookie.secondHandStyle
                            onSelected: newValue => Config.options.background.widgets.clock.cookie.secondHandStyle = newValue
                            options: [
                                { displayName: "", icon: "block", value: "hide" },
                                { displayName: Translation.tr("Classic"), icon: "radio", value: "classic" },
                                { displayName: Translation.tr("Line"), icon: "line_end", value: "line" },
                                { displayName: Translation.tr("Dot"), icon: "adjust", value: "dot" }
                            ]
                        }
                    }
                }
                ContentSubsection {
                    title: Translation.tr("Minute hand")
                    ConfigSelectionArray {
                        currentValue: Config.options.background.widgets.clock.cookie.minuteHandStyle
                        onSelected: newValue => Config.options.background.widgets.clock.cookie.minuteHandStyle = newValue
                        options: [
                            { displayName: "", icon: "block", value: "hide" },
                            { displayName: Translation.tr("Classic"), icon: "radio", value: "classic" },
                            { displayName: Translation.tr("Thin"), icon: "line_end", value: "thin" },
                            { displayName: Translation.tr("Medium"), icon: "eraser_size_2", value: "medium" },
                            { displayName: Translation.tr("Bold"), icon: "eraser_size_4", value: "bold" }
                        ]
                    }
                }
                ContentSubsection {
                    title: Translation.tr("Date style")
                    ConfigSelectionArray {
                        currentValue: Config.options.background.widgets.clock.cookie.dateStyle
                        onSelected: newValue => Config.options.background.widgets.clock.cookie.dateStyle = newValue
                        options: [
                            { displayName: "", icon: "block", value: "hide" },
                            { displayName: Translation.tr("Bubble"), icon: "bubble_chart", value: "bubble" },
                            { displayName: Translation.tr("Border"), icon: "rotate_right", value: "border" },
                            { displayName: Translation.tr("Rect"), icon: "rectangle", value: "rect" }
                        ]
                    }
                }
                ConfigSpinBox {
                    icon: "add_triangle"
                    text: Translation.tr("Sides")
                    value: Config.options.background.widgets.clock.cookie.sides
                    from: 0
                    to: 40
                    stepSize: 1
                    onValueChanged: Config.options.background.widgets.clock.cookie.sides = value
                }
                ConfigRow {
                    uniform: true
                    ConfigSwitch {
                        enabled: Config.options.background.widgets.clock.cookie.dialNumberStyle === "dots" || Config.options.background.widgets.clock.cookie.dialNumberStyle === "full"
                        buttonIcon: "brightness_7"
                        text: Translation.tr("Hour marks")
                        description: Translation.tr("Only with the 'Dots' or 'Full' dial style")
                        checked: Config.options.background.widgets.clock.cookie.hourMarks
                        onEnabledChanged: checked = Config.options.background.widgets.clock.cookie.hourMarks
                        onCheckedChanged: Config.options.background.widgets.clock.cookie.hourMarks = checked
                    }
                    ConfigSwitch {
                        enabled: Config.options.background.widgets.clock.cookie.dialNumberStyle !== "numbers"
                        buttonIcon: "timer_10"
                        text: Translation.tr("Digits in the middle")
                        description: Translation.tr("Not available with the 'Numbers' dial style")
                        checked: Config.options.background.widgets.clock.cookie.timeIndicators
                        onEnabledChanged: checked = Config.options.background.widgets.clock.cookie.timeIndicators
                        onCheckedChanged: Config.options.background.widgets.clock.cookie.timeIndicators = checked
                    }
                }
                ConfigSwitch {
                    buttonIcon: "autoplay"
                    text: Translation.tr("Constantly rotate")
                    description: Translation.tr("Makes the clock always rotate. This is extremely expensive (expect 50% usage on Intel UHD Graphics) and thus impractical.")
                    checked: Config.options.background.widgets.clock.cookie.constantlyRotate
                    onCheckedChanged: Config.options.background.widgets.clock.cookie.constantlyRotate = checked
                }
                ConfigSwitch {
                    buttonIcon: "airwave"
                    text: Translation.tr("Use old sine wave cookie implementation")
                    description: Translation.tr("Looks a bit softer and more consistent with different number of sides, but has less impressive morphing")
                    checked: Config.options.background.widgets.clock.cookie.useSineCookie
                    onCheckedChanged: Config.options.background.widgets.clock.cookie.useSineCookie = checked
                }
                ConfigSwitch {
                    buttonIcon: "wand_stars"
                    text: Translation.tr("Auto styling with Gemini")
                    description: Translation.tr("Uses Gemini to categorize the wallpaper then picks a preset based on it. You'll need to set Gemini API key on the left sidebar first. Images are downscaled for performance, but just to be safe, do not select wallpapers with sensitive information.")
                    checked: Config.options.background.widgets.clock.cookie.aiStyling
                    onCheckedChanged: Config.options.background.widgets.clock.cookie.aiStyling = checked
                }
            }
        }

        WidgetDetails {
            widgetKey: "weather"
            description: Translation.tr("Shared with the weather in the bar and on the lock screen.")

            WeatherStatusCard {}

            ContentSubsection {
                title: Translation.tr("Look")
                searchText: `${title} ${Translation.tr("Pill")} ${Translation.tr("Card with the next hours")}`
                Flow {
                    Layout.fillWidth: true
                    spacing: 4
                    SchemeTile {
                        id: pillTile
                        label: Translation.tr("Pill")
                        frameWidth: 112
                        frameHeight: 70
                        selected: root.widgetsConfig.weather.style !== "card"
                        onClicked: root.widgetsConfig.weather.style = "pill"
                        MaterialShape {
                            anchors.centerIn: parent
                            implicitSize: 54
                            shape: MaterialShape.Shape.Pill
                            color: pillTile.faint
                            StyledText { x: 22; y: 6; text: "10°"; font.pixelSize: 15; font.weight: Font.DemiBold; color: pillTile.ink }
                            MaterialSymbol { x: 6; y: 26; text: "partly_cloudy_day"; iconSize: 20; fill: 1; color: pillTile.ink }
                        }
                    }
                    SchemeTile {
                        id: cardTileWeather
                        label: Translation.tr("Card with the next hours")
                        frameWidth: 112
                        frameHeight: 70
                        selected: root.widgetsConfig.weather.style === "card"
                        onClicked: root.widgetsConfig.weather.style = "card"
                        Rectangle {
                            anchors.centerIn: parent
                            width: 92
                            height: 54
                            radius: 10
                            color: cardTileWeather.faint
                            MaterialSymbol { x: 8; y: 6; text: "partly_cloudy_day"; iconSize: 20; fill: 1; color: cardTileWeather.ink }
                            StyledText { x: 32; y: 5; text: "10°"; font.pixelSize: 16; font.weight: Font.DemiBold; color: cardTileWeather.ink }
                            Row {
                                x: 8
                                y: 34
                                spacing: 6
                                Repeater {
                                    model: 5
                                    Rectangle { width: 10; height: 12; radius: 3; color: cardTileWeather.ink; opacity: 0.6 }
                                }
                            }
                        }
                    }
                }
            }

            ContentSubsection {
                title: Translation.tr("Where")
                searchText: `${title} ${Translation.tr("Automatically")} ${Translation.tr("My city")} GPS`
                Flow {
                    Layout.fillWidth: true
                    spacing: 4
                    SchemeTile {
                        id: autoPlaceTile
                        label: Translation.tr("Automatically")
                        frameWidth: 112
                        frameHeight: 70
                        selected: Config.options.bar.weather.enableGPS
                        onClicked: Config.options.bar.weather.enableGPS = true
                        MaterialSymbol { anchors.centerIn: parent; text: "my_location"; iconSize: 34; color: autoPlaceTile.ink }
                    }
                    SchemeTile {
                        id: cityPlaceTile
                        label: Translation.tr("My city")
                        frameWidth: 112
                        frameHeight: 70
                        selected: !Config.options.bar.weather.enableGPS
                        onClicked: Config.options.bar.weather.enableGPS = false
                        MaterialSymbol { anchors.centerIn: parent; text: "location_city"; iconSize: 34; color: cityPlaceTile.ink }
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    wrapMode: Text.Wrap
                    text: Config.options.bar.weather.enableGPS
                        ? Translation.tr("Uses GPS (GeoClue). When it finds nothing: the last place it found, then the city below, then a guess from your IP address.")
                        : Translation.tr("Always the city below.")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
            ConfigTextRow {
                icon: "location_city"
                label: Translation.tr("City")
                description: {
                    const geocoded = Weather.geocoded;
                    const city = Config.options.bar.weather.city.trim();
                    if (city.length > 0 && geocoded?.query === city) return Translation.tr("Found: %1").arg(geocoded.name);
                    return Config.options.bar.weather.enableGPS ? Translation.tr("Optional, used when the place can't be found") : Translation.tr("The weather is shown for this city");
                }
                inline: true
                wrapMode: TextEdit.NoWrap
                placeholderText: Translation.tr("e.g. Moscow")
                value: Config.options.bar.weather.city
                onValueChanged: Config.options.bar.weather.city = value
            }
            ContentSubsection {
                title: Translation.tr("Units")
                ConfigSelectionArray {
                    currentValue: Config.options.bar.weather.useUSCS
                    onSelected: newValue => Config.options.bar.weather.useUSCS = newValue
                    options: [
                        { displayName: Translation.tr("Celsius, km/h"), icon: "thermometer", value: false },
                        { displayName: Translation.tr("Fahrenheit, mph"), icon: "thermometer", value: true }
                    ]
                }
            }
            ConfigSwitch {
                buttonIcon: "toast"
                text: Translation.tr("Also show in the bar")
                description: Translation.tr("Hover it for the forecast, right-click to refresh")
                autoToggle: false
                checked: Config.options.bar.weather.enable
                onClicked: Config.options.bar.weather.enable = !Config.options.bar.weather.enable
            }
            ConfigExpander {
                ConfigSpinBox {
                    icon: "av_timer"
                    text: Translation.tr("Refresh every (minutes)")
                    value: Config.options.bar.weather.fetchInterval
                    from: 5
                    to: 60
                    stepSize: 5
                    onValueChanged: Config.options.bar.weather.fetchInterval = value
                }
            }
        }

        WidgetDetails {
            widgetKey: "systemMonitor"
            description: Translation.tr("Live usage of your hardware. Readings refresh at the resource polling interval.")

            ContentSubsection {
                title: Translation.tr("What to show")
                Flow {
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    Layout.bottomMargin: 8
                    spacing: 6
                    Repeater {
                        model: [
                            { key: "showCpu", icon: "memory", name: Translation.tr("CPU") },
                            { key: "showMemory", icon: "memory_alt", name: Translation.tr("Memory") },
                            { key: "showSwap", icon: "swap_horiz", name: Translation.tr("Swap") },
                            { key: "showTemperature", icon: "thermostat", name: Translation.tr("CPU temperature") },
                            { key: "showDisk", icon: "hard_drive", name: Translation.tr("Disk usage") },
                            { key: "showNetwork", icon: "network_check", name: Translation.tr("Network speed") },
                            { key: "showGraphs", icon: "monitoring", name: Translation.tr("History graphs") }
                        ]
                        delegate: ToggleChip {
                            required property var modelData
                            buttonIcon: modelData.icon
                            text: modelData.name
                            active: root.widgetsConfig.systemMonitor[modelData.key]
                            onClicked: Config.options.background.widgets.systemMonitor[modelData.key] = !active
                        }
                    }
                }
            }
        }

        WidgetDetails {
            widgetKey: "media"
            description: Translation.tr("Controls the active player, like the media popup of the bar")

            ConfigSwitch {
                buttonIcon: "visibility_off"
                text: Translation.tr("Hide when nothing is playing")
                autoToggle: false
                checked: root.widgetsConfig.media.hideWhenIdle
                onClicked: Config.options.background.widgets.media.hideWhenIdle = !root.widgetsConfig.media.hideWhenIdle
            }
        }

        WidgetDetails {
            widgetKey: "calendar"
            description: Translation.tr("Scroll over the widget to change the month, click the title to come back")

            ConfigSwitch {
                buttonIcon: "weekend"
                text: Translation.tr("Highlight weekends")
                autoToggle: false
                checked: root.widgetsConfig.calendar.highlightWeekends
                onClicked: Config.options.background.widgets.calendar.highlightWeekends = !root.widgetsConfig.calendar.highlightWeekends
            }
        }

        WidgetDetails {
            widgetKey: "countdown"
            description: Translation.tr("Counts the days to a birthday, a trip or a deadline")

            ConfigTextRow {
                icon: "label"
                label: Translation.tr("Title")
                inline: true
                wrapMode: TextEdit.NoWrap
                placeholderText: Translation.tr("e.g. Vacation")
                value: root.widgetsConfig.countdown.title
                onValueChanged: Config.options.background.widgets.countdown.title = value
            }
            DatePickerRow {
                dateString: root.widgetsConfig.countdown.date
                onPicked: newDate => Config.options.background.widgets.countdown.date = newDate
            }
            Flow { // Date presets
                Layout.fillWidth: true
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                Layout.topMargin: 6
                Layout.bottomMargin: 8
                spacing: 6
                Repeater {
                    model: [
                        { name: Translation.tr("New Year"), icon: "celebration", date: () => new Date(new Date().getFullYear() + 1, 0, 1) },
                        { name: Translation.tr("In a week"), icon: "date_range", date: () => new Date(Date.now() + 7 * 86400000) },
                        { name: Translation.tr("In a month"), icon: "calendar_month", date: () => { const d = new Date(); d.setMonth(d.getMonth() + 1); return d; } },
                        { name: Translation.tr("In 100 days"), icon: "hourglass_bottom", date: () => new Date(Date.now() + 100 * 86400000) },
                        { name: Translation.tr("Clear"), icon: "close", date: () => null }
                    ]
                    delegate: RippleButton {
                        id: presetButton
                        required property var modelData
                        implicitHeight: 34
                        leftPadding: 12
                        rightPadding: 14
                        buttonRadius: Appearance.rounding.full
                        colBackground: Appearance.colors.colSecondaryContainer
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        colRipple: Appearance.colors.colSecondaryContainerActive
                        onClicked: {
                            const date = modelData.date();
                            Config.options.background.widgets.countdown.date = date ? root.dateString(date) : "";
                        }
                        contentItem: RowLayout {
                            spacing: 6
                            MaterialSymbol {
                                text: presetButton.modelData.icon
                                iconSize: 18
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                            StyledText {
                                text: presetButton.modelData.name
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }
                    }
                }
            }
            ConfigExpander {
                description: Translation.tr("Time of day, hours and minutes left")
                RowLayout { // Time of the event
                    readonly property bool settingsSearchable: true
                    property string searchText: Translation.tr("Time")
                    property string text: Translation.tr("Time")
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    Layout.topMargin: 5
                    Layout.bottomMargin: 5
                    spacing: 12
                    ConfigIconTile {
                        icon: "schedule"
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        StyledText {
                            text: Translation.tr("Time")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Leave 00:00 to count to the start of the day")
                            wrapMode: Text.Wrap
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                    StyledSpinBox {
                        radius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer3
                        colButtonHover: Appearance.colors.colLayer3Hover
                        colButtonActive: Appearance.colors.colLayer3Active
                        from: 0
                        to: 23
                        value: root.widgetsConfig.countdown.hour
                        onValueChanged: if (value !== root.widgetsConfig.countdown.hour) Config.options.background.widgets.countdown.hour = value
                    }
                    StyledText {
                        text: ":"
                        font.pixelSize: Appearance.font.pixelSize.large
                        color: Appearance.colors.colOnLayer2
                    }
                    StyledSpinBox {
                        radius: Appearance.rounding.full
                        colBackground: Appearance.colors.colLayer3
                        colButtonHover: Appearance.colors.colLayer3Hover
                        colButtonActive: Appearance.colors.colLayer3Active
                        from: 0
                        to: 59
                        stepSize: 5
                        value: root.widgetsConfig.countdown.minute
                        onValueChanged: if (value !== root.widgetsConfig.countdown.minute) Config.options.background.widgets.countdown.minute = value
                    }
                }
                ConfigSwitch {
                    buttonIcon: "schedule"
                    text: Translation.tr("Show hours and minutes")
                    description: Translation.tr("Under the number of days")
                    autoToggle: false
                    checked: root.widgetsConfig.countdown.showHours
                    onClicked: Config.options.background.widgets.countdown.showHours = !root.widgetsConfig.countdown.showHours
                }
            }
        }

        WidgetDetails {
            widgetKey: "note"
            description: Translation.tr("You can also edit it on the desktop with the pencil button")

            ConfigTextRow {
                icon: "title"
                label: Translation.tr("Title")
                inline: true
                wrapMode: TextEdit.NoWrap
                placeholderText: Translation.tr("Note")
                value: root.widgetsConfig.note.title
                onValueChanged: Config.options.background.widgets.note.title = value
            }
            ConfigTextRow {
                icon: "notes"
                label: Translation.tr("Text")
                placeholderText: Translation.tr("Write something to remember...")
                value: root.widgetsConfig.note.text
                onValueChanged: Config.options.background.widgets.note.text = value
                fieldMinimumHeight: 96
            }
        }

        WidgetDetails {
            widgetKey: "pomodoro"
            description: Translation.tr("Shares its timer with the pomodoro in the right sidebar. Before a period starts you can also change its length on the widget.")

            ConfigRow {
                uniform: true
                ConfigSpinBox {
                    icon: "target"
                    text: Translation.tr("Focus (min)")
                    value: Math.round(Config.options.time.pomodoro.focus / 60)
                    from: 1
                    to: 180
                    stepSize: 5
                    onValueChanged: Config.options.time.pomodoro.focus = value * 60
                }
                ConfigSpinBox {
                    icon: "coffee"
                    text: Translation.tr("Break (min)")
                    value: Math.round(Config.options.time.pomodoro.breakTime / 60)
                    from: 1
                    to: 60
                    stepSize: 1
                    onValueChanged: Config.options.time.pomodoro.breakTime = value * 60
                }
            }
            ConfigSwitch {
                buttonIcon: "notification_sound"
                text: Translation.tr("Play a sound when a phase ends")
                autoToggle: false
                checked: Config.options.sounds.pomodoro
                onClicked: Config.options.sounds.pomodoro = !Config.options.sounds.pomodoro
            }
            ConfigExpander {
                description: Translation.tr("Long breaks and how often they come")
                ConfigSpinBox {
                    icon: "self_improvement"
                    text: Translation.tr("Long break (min)")
                    value: Math.round(Config.options.time.pomodoro.longBreak / 60)
                    from: 1
                    to: 120
                    stepSize: 5
                    onValueChanged: Config.options.time.pomodoro.longBreak = value * 60
                }
                ConfigSpinBox {
                    icon: "repeat"
                    text: Translation.tr("Cycles before long break")
                    value: Config.options.time.pomodoro.cyclesBeforeLongBreak
                    from: 1
                    to: 12
                    stepSize: 1
                    onValueChanged: Config.options.time.pomodoro.cyclesBeforeLongBreak = value
                }
            }
        }
    }

    ContentSection {
        icon: "style"
        title: Translation.tr("Card style")
        description: Translation.tr("The background of the system monitor, calendar, countdown, note and pomodoro")

        Flow {
            Layout.fillWidth: true
            Layout.margins: 4
            spacing: 4
            CardStyleTile {
                styleValue: "tonal"
                label: Translation.tr("Tonal")
            }
            CardStyleTile {
                styleValue: "surface"
                label: Translation.tr("Surface")
            }
            CardStyleTile {
                styleValue: "transparent"
                label: Translation.tr("Transparent")
            }
        }
    }
}
