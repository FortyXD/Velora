pragma ComponentBehavior: Bound
import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.ii.bar.layout
import qs.modules.ii.dock
import qs.modules.settings.preview

Item {
    id: root
    required property MonitorFrame monitor
    property var preset: null
    property var categories: null
    property bool showBackdrop: true
    property bool moving: false
    property bool populated: true
    property bool animateBar: false
    property int workspace: 0
    property real widgetOffsetX: 0
    property real widgetOffsetY: 0

    function part(name) { return !categories || categories.includes(name) ? preset?.[name] : null; }

    // Match Config.applyPatch without writing to either the current options or the preset.
    function projected(current, patch) {
        if (!patch) return current;
        const result = ObjectUtils.toPlainObject(current);
        for (const key of Object.keys(patch)) {
            if (!(key in current)) continue;
            const child = current[key], value = patch[key];
            result[key] = child && typeof child === "object" && "objectName" in child
                && value !== null && typeof value === "object" && !Array.isArray(value)
                ? projected(child, value) : value;
        }
        return result;
    }
    readonly property var bar: projected(Config.options.bar, part("bar")?.config?.bar)
    readonly property var barStyle: bar.style
    readonly property bool vertical: bar.vertical
    readonly property var dock: projected(Config.options.dock, part("dockWidgets")?.config?.dock)
    readonly property var widgets: projected(Config.options.background.widgets, part("dockWidgets")?.config?.background?.widgets)
    readonly property var theme: part("theme")
    readonly property var motion: part("wallpaperAnimations")
    readonly property string wallpaper: motion?.wallpaper ?? ""
    readonly property var shader: motion?.config?.background?.shaderWallpaper
    readonly property bool changesBackdrop: !!wallpaper || !!shader
    readonly property string poster: motion ? Presets.previewOf(preset) ||
        (Presets.isRemote(wallpaper) && !FileUtils.isVideoPath(wallpaper) ? wallpaper : "") : ""
    property string placementPicture: {
        if (poster) return Presets.isRemote(poster) ? OnlineWallpapers.thumbnailDir + "/" + Qt.md5(poster) : FileUtils.trimFileProtocol(poster);
        if (wallpaper.startsWith("shader:")) return ShaderWallpaper.framePath(wallpaper.slice(7));
        if (wallpaper) return "";
        const bg = Config.options.background;
        return FileUtils.trimFileProtocol(FileUtils.isVideoPath(bg.wallpaperPath) ? bg.thumbnailPath : bg.wallpaperPath);
    }
    readonly property real screenScale: width / monitor.logicalWidth
    readonly property bool backdropReady: !showBackdrop || !!backdrop.item?.settled
    readonly property bool backdropAvailable: !!backdrop.item && !backdrop.item.unavailable
    readonly property bool widgetsSettled: !!surface.item?.widgetsSettled
    readonly property PresetColors sceneColors: PresetColors { theme: root.theme; barStyle: root.barStyle }

    Loader {
        id: backdrop
        anchors.fill: parent
        active: root.showBackdrop
        sourceComponent: WallpaperPreviewMedia {
            active: root.moving
            picture: FileUtils.trimFileProtocol(root.poster) || (root.wallpaper ? "" : currentPicture)
            video: root.motion ? FileUtils.trimFileProtocol(Presets.previewVideoOf(root.preset)) : ""
            playVideo: !!video
            shaderName: root.wallpaper.startsWith("shader:") ? root.wallpaper.slice(7)
                : root.wallpaper ? "" : root.shader?.name ?? (ShaderWallpaper.active ? ShaderWallpaper.name : "")
            shaderColors: root.shader?.colors ?? Config.options.background.shaderWallpaper.colors
            speed: root.shader?.speed ?? Config.options.background.shaderWallpaper.speed
            fps: root.shader?.fps ?? Config.options.background.shaderWallpaper.fps
            zoom: Config.options.background.parallax.workspaceZoom
        }
    }
    Loader {
        id: surface
        objectName: "desktopSurface"
        width: root.monitor.logicalWidth
        height: root.monitor.logicalHeight
        scale: root.screenScale
        transformOrigin: Item.TopLeft
        active: root.populated
        enabled: false
        sourceComponent: Item {
            readonly property bool widgetsSettled: desktopWidgets.settled
            DesktopWidgetLayer {
                id: desktopWidgets
                width: parent.width; height: parent.height
                x: root.widgetOffsetX / (root.screenScale || 1)
                y: root.widgetOffsetY / (root.screenScale || 1)
                settings: root.widgets
                colors: root.theme ? root.sceneColors : Appearance.colors
                wallpaper: root.placementPicture
            }
            BarLayoutView {
                id: panel
                objectName: "desktopPreviewBar"
                screen: root.monitor.output
                preview: true
                previewWorkspace: root.workspace
                barOptions: root.bar
                barColors: root.sceneColors
                vertical: root.vertical
                layoutData: vertical ? BarLayout.normalize(root.bar.verticalLayout, BarLayoutDefaults.vertical)
                    : BarLayout.normalize(root.bar.layout, BarLayoutDefaults.horizontal)
                readonly property real depth: thickness + (barOptions.cornerStyle === 1 || barOptions.style.islands ? 2 * floatMargin : 0)
                x: vertical && barOptions.bottom ? parent.width - width : 0
                y: !vertical && barOptions.bottom ? parent.height - height : 0
                width: vertical ? depth : parent.width
                height: vertical ? parent.height : depth
                visible: !root.bar.screenList?.length || root.bar.screenList.includes(root.monitor.output?.name ?? "")
                property real entrance: 0
                transform: Translate {
                    x: panel.vertical ? panel.entrance * panel.depth * (root.bar.bottom ? 1 : -1) : 0
                    y: panel.vertical ? 0 : panel.entrance * panel.depth * (root.bar.bottom ? 1 : -1)
                }
                onVerticalChanged: if (root.animateBar) enter.restart()
                NumberAnimation { id: enter; target: panel; property: "entrance"; from: 1; to: 0; duration: Appearance.scaledDuration(250); easing.type: Easing.OutCubic }
            }
            Loader {
                anchors.fill: parent
                active: root.dock.enable && !(root.bar.bottom && !root.vertical)
                sourceComponent: DockShelf {
                    objectName: "desktopPreviewDock"
                    colors: root.theme ? root.sceneColors : Appearance.colors
                    dock: DockContext { options: root.dock }
                }
            }
        }
    }
}
