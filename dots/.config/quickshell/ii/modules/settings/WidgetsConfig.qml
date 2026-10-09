import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

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

    function sectionFor(key) {
        return {
            clock: clockSection,
            weather: weatherSection,
            systemMonitor: systemMonitorSection,
            media: mediaSection,
            calendar: calendarSection,
            countdown: countdownSection,
            note: noteSection,
            pomodoro: pomodoroSection
        }[key] ?? null;
    }

    function toggleWidget(key) {
        root.widgetsConfig[key].enable = !root.widgetsConfig[key].enable;
    }

    function dateString(date) {
        const pad = n => n.toString().padStart(2, "0");
        return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
    }

    // "Enable" row of a widget section, kept in sync with the gallery switch
    component WidgetEnableSwitch: ConfigSwitch {
        required property string widgetKey
        autoToggle: false
        buttonIcon: "power_settings_new"
        text: Translation.tr("Show on desktop")
        checked: root.widgetsConfig[widgetKey].enable
        onClicked: root.toggleWidget(widgetKey)
    }

    component PlacementSelector: ContentSubsection {
        required property string widgetKey
        title: Translation.tr("Placement")
        description: Translation.tr("Free lets you drag the widget around. The other options move it to an empty or busy part of the wallpaper.")
        ConfigSelectionArray {
            currentValue: root.widgetsConfig[widgetKey].placementStrategy
            onSelected: newValue => {
                root.widgetsConfig[widgetKey].placementStrategy = newValue;
            }
            options: [
                { displayName: Translation.tr("Free (drag)"), icon: "drag_pan", value: "free" },
                { displayName: Translation.tr("Least busy"), icon: "category", value: "leastBusy" },
                { displayName: Translation.tr("Most busy"), icon: "shapes", value: "mostBusy" }
            ]
        }
    }

    component WidgetTile: RippleButton {
        id: tile
        required property var modelData
        readonly property bool active: root.widgetsConfig[modelData.key].enable
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
        onClicked: root.revealItem(root.sectionFor(modelData.key))

        StyledToolTip {
            text: Translation.tr("Show options")
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

    // Gallery
    ContentSection {
        icon: "dashboard_customize"
        title: Translation.tr("Desktop widgets")
        description: Translation.tr("Switch widgets on and off. Click a card to jump to its options.")

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

    ContentSection {
        icon: "style"
        title: Translation.tr("Look")
        description: Translation.tr("Shared style of the system monitor, calendar, countdown, note and pomodoro widgets")

        ContentSubsection {
            title: Translation.tr("Card style")
            ConfigSelectionArray {
                currentValue: root.widgetsConfig.cardStyle
                onSelected: newValue => {
                    root.widgetsConfig.cardStyle = newValue;
                }
                options: [
                    { displayName: Translation.tr("Tonal"), icon: "format_color_fill", value: "tonal" },
                    { displayName: Translation.tr("Surface"), icon: "rectangle", value: "surface" },
                    { displayName: Translation.tr("Transparent"), icon: "blur_on", value: "transparent" }
                ]
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            Layout.margins: 6
            materialIcon: "drag_pan"
            text: Translation.tr("Widgets with free placement can be dragged right on the desktop. Their position is saved automatically.")
        }
    }

    // Clock
    ContentSection {
        id: clockSection
        icon: "nest_clock_farsight_analog"
        title: Translation.tr("Clock")
        description: Translation.tr("The clock on your wallpaper and lock screen")

        function stylePresent(styleName) {
            if (!Config.options.background.widgets.clock.showOnlyWhenLocked && Config.options.background.widgets.clock.style === styleName) {
                return true;
            }
            if (Config.options.background.widgets.clock.styleLocked === styleName) {
                return true;
            }
            return false;
        }

        readonly property bool digitalPresent: stylePresent("digital")
        readonly property bool cookiePresent: stylePresent("cookie")

        WidgetEnableSwitch {
            widgetKey: "clock"
        }
        ConfigSwitch {
            buttonIcon: "lock_clock"
            text: Translation.tr("Show only when locked")
            checked: Config.options.background.widgets.clock.showOnlyWhenLocked
            onCheckedChanged: {
                Config.options.background.widgets.clock.showOnlyWhenLocked = checked;
            }
        }
        PlacementSelector {
            widgetKey: "clock"
        }

        ConfigRow {
            ContentSubsection {
                visible: !Config.options.background.widgets.clock.showOnlyWhenLocked
                title: Translation.tr("Clock style")
                ConfigSelectionArray {
                    currentValue: Config.options.background.widgets.clock.style
                    onSelected: newValue => {
                        Config.options.background.widgets.clock.style = newValue;
                    }
                    options: [
                        { displayName: Translation.tr("Digital"), icon: "timer_10", value: "digital" },
                        { displayName: Translation.tr("Cookie"), icon: "cookie", value: "cookie" }
                    ]
                }
            }

            ContentSubsection {
                title: Translation.tr("Clock style (locked)")
                ConfigSelectionArray {
                    currentValue: Config.options.background.widgets.clock.styleLocked
                    onSelected: newValue => {
                        Config.options.background.widgets.clock.styleLocked = newValue;
                    }
                    options: [
                        { displayName: Translation.tr("Digital"), icon: "timer_10", value: "digital" },
                        { displayName: Translation.tr("Cookie"), icon: "cookie", value: "cookie" }
                    ]
                }
            }
        }

        ContentSubsection {
            visible: clockSection.digitalPresent
            title: Translation.tr("Digital clock settings")
            description: Translation.tr("Font width and roundness settings are only available for some fonts like Google Sans Flex")

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "vertical_distribute"
                    text: Translation.tr("Vertical")
                    checked: Config.options.background.widgets.clock.digital.vertical
                    onCheckedChanged: {
                        Config.options.background.widgets.clock.digital.vertical = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "animation"
                    text: Translation.tr("Animate time change")
                    checked: Config.options.background.widgets.clock.digital.animateChange
                    onCheckedChanged: {
                        Config.options.background.widgets.clock.digital.animateChange = checked;
                    }
                }
            }

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "date_range"
                    text: Translation.tr("Show date")
                    checked: Config.options.background.widgets.clock.digital.showDate
                    onCheckedChanged: {
                        Config.options.background.widgets.clock.digital.showDate = checked;
                    }
                }
                ConfigSwitch {
                    buttonIcon: "activity_zone"
                    text: Translation.tr("Use adaptive alignment")
                    description: Translation.tr("Aligns the date and quote to left, center or right depending on its position on the screen.")
                    checked: Config.options.background.widgets.clock.digital.adaptiveAlignment
                    onCheckedChanged: {
                        Config.options.background.widgets.clock.digital.adaptiveAlignment = checked;
                    }
                }
            }

            ConfigTextRow {
                icon: "font_download"
                label: Translation.tr("Font family")
                inline: true
                wrapMode: TextEdit.NoWrap
                placeholderText: "Google Sans Flex"
                value: Config.options.background.widgets.clock.digital.font.family
                onValueChanged: {
                    Config.options.background.widgets.clock.digital.font.family = value;
                }
            }

            ConfigSlider {
                text: Translation.tr("Font weight")
                value: Config.options.background.widgets.clock.digital.font.weight
                usePercentTooltip: false
                buttonIcon: "format_bold"
                from: 1
                to: 1000
                stopIndicatorValues: [350]
                onValueChanged: {
                    Config.options.background.widgets.clock.digital.font.weight = value;
                }
            }

            ConfigSlider {
                text: Translation.tr("Font size")
                value: Config.options.background.widgets.clock.digital.font.size
                usePercentTooltip: false
                buttonIcon: "format_size"
                from: 50
                to: 700
                stopIndicatorValues: [90]
                onValueChanged: {
                    Config.options.background.widgets.clock.digital.font.size = value;
                }
            }

            ConfigSlider {
                text: Translation.tr("Font width")
                value: Config.options.background.widgets.clock.digital.font.width
                usePercentTooltip: false
                buttonIcon: "fit_width"
                from: 25
                to: 125
                stopIndicatorValues: [100]
                onValueChanged: {
                    Config.options.background.widgets.clock.digital.font.width = value;
                }
            }
            ConfigSlider {
                text: Translation.tr("Font roundness")
                value: Config.options.background.widgets.clock.digital.font.roundness
                usePercentTooltip: false
                buttonIcon: "line_curve"
                from: 0
                to: 100
                onValueChanged: {
                    Config.options.background.widgets.clock.digital.font.roundness = value;
                }
            }
        }

        ContentSubsection {
            visible: clockSection.cookiePresent
            title: Translation.tr("Cookie clock settings")

            ConfigSwitch {
                buttonIcon: "wand_stars"
                text: Translation.tr("Auto styling with Gemini")
                description: Translation.tr("Uses Gemini to categorize the wallpaper then picks a preset based on it. You'll need to set Gemini API key on the left sidebar first. Images are downscaled for performance, but just to be safe, do not select wallpapers with sensitive information.")
                checked: Config.options.background.widgets.clock.cookie.aiStyling
                onCheckedChanged: {
                    Config.options.background.widgets.clock.cookie.aiStyling = checked;
                }
            }

            ConfigSwitch {
                buttonIcon: "airwave"
                text: Translation.tr("Use old sine wave cookie implementation")
                description: Translation.tr("Looks a bit softer and more consistent with different number of sides, but has less impressive morphing")
                checked: Config.options.background.widgets.clock.cookie.useSineCookie
                onCheckedChanged: {
                    Config.options.background.widgets.clock.cookie.useSineCookie = checked;
                }
            }

            ConfigSpinBox {
                icon: "add_triangle"
                text: Translation.tr("Sides")
                value: Config.options.background.widgets.clock.cookie.sides
                from: 0
                to: 40
                stepSize: 1
                onValueChanged: {
                    Config.options.background.widgets.clock.cookie.sides = value;
                }
            }

            ConfigSwitch {
                buttonIcon: "autoplay"
                text: Translation.tr("Constantly rotate")
                description: Translation.tr("Makes the clock always rotate. This is extremely expensive (expect 50% usage on Intel UHD Graphics) and thus impractical.")
                checked: Config.options.background.widgets.clock.cookie.constantlyRotate
                onCheckedChanged: {
                    Config.options.background.widgets.clock.cookie.constantlyRotate = checked;
                }
            }

            ConfigRow {
                uniform: true
                ConfigSwitch {
                    enabled: Config.options.background.widgets.clock.cookie.dialNumberStyle === "dots" || Config.options.background.widgets.clock.cookie.dialNumberStyle === "full"
                    buttonIcon: "brightness_7"
                    text: Translation.tr("Hour marks")
                    description: Translation.tr("Only with the 'Dots' or 'Full' dial style")
                    checked: Config.options.background.widgets.clock.cookie.hourMarks
                    onEnabledChanged: {
                        checked = Config.options.background.widgets.clock.cookie.hourMarks;
                    }
                    onCheckedChanged: {
                        Config.options.background.widgets.clock.cookie.hourMarks = checked;
                    }
                }

                ConfigSwitch {
                    enabled: Config.options.background.widgets.clock.cookie.dialNumberStyle !== "numbers"
                    buttonIcon: "timer_10"
                    text: Translation.tr("Digits in the middle")
                    description: Translation.tr("Not available with the 'Numbers' dial style")
                    checked: Config.options.background.widgets.clock.cookie.timeIndicators
                    onEnabledChanged: {
                        checked = Config.options.background.widgets.clock.cookie.timeIndicators;
                    }
                    onCheckedChanged: {
                        Config.options.background.widgets.clock.cookie.timeIndicators = checked;
                    }
                }
            }
        }

        ContentSubsection {
            visible: clockSection.cookiePresent
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
            visible: clockSection.cookiePresent
            ContentSubsection {
                title: Translation.tr("Hour hand")
                ConfigSelectionArray {
                    currentValue: Config.options.background.widgets.clock.cookie.hourHandStyle
                    onSelected: newValue => {
                        Config.options.background.widgets.clock.cookie.hourHandStyle = newValue;
                    }
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
                    onSelected: newValue => {
                        Config.options.background.widgets.clock.cookie.secondHandStyle = newValue;
                    }
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
            visible: clockSection.cookiePresent
            title: Translation.tr("Minute hand")
            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.clock.cookie.minuteHandStyle
                onSelected: newValue => {
                    Config.options.background.widgets.clock.cookie.minuteHandStyle = newValue;
                }
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
            visible: clockSection.cookiePresent
            title: Translation.tr("Date style")
            ConfigSelectionArray {
                currentValue: Config.options.background.widgets.clock.cookie.dateStyle
                onSelected: newValue => {
                    Config.options.background.widgets.clock.cookie.dateStyle = newValue;
                }
                options: [
                    { displayName: "", icon: "block", value: "hide" },
                    { displayName: Translation.tr("Bubble"), icon: "bubble_chart", value: "bubble" },
                    { displayName: Translation.tr("Border"), icon: "rotate_right", value: "border" },
                    { displayName: Translation.tr("Rect"), icon: "rectangle", value: "rect" }
                ]
            }
        }

        ContentSubsection {
            title: Translation.tr("Quote")
            ConfigSwitch {
                buttonIcon: "format_quote"
                text: Translation.tr("Show a quote under the clock")
                checked: Config.options.background.widgets.clock.quote.enable
                onCheckedChanged: {
                    Config.options.background.widgets.clock.quote.enable = checked;
                }
            }
            ConfigTextRow {
                enabled: Config.options.background.widgets.clock.quote.enable
                placeholderText: Translation.tr("Quote")
                value: Config.options.background.widgets.clock.quote.text
                onValueChanged: {
                    Config.options.background.widgets.clock.quote.text = value;
                }
            }
        }
    }

    // Weather
    ContentSection {
        id: weatherSection
        icon: "partly_cloudy_day"
        title: Translation.tr("Weather")
        description: Translation.tr("Data comes from wttr.in. These settings are shared with the bar.")

        WidgetEnableSwitch {
            widgetKey: "weather"
        }
        PlacementSelector {
            widgetKey: "weather"
        }
        ConfigSwitch {
            buttonIcon: "toast"
            text: Translation.tr("Also show in the bar")
            autoToggle: false
            checked: Config.options.bar.weather.enable
            onClicked: Config.options.bar.weather.enable = !Config.options.bar.weather.enable
        }
        ConfigRow {
            uniform: true
            ConfigSwitch {
                buttonIcon: "assistant_navigation"
                text: Translation.tr("Enable GPS based location")
                checked: Config.options.bar.weather.enableGPS
                onCheckedChanged: {
                    Config.options.bar.weather.enableGPS = checked;
                }
            }
            ConfigSwitch {
                buttonIcon: "thermometer"
                text: Translation.tr("Fahrenheit unit")
                description: Translation.tr("It may take a few seconds to update")
                checked: Config.options.bar.weather.useUSCS
                onCheckedChanged: {
                    Config.options.bar.weather.useUSCS = checked;
                }
            }
        }
        ConfigTextRow {
            icon: "location_city"
            label: Translation.tr("City name")
            description: Translation.tr("Used when GPS is off or unavailable")
            inline: true
            wrapMode: TextEdit.NoWrap
            placeholderText: Translation.tr("e.g. Moscow")
            value: Config.options.bar.weather.city
            onValueChanged: {
                Config.options.bar.weather.city = value;
            }
        }
        ConfigSpinBox {
            icon: "av_timer"
            text: Translation.tr("Polling interval (m)")
            value: Config.options.bar.weather.fetchInterval
            from: 5
            to: 50
            stepSize: 5
            onValueChanged: {
                Config.options.bar.weather.fetchInterval = value;
            }
        }
    }

    // System monitor
    ContentSection {
        id: systemMonitorSection
        icon: "monitor_heart"
        title: Translation.tr("System monitor")
        description: Translation.tr("Live usage of your hardware. Readings refresh at the resource polling interval.")

        WidgetEnableSwitch {
            widgetKey: "systemMonitor"
        }
        PlacementSelector {
            widgetKey: "systemMonitor"
        }
        ContentSubsection {
            title: Translation.tr("Show")
            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "memory"
                    text: Translation.tr("CPU")
                    checked: root.widgetsConfig.systemMonitor.showCpu
                    onCheckedChanged: root.widgetsConfig.systemMonitor.showCpu = checked
                }
                ConfigSwitch {
                    buttonIcon: "memory_alt"
                    text: Translation.tr("Memory")
                    checked: root.widgetsConfig.systemMonitor.showMemory
                    onCheckedChanged: root.widgetsConfig.systemMonitor.showMemory = checked
                }
            }
            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "swap_horiz"
                    text: Translation.tr("Swap")
                    checked: root.widgetsConfig.systemMonitor.showSwap
                    onCheckedChanged: root.widgetsConfig.systemMonitor.showSwap = checked
                }
                ConfigSwitch {
                    buttonIcon: "thermostat"
                    text: Translation.tr("CPU temperature")
                    checked: root.widgetsConfig.systemMonitor.showTemperature
                    onCheckedChanged: root.widgetsConfig.systemMonitor.showTemperature = checked
                }
            }
            ConfigRow {
                uniform: true
                ConfigSwitch {
                    buttonIcon: "hard_drive"
                    text: Translation.tr("Disk usage")
                    checked: root.widgetsConfig.systemMonitor.showDisk
                    onCheckedChanged: root.widgetsConfig.systemMonitor.showDisk = checked
                }
                ConfigSwitch {
                    buttonIcon: "network_check"
                    text: Translation.tr("Network speed")
                    checked: root.widgetsConfig.systemMonitor.showNetwork
                    onCheckedChanged: root.widgetsConfig.systemMonitor.showNetwork = checked
                }
            }
            ConfigSwitch {
                buttonIcon: "monitoring"
                text: Translation.tr("History graphs")
                description: Translation.tr("Draws a small graph of recent CPU and memory usage")
                checked: root.widgetsConfig.systemMonitor.showGraphs
                onCheckedChanged: root.widgetsConfig.systemMonitor.showGraphs = checked
            }
        }
    }

    // Media
    ContentSection {
        id: mediaSection
        icon: "music_note"
        title: Translation.tr("Media")
        description: Translation.tr("Controls the active player, like the media popup of the bar")

        WidgetEnableSwitch {
            widgetKey: "media"
        }
        PlacementSelector {
            widgetKey: "media"
        }
        ConfigSwitch {
            buttonIcon: "visibility_off"
            text: Translation.tr("Hide when nothing is playing")
            checked: root.widgetsConfig.media.hideWhenIdle
            onCheckedChanged: root.widgetsConfig.media.hideWhenIdle = checked
        }
    }

    // Calendar
    ContentSection {
        id: calendarSection
        icon: "calendar_month"
        title: Translation.tr("Calendar")
        description: Translation.tr("Scroll over the widget to change the month, click the title to come back")

        WidgetEnableSwitch {
            widgetKey: "calendar"
        }
        PlacementSelector {
            widgetKey: "calendar"
        }
        ConfigSwitch {
            buttonIcon: "weekend"
            text: Translation.tr("Highlight weekends")
            checked: root.widgetsConfig.calendar.highlightWeekends
            onCheckedChanged: root.widgetsConfig.calendar.highlightWeekends = checked
        }
    }

    // Countdown
    ContentSection {
        id: countdownSection
        icon: "hourglass_top"
        title: Translation.tr("Countdown")
        description: Translation.tr("Counts the days to a birthday, a trip or a deadline")

        WidgetEnableSwitch {
            widgetKey: "countdown"
        }
        PlacementSelector {
            widgetKey: "countdown"
        }
        ConfigTextRow {
            icon: "label"
            label: Translation.tr("Title")
            inline: true
            wrapMode: TextEdit.NoWrap
            placeholderText: Translation.tr("e.g. Vacation")
            value: root.widgetsConfig.countdown.title
            onValueChanged: root.widgetsConfig.countdown.title = value
        }
        DatePickerRow {
            dateString: root.widgetsConfig.countdown.date
            onPicked: newDate => root.widgetsConfig.countdown.date = newDate
        }
        RowLayout { // Time of the event
            readonly property bool settingsSearchable: true
            property string searchText: Translation.tr("Time")
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
                onValueChanged: if (value !== root.widgetsConfig.countdown.hour) root.widgetsConfig.countdown.hour = value
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
                onValueChanged: if (value !== root.widgetsConfig.countdown.minute) root.widgetsConfig.countdown.minute = value
            }
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
                        root.widgetsConfig.countdown.date = date ? root.dateString(date) : "";
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
        ConfigSwitch {
            buttonIcon: "schedule"
            text: Translation.tr("Show hours and minutes")
            description: Translation.tr("Under the number of days")
            checked: root.widgetsConfig.countdown.showHours
            onCheckedChanged: root.widgetsConfig.countdown.showHours = checked
        }
    }

    // Note
    ContentSection {
        id: noteSection
        icon: "sticky_note_2"
        title: Translation.tr("Note")
        description: Translation.tr("You can also edit it on the desktop with the pencil button")

        WidgetEnableSwitch {
            widgetKey: "note"
        }
        PlacementSelector {
            widgetKey: "note"
        }
        ConfigTextRow {
            icon: "title"
            label: Translation.tr("Title")
            inline: true
            wrapMode: TextEdit.NoWrap
            placeholderText: Translation.tr("Note")
            value: root.widgetsConfig.note.title
            onValueChanged: root.widgetsConfig.note.title = value
        }
        ConfigTextRow {
            icon: "notes"
            label: Translation.tr("Text")
            placeholderText: Translation.tr("Write something to remember...")
            value: root.widgetsConfig.note.text
            onValueChanged: root.widgetsConfig.note.text = value
            fieldMinimumHeight: 96
        }
    }

    // Pomodoro
    ContentSection {
        id: pomodoroSection
        icon: "timer"
        title: Translation.tr("Pomodoro")
        description: Translation.tr("Shares its timer with the pomodoro in the right sidebar. Before a period starts you can also change its length on the widget.")

        WidgetEnableSwitch {
            widgetKey: "pomodoro"
        }
        PlacementSelector {
            widgetKey: "pomodoro"
        }
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
        ConfigRow {
            uniform: true
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
        ConfigSwitch {
            buttonIcon: "notification_sound"
            text: Translation.tr("Play a sound when a phase ends")
            autoToggle: false
            checked: Config.options.sounds.pomodoro
            onClicked: Config.options.sounds.pomodoro = !Config.options.sounds.pomodoro
        }
    }
}
