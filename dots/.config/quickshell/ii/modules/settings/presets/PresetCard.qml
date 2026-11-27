pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.settings
import qs.modules.settings.preview

SettingsAction {
    id: root
    required property var preset
    required property bool pageShown
    required property PresetCoverCache coverCache
    readonly property var categories: Presets.categoriesOf(preset)
    property var viewport
    readonly property bool onScreen: {
        if (!root.visible || !root.pageShown || !viewport || !viewport.contentHeight) return false;
        const top = root.mapToItem(viewport.contentItem, 0, 0).y;
        return top + root.height > viewport.contentY - 32 && top < viewport.contentY + viewport.height + 32;
    }
    readonly property string poster: Presets.previewOf(preset) ||
        (Presets.isRemote(preset.wallpaperAnimations?.wallpaper ?? "") && !Presets.isLive(preset) ? preset.wallpaperAnimations.wallpaper : "")
    readonly property bool remotePoster: Presets.isRemote(poster)
    readonly property string currentStill: ShaderWallpaper.active ? ShaderWallpaper.framePath(ShaderWallpaper.name)
        : FileUtils.isVideoPath(Config.options.background.wallpaperPath) ? Config.options.background.thumbnailPath : Config.options.background.wallpaperPath
    readonly property string wallpaper: preset.wallpaperAnimations?.wallpaper ?? ""
    readonly property string shader: wallpaper.startsWith("shader:") ? wallpaper.slice(7) : ""
    readonly property string coverSource: FileUtils.fileUrl(FileUtils.trimFileProtocol((!remotePoster && poster)
        || (shader && ShaderWallpaper.framePath(shader)) || currentStill || Directories.defaultWallpaper))
    readonly property string description: Translation.tr(preset.description ?? "")
    readonly property bool settingsSearchable: true
    readonly property string searchText: text + " " + description
    readonly property string stillKey: coverCache.key(preset, cover)
    readonly property var captured: coverCache.frames.get(stillKey)
    readonly property string bundledLayer: preset.kind === "builtin" ? preset.id
        : (preset.bar?.config?.bar?.vertical ?? Config.options.bar.vertical) ? "bar-vertical" : "folis"
    signal quickApply()

    objectName: "presetCard-" + preset.id
    text: Translation.tr(preset.name)
    Accessible.description: description
    Layout.fillWidth: true
    Layout.minimumWidth: 0
    Layout.preferredWidth: 1
    Layout.alignment: Qt.AlignTop
    padding: 8
    implicitHeight: contentItem.implicitHeight + 2 * padding
    buttonRadius: Appearance.rounding.normal
    colBackground: Appearance.colors.colLayer2
    colBackgroundHover: Appearance.colors.colLayer2Hover

    contentItem: ColumnLayout {
        spacing: 7
        MonitorFrame {
            id: cover
            Layout.fillWidth: true
            readonly property real radius: Appearance.rounding.small
            Rectangle { anchors.fill: parent; color: Appearance.colors.colLayer3; radius: cover.radius }
            layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
            layer.effect: OpacityMask {
                maskSource: Rectangle { width: cover.width; height: cover.height; radius: cover.radius }
            }
            Image {
                id: coverImage
                objectName: "presetCover"
                anchors.centerIn: parent
                width: parent.width * Math.max(1, Config.options.background.parallax.workspaceZoom)
                height: parent.height * Math.max(1, Config.options.background.parallax.workspaceZoom)
                property bool fallback: false
                readonly property string wanted: root.onScreen ? root.coverSource : ""
                onWantedChanged: fallback = false
                onStatusChanged: if (status === Image.Error) fallback = true
                source: !wanted || root.captured ? "" : fallback ? FileUtils.fileUrl(Directories.defaultWallpaper) : wanted
                sourceSize: Qt.size(640, 0)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true; autoTransform: true
            }
            Loader {
                anchors.fill: parent
                active: root.onScreen && root.remotePoster && !root.captured
                sourceComponent: RemoteImage { url: root.poster; visible: ready }
            }
            Image {
                id: interfaceLayer
                objectName: "presetCoverInterface"
                anchors.fill: parent
                property bool useDefault: false
                readonly property string asset: Qt.resolvedUrl("../../../assets/preset-covers/"
                    + (cover.aspect >= 1 ? "landscape/" : "portrait/") + (useDefault ? "folis" : root.bundledLayer) + ".png")
                onStatusChanged: if (status === Image.Error && !root.captured) useDefault = true
                source: !root.onScreen ? "" : root.captured?.url ?? asset
                asynchronous: true
                retainWhileLoading: true
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 5
            Layout.rightMargin: 4
            spacing: 6
            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 2
                StyledText {
                    Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
                    text: root.text; font.pixelSize: Appearance.font.pixelSize.normal; font.weight: Font.DemiBold
                }
                StyledText {
                    visible: root.description.length > 0
                    Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
                    text: root.description; color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smaller
                }
                StyledText {
                    visible: !!root.preset.isDefault || root.preset.kind === "user"
                    text: root.preset.isDefault ? Translation.tr("Default") : Translation.tr("Yours")
                    color: Appearance.colors.colPrimary; font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
            SettingsToolButton {
                objectName: "quickApply-" + root.preset.id
                visible: root.categories.length === 1
                materialIcon: "check"
                mainText: Translation.tr("Apply")
                onClicked: root.quickApply()
            }
            MaterialSymbol {
                visible: root.categories.length !== 1
                text: "chevron_right"; iconSize: 19; color: Appearance.colors.colSubtext
            }
        }
    }
}
