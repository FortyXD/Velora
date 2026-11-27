pragma ComponentBehavior: Bound
import QtQuick

// Instantiate the desktop's own widgets in monitor coordinates. Automatic positioning uses the
// same wallpaper analysis and obstacle order as the shell, including for a candidate preset.
Item {
    id: root
    required property var settings
    required property var colors
    required property string wallpaper
    readonly property bool settled: {
        for (const host of children) {
            if (!host.shown) continue;
            const widget = host.item;
            if (!widget || (wallpaper && widget.placementStrategy !== "free" && widget.analysisResult?.path !== wallpaper)) return false;
        }
        return true;
    }
    readonly property var entries: [
        ["clock", "clock/ClockWidget"], ["weather", settings.weather.style === "card" ? "weather/WeatherCardWidget" : "weather/WeatherWidget"],
        ["systemMonitor", "systemMonitor/SystemMonitorWidget"], ["media", "media/MediaWidget"],
        ["calendar", "calendar/CalendarDesktopWidget"], ["countdown", "countdown/CountdownWidget"],
        ["note", "note/NoteWidget"], ["pomodoro", "pomodoro/PomodoroDesktopWidget"]
    ]
    Repeater {
        model: root.entries
        delegate: Loader {
            id: host
            required property var modelData
            readonly property bool shown: !!root.settings[modelData[0]].enable
            readonly property url widgetFile: Qt.resolvedUrl("../../ii/background/widgets/" + modelData[1] + ".qml")
            active: shown
            asynchronous: true
            onWidgetFileChanged: setSource(widgetFile, {
                objectName: "desktopWidget-" + modelData[0],
                preview: true, placementCanvas: root,
                screenWidth: Qt.binding(() => root.width), screenHeight: Qt.binding(() => root.height),
                scaledScreenWidth: Qt.binding(() => root.width), scaledScreenHeight: Qt.binding(() => root.height),
                wallpaperScale: 1, wallpaperPath: Qt.binding(() => root.wallpaper),
                widgetSettings: Qt.binding(() => root.settings), widgetColors: Qt.binding(() => root.colors)
            })
        }
    }
}
