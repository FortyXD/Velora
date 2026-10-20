import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * A miniature of a preset on screen, drawn over its wallpaper from the preset's own settings:
 * the bar with its layout, position and style, the desktop widgets and the dock.
 * Parts the preset doesn't set are taken from the current settings.
 */
Item {
    id: root

    property var preset: null
    property bool barOnly: false // Just the bar, for bar presets

    // One screen pixel, a little enlarged so the details stay readable on a small card; the bar a bit more
    readonly property real u: width / 1100
    readonly property real bu: width / 760

    // What gets drawn
    readonly property var bar: root.preset?.bar?.config?.bar ?? Config.options.bar
    readonly property var barStyle: root.bar.style ?? ({})
    readonly property bool vertical: !!root.bar.vertical
    readonly property var layout: (root.vertical ? root.bar.verticalLayout : root.bar.layout)
        ?? (root.vertical ? BarLayoutDefaults.vertical : BarLayoutDefaults.horizontal)
    readonly property var widgets: root.preset?.dockWidgets?.config?.background?.widgets ?? Config.options.background.widgets
    readonly property var dock: root.preset?.dockWidgets?.config?.dock ?? Config.options.dock
    readonly property bool weatherOn: root.bar.weather?.enable ?? Config.options.bar.weather.enable

    // Colors: from the preset's accent and mode, or the current theme when it has none
    readonly property bool dark: (root.preset?.theme?.mode ?? (Appearance.m3colors.darkmode ? "dark" : "light")) !== "light"
    readonly property string accent: root.preset?.theme?.accent ?? ""
    readonly property bool mono: root.preset?.theme?.config?.appearance?.palette?.type === "scheme-monochrome"
    readonly property bool ownColors: root.mono || /^#[0-9a-f]{6}$/i.test(root.accent)
    readonly property bool currentTheme: !root.ownColors && root.dark === Appearance.m3colors.darkmode
    readonly property color colSurface: root.mono ? (root.dark ? "#141414" : "#f7f7f7")
        : root.ownColors ? ColorUtils.mix(root.accent, root.dark ? "#121212" : "#fcfcfc", 0.07)
        : root.currentTheme ? Appearance.m3colors.m3surfaceContainerLow : (root.dark ? "#1b1b1f" : "#f6f5f9")
    readonly property color colPill: root.mono ? (root.dark ? "#2a2a2a" : "#e4e4e4")
        : root.ownColors ? ColorUtils.mix(root.accent, root.dark ? "#2a2a2a" : "#ebebeb", 0.14)
        : root.currentTheme ? Appearance.m3colors.m3surfaceContainerHigh : (root.dark ? "#2b2a30" : "#e8e6ee")
    readonly property color colOn: root.mono ? (root.dark ? "#eeeeee" : "#202020")
        : root.ownColors ? ColorUtils.mix(root.accent, root.dark ? "#f2f2f2" : "#161616", 0.12)
        : root.currentTheme ? Appearance.m3colors.m3onSurface : (root.dark ? "#e6e1e9" : "#1c1b1f")
    readonly property color colPrimary: root.mono ? (root.dark ? "#ffffff" : "#000000")
        : root.ownColors ? ColorUtils.mix(root.accent, root.dark ? "#ffffff" : "#000000", root.dark ? 0.7 : 0.82)
        : root.currentTheme ? Appearance.m3colors.m3primary : (root.dark ? "#cfbcff" : "#6750a4")
    readonly property color colOnPrimary: root.dark ? ColorUtils.mix(root.colPrimary, "#000000", 0.25) : "#ffffff"

    // Bar geometry
    readonly property real t: (root.barStyle.thickness > 0 ? root.barStyle.thickness : 40) * root.bu
    readonly property bool islands: !!root.barStyle.islands
    readonly property bool floating: root.bar.cornerStyle === 1 || root.islands
    readonly property real margin: root.floating ? (root.barStyle.floatMargin >= 0 ? root.barStyle.floatMargin : 8) * root.bu : 0
    readonly property real cornerRadius: (root.barStyle.radius >= 0 ? root.barStyle.radius : 16) * root.bu
    readonly property string pillStyle: root.bar.borderless ? "none" : (root.barStyle.pillStyle ?? "filled")
    readonly property real barOpacity: root.barStyle.backgroundOpacity >= 0 ? root.barStyle.backgroundOpacity : root.barStyle.glass ? 0.6 : 0.94

    // Consecutive pill items share one pill, like on the real bar
    function groupsOf(items) {
        let groups = [];
        for (const item of items ?? []) {
            if (["spacer", "privacy"].includes(item.type) || (item.type === "weather" && !root.weatherOn)) continue;
            if (root.vertical && ["activeWindow", "networkSpeed", "utilButtons", "weather", "text", "customCommand"].includes(item.type)) continue;
            const last = groups[groups.length - 1];
            if (item.pill && last?.pill && !item.pillBreak) last.items.push(item);
            else groups.push({ "pill": !!item.pill, "items": [item] });
        }
        return groups;
    }

    // Desktop widgets take turns over a few spots, roughly where the real ones tend to land
    readonly property var widgetOrder: ["clock", "weather", "systemMonitor", "media", "calendar", "countdown", "note", "pomodoro"]
    readonly property var spots: [[0.77, 0.56], [0.19, 0.40], [0.48, 0.32], [0.22, 0.74], [0.50, 0.70], [0.80, 0.24]]
    readonly property var shownWidgets: root.barOnly ? [] : root.widgetOrder.filter(name => root.widgets?.[name]?.enable)

    // Bar
    Item {
        id: barArea
        readonly property real length: root.vertical ? root.height - root.margin * 2 : root.width - root.margin * 2
        x: root.vertical ? (root.bar.bottom ? root.width - root.t - root.margin : root.margin) : root.margin
        y: root.vertical ? root.margin : (root.bar.bottom ? root.height - root.t - root.margin : root.margin)
        width: root.vertical ? root.t : length
        height: root.vertical ? length : root.t
        z: 2

        Rectangle {
            anchors.fill: parent
            visible: root.bar.showBackground !== false && !root.islands
            color: ColorUtils.applyAlpha(root.colSurface, root.barOpacity)
            radius: root.bar.cornerStyle === 1 ? root.cornerRadius : 0
            border.width: root.bar.cornerStyle === 1 ? Math.max(1, root.bu) : 0
            border.color: ColorUtils.applyAlpha(root.colOn, 0.08)
        }

        // A busy bar shrinks to fit, like the real one gives up space before running off the screen
        readonly property real fit: {
            const along = item => root.vertical ? item.implicitHeight : item.implicitWidth;
            const needed = Math.max(along(startRow), along(endRow)) + along(middleRow) / 2 + root.t * 0.6;
            return Math.min(1, (barArea.length / 2) / Math.max(1, needed));
        }

        ZoneRow {
            id: startRow
            groups: root.groupsOf(root.layout.zones?.start)
            scale: barArea.fit
            transformOrigin: root.vertical ? Item.Top : Item.Left
            x: root.vertical ? (parent.width - width) / 2 : root.t * 0.3
            y: root.vertical ? root.t * 0.3 : (parent.height - height) / 2
        }
        ZoneRow {
            id: middleRow
            groups: [...root.groupsOf(root.layout.zones?.centerStart), ...root.groupsOf(root.layout.zones?.center), ...root.groupsOf(root.layout.zones?.centerEnd)]
            scale: barArea.fit
            x: (parent.width - width) / 2
            y: (parent.height - height) / 2
        }
        ZoneRow {
            id: endRow
            groups: root.groupsOf(root.layout.zones?.end)
            scale: barArea.fit
            transformOrigin: root.vertical ? Item.Bottom : Item.Right
            x: root.vertical ? (parent.width - width) / 2 : parent.width - width - root.t * 0.3
            y: root.vertical ? parent.height - height - root.t * 0.3 : (parent.height - height) / 2
        }
    }

    // Dock, when the bar leaves room for it at the bottom
    Rectangle {
        visible: !root.barOnly && !!root.dock?.enable && !(root.bar.bottom && !root.vertical)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 10 * root.u
        width: dockRow.implicitWidth + 16 * root.u
        height: 58 * root.u
        radius: 18 * root.u
        color: ColorUtils.applyAlpha(root.colSurface, 0.9)
        Row {
            id: dockRow
            anchors.centerIn: parent
            spacing: 8 * root.u
            Repeater {
                model: 5
                Rectangle {
                    required property int index
                    width: 40 * root.u
                    height: width
                    radius: 11 * root.u
                    color: index === 1 ? root.colPrimary : ColorUtils.applyAlpha(root.colOn, 0.25 + 0.1 * (index % 3))
                }
            }
        }
    }

    // Desktop widgets
    Repeater {
        model: root.shownWidgets
        delegate: Loader {
            id: widgetLoader
            required property string modelData
            required property int index
            readonly property var config: root.widgets[modelData]
            readonly property var spot: root.spots[index % root.spots.length]
            x: Math.max(4, Math.min(root.width - width - 4, root.width * spot[0] - width / 2))
            y: Math.max(root.t + root.margin * 2 + 4, Math.min(root.height - height - 4, root.height * spot[1] - height / 2))
            sourceComponent: modelData === "clock" ? (config.style === "digital" ? digitalClock : cookieClock)
                : modelData === "calendar" ? calendarCard
                : modelData === "systemMonitor" ? monitorCard
                : modelData === "weather" ? weatherCard
                : modelData === "media" ? mediaCard
                : noteCard
        }
    }

    // A row (column on a vertical bar) of groups of one zone
    component ZoneRow: Grid {
        property var groups: []
        columns: root.vertical ? 1 : 99
        spacing: root.islands ? root.t * 0.3 : root.t * 0.22
        verticalItemAlignment: Grid.AlignVCenter
        horizontalItemAlignment: Grid.AlignHCenter
        Repeater {
            model: parent.groups
            delegate: Rectangle {
                id: group
                required property var modelData
                readonly property bool pill: modelData.pill && root.pillStyle !== "none"
                readonly property real pad: root.islands || pill ? root.t * 0.24 : 0
                implicitWidth: root.vertical ? root.t * (root.islands ? 1 : 0.8) : groupItems.implicitWidth + pad * 2
                implicitHeight: root.vertical ? groupItems.implicitHeight + pad * 2 : root.t * (root.islands ? 1 : 0.76)
                radius: root.islands ? root.cornerRadius : Math.min(width, height) / 2
                color: root.islands ? ColorUtils.applyAlpha(root.colSurface, root.barOpacity)
                    : pill && root.pillStyle === "filled" ? root.colPill : "transparent"
                border.width: pill && root.pillStyle === "outlined" ? Math.max(1, root.bu * 1.4) : 0
                border.color: ColorUtils.applyAlpha(root.colOn, 0.45)
                Grid {
                    id: groupItems
                    anchors.centerIn: parent
                    columns: root.vertical ? 1 : 99
                    spacing: root.t * 0.24
                    verticalItemAlignment: Grid.AlignVCenter
                    horizontalItemAlignment: Grid.AlignHCenter
                    Repeater {
                        model: group.modelData.items
                        delegate: Loader {
                            required property var modelData
                            readonly property var entry: modelData
                            sourceComponent: {
                                switch (modelData.type) {
                                case "workspaces": return workspacesGlyph;
                                case "clock": return clockGlyph;
                                case "activeWindow": return windowGlyph;
                                case "media": case "island": return mediaGlyph;
                                case "statusIndicators": return statusGlyph;
                                case "sysTray": return trayGlyph;
                                case "battery": return batteryGlyph;
                                case "separator": return separatorGlyph;
                                case "fixedSpace": return gapGlyph;
                                case "weather": return weatherGlyph;
                                case "utilButtons": return utilGlyph;
                                case "networkSpeed": return speedGlyph;
                                default: return iconGlyph;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Bar items
    Component {
        id: iconGlyph
        MaterialSymbol {
            text: BarWidgetCatalog.get(parent?.entry?.type ?? "")?.icon ?? "circle"
            iconSize: root.t * 0.44
            fill: 1
            color: root.colOn
        }
    }
    Component {
        id: workspacesGlyph
        Grid {
            columns: root.vertical ? 1 : 99
            spacing: root.t * 0.13
            verticalItemAlignment: Grid.AlignVCenter
            horizontalItemAlignment: Grid.AlignHCenter
            Repeater {
                model: 6
                Rectangle {
                    required property int index
                    readonly property bool active: index === 1
                    implicitWidth: root.vertical ? root.t * (active ? 0.32 : 0.13) : (active ? root.t * 0.5 : root.t * 0.13)
                    implicitHeight: root.vertical ? (active ? root.t * 0.5 : root.t * 0.13) : root.t * (active ? 0.32 : 0.13)
                    radius: Math.min(implicitWidth, implicitHeight) / 2
                    color: active ? root.colPrimary : ColorUtils.applyAlpha(root.colOn, index < 3 ? 0.75 : 0.35)
                }
            }
        }
    }
    Component {
        id: clockGlyph
        StyledText {
            text: root.vertical ? "11\n07" : ((parent?.entry?.options?.showDate ?? true) ? "11:07 · Tue" : "11:07")
            horizontalAlignment: Text.AlignHCenter
            lineHeight: 0.85
            font.pixelSize: root.t * (root.vertical ? 0.34 : 0.36)
            font.weight: Font.Medium
            color: root.colOn
        }
    }
    Component {
        id: windowGlyph
        Column {
            spacing: root.t * 0.08
            Rectangle {
                width: root.t * 1.3
                height: root.t * 0.09
                radius: height / 2
                color: ColorUtils.applyAlpha(root.colOn, 0.4)
            }
            Rectangle {
                width: root.t * 2.4
                height: root.t * 0.14
                radius: height / 2
                color: ColorUtils.applyAlpha(root.colOn, 0.85)
            }
        }
    }
    Component {
        id: mediaGlyph
        Row {
            spacing: root.t * 0.14
            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                text: "music_note"
                iconSize: root.t * 0.42
                fill: 1
                color: root.colPrimary
            }
            Rectangle {
                visible: !root.vertical
                anchors.verticalCenter: parent.verticalCenter
                width: root.t * 1.8
                height: root.t * 0.12
                radius: height / 2
                color: ColorUtils.applyAlpha(root.colOn, 0.6)
            }
        }
    }
    Component {
        id: statusGlyph
        Grid {
            columns: root.vertical ? 1 : 99
            spacing: root.t * 0.12
            Repeater {
                model: ["wifi", "bluetooth", "notifications"]
                MaterialSymbol {
                    required property string modelData
                    text: modelData
                    iconSize: root.t * 0.38
                    fill: 1
                    color: root.colOn
                }
            }
        }
    }
    Component {
        id: trayGlyph
        Grid {
            columns: root.vertical ? 1 : 99
            spacing: root.t * 0.12
            Repeater {
                model: 3
                Rectangle {
                    required property int index
                    width: root.t * 0.3
                    height: width
                    radius: root.t * 0.08
                    color: ColorUtils.applyAlpha(root.colOn, 0.4 + 0.15 * index)
                }
            }
        }
    }
    Component {
        id: batteryGlyph
        Rectangle {
            width: root.t * 0.74
            height: root.t * 0.38
            radius: height / 2
            color: ColorUtils.applyAlpha(root.colOn, 0.85)
            StyledText {
                anchors.centerIn: parent
                text: "87"
                font.pixelSize: root.t * 0.24
                font.weight: Font.Bold
                color: root.colSurface
            }
        }
    }
    Component {
        id: separatorGlyph
        Rectangle {
            width: root.vertical ? root.t * 0.5 : Math.max(1, root.bu)
            height: root.vertical ? Math.max(1, root.bu) : root.t * 0.5
            color: ColorUtils.applyAlpha(root.colOn, 0.35)
        }
    }
    Component {
        id: gapGlyph
        Item {
            width: (parent?.entry?.options?.size ?? 16) * root.bu
            height: width
        }
    }
    Component {
        id: weatherGlyph
        Row {
            spacing: root.t * 0.08
            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                text: "partly_cloudy_day"
                iconSize: root.t * 0.42
                fill: 1
                color: root.colOn
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: "5°"
                font.pixelSize: root.t * 0.34
                color: root.colOn
            }
        }
    }
    Component {
        id: utilGlyph
        Row {
            spacing: root.t * 0.14
            Repeater {
                model: ["screenshot_region", "videocam", "keyboard", "dark_mode"]
                MaterialSymbol {
                    required property string modelData
                    text: modelData
                    iconSize: root.t * 0.36
                    color: root.colOn
                }
            }
        }
    }
    Component {
        id: speedGlyph
        StyledText {
            text: "↓4 MB/s"
            font.pixelSize: root.t * 0.28
            color: root.colOn
        }
    }

    // Desktop widgets
    component Card: Rectangle {
        readonly property string cardStyle: root.widgets?.cardStyle ?? "tonal"
        radius: 18 * root.u
        color: cardStyle === "transparent" ? "transparent"
            : ColorUtils.applyAlpha(cardStyle === "surface" ? root.colSurface : root.colPill, 0.88)
    }
    Component {
        id: cookieClock
        Item {
            id: cookie
            readonly property var cookieConfig: parent?.config?.cookie ?? ({})
            readonly property int sides: cookieConfig.sides ?? 14
            width: 230 * root.u
            height: width
            MaterialShape {
                anchors.fill: parent
                implicitSize: parent.width
                shape: cookie.sides <= 0 ? MaterialShape.Shape.Circle
                    : cookie.sides <= 5 ? MaterialShape.Shape.Cookie4Sided
                    : cookie.sides <= 6 ? MaterialShape.Shape.Cookie6Sided
                    : cookie.sides <= 8 ? MaterialShape.Shape.Cookie7Sided
                    : cookie.sides <= 10 ? MaterialShape.Shape.Cookie9Sided
                    : MaterialShape.Shape.Cookie12Sided
                color: ColorUtils.mix(root.colPrimary, root.colSurface, 0.32)
            }
            Repeater { // Marks at 12, 3, 6 and 9
                model: 4
                Rectangle {
                    required property int index
                    readonly property real angle: index * Math.PI / 2
                    width: 14 * root.u
                    height: width
                    radius: width / 2
                    x: cookie.width / 2 + Math.sin(angle) * cookie.width * 0.33 - width / 2
                    y: cookie.height / 2 - Math.cos(angle) * cookie.height * 0.33 - height / 2
                    color: ColorUtils.applyAlpha(root.colOn, 0.55)
                }
            }
            Rectangle { // Hour hand
                x: parent.width / 2 - width / 2
                y: parent.height / 2 - height + width / 2
                width: 18 * root.u
                height: 62 * root.u
                radius: width / 2
                color: root.colPrimary
                transform: Rotation { origin.x: 9 * root.u; origin.y: 62 * root.u - 9 * root.u; angle: 305 }
            }
            Rectangle { // Minute hand
                x: parent.width / 2 - width / 2
                y: parent.height / 2 - height + width / 2
                width: 10 * root.u
                height: 88 * root.u
                radius: width / 2
                color: root.colOn
                transform: Rotation { origin.x: 5 * root.u; origin.y: 88 * root.u - 5 * root.u; angle: 60 }
            }
            Rectangle {
                anchors.centerIn: parent
                width: 12 * root.u
                height: width
                radius: width / 2
                color: root.colOn
            }
        }
    }
    Component {
        id: digitalClock
        StyledText {
            readonly property var digitalConfig: parent?.config?.digital ?? ({})
            text: digitalConfig.vertical ? "11\n07" : "11:07"
            horizontalAlignment: Text.AlignHCenter
            lineHeight: 0.8
            font.pixelSize: (digitalConfig.font?.size ?? 90) * root.u * 1.1
            font.weight: digitalConfig.font?.weight ?? 350
            color: "white"
            style: Text.Raised
            styleColor: "#40000000"
        }
    }
    Component {
        id: calendarCard
        Card {
            width: 250 * root.u
            height: 220 * root.u
            Grid {
                anchors.centerIn: parent
                columns: 7
                spacing: 9 * root.u
                Repeater {
                    model: 35
                    Rectangle {
                        required property int index
                        width: 20 * root.u
                        height: width
                        radius: width / 2
                        color: index === 19 ? root.colPrimary : ColorUtils.applyAlpha(root.colOn, index < 3 || index > 31 ? 0.15 : 0.45)
                    }
                }
            }
        }
    }
    Component {
        id: monitorCard
        Card {
            width: 270 * root.u
            height: 200 * root.u
            Column {
                anchors.centerIn: parent
                spacing: 20 * root.u
                Repeater {
                    model: [0.35, 0.62, 0.48, 0.8]
                    Rectangle {
                        required property real modelData
                        width: 220 * root.u
                        height: 14 * root.u
                        radius: height / 2
                        color: ColorUtils.applyAlpha(root.colOn, 0.18)
                        Rectangle {
                            width: parent.width * parent.modelData
                            height: parent.height
                            radius: height / 2
                            color: root.colPrimary
                        }
                    }
                }
            }
        }
    }
    Component {
        id: weatherCard
        Card {
            width: 230 * root.u
            height: 110 * root.u
            Row {
                anchors.centerIn: parent
                spacing: 14 * root.u
                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "partly_cloudy_day"
                    iconSize: 56 * root.u
                    fill: 1
                    color: root.colPrimary
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "5°"
                    font.pixelSize: 52 * root.u
                    color: root.colOn
                }
            }
        }
    }
    Component {
        id: mediaCard
        Card {
            width: 300 * root.u
            height: 110 * root.u
            Rectangle {
                id: albumArt
                anchors.left: parent.left
                anchors.leftMargin: 16 * root.u
                anchors.verticalCenter: parent.verticalCenter
                width: 78 * root.u
                height: width
                radius: 12 * root.u
                color: root.colPrimary
            }
            Column {
                anchors.left: albumArt.right
                anchors.leftMargin: 16 * root.u
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12 * root.u
                Repeater {
                    model: [150, 100, 170]
                    Rectangle {
                        required property int modelData
                        required property int index
                        width: modelData * root.u
                        height: (index === 0 ? 16 : 11) * root.u
                        radius: height / 2
                        color: index === 2 ? root.colPrimary : ColorUtils.applyAlpha(root.colOn, index === 0 ? 0.85 : 0.45)
                    }
                }
            }
        }
    }
    Component {
        id: noteCard
        Card {
            width: 230 * root.u
            height: 150 * root.u
            Column {
                anchors.centerIn: parent
                spacing: 14 * root.u
                Repeater {
                    model: [170, 190, 120, 160]
                    Rectangle {
                        required property int modelData
                        required property int index
                        width: modelData * root.u
                        height: (index === 0 ? 16 : 10) * root.u
                        radius: height / 2
                        color: ColorUtils.applyAlpha(index === 0 ? root.colPrimary : root.colOn, index === 0 ? 1 : 0.45)
                    }
                }
            }
        }
    }
}
