pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QtQml.Models
import Qt5Compat.GraphicalEffects
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings
import qs.services

ColumnLayout {
    id: root
    required property bool pageShown
    property string chosenKey: ""
    signal browse()
    signal applyRequested(string path)
    signal shaderRequested(string name, var colors)
    signal videoRequested()
    signal previewSelected()
    signal randomRequested(string provider)

    readonly property string currentKey: Wallpapers.currentWallpaper?.key ?? ""
    readonly property var collection: {
        if (!pageShown) return [];
        const items = [], seen = new Set();
        for (const preset of Presets.presets) {
            if (preset.kind !== "builtin" || Presets.isLive(preset)) continue;
            const path = FileUtils.localPath(Presets.wallpaperFile(preset));
            if (!path || seen.has(path)) continue;
            seen.add(path);
            items.push({id: preset.id, path, name: preset.name, author: preset.credits?.author ?? ""});
        }
        return items;
    }
    readonly property var recent: {
        if (!pageShown) return [];
        const resolved = pathLookup.object?.resolved ?? {};
        const items = [], seen = new Set();
        for (const entry of Wallpapers.recentWallpapers) {
            const real = resolved[entry.path];
            if (entry.path?.startsWith("/") && entry.key !== currentKey && !real) continue;
            const identity = real || entry.key;
            if (seen.has(identity)) continue;
            seen.add(identity);
            const art = collection.find(item => item.path === entry.path || (real && resolved[item.path] === real));
            const shader = ShaderWallpaper.shader(entry.shader);
            const name = shader?.name ?? (art ? Translation.tr(art.name) : FileUtils.trimFileExt(FileUtils.fileNameForPath(entry.path)).replace(/[_-]+/g, " "));
            items.push(Object.assign({}, entry, {id: art?.id ?? entry.key, name, author: art?.author ?? "", collectionPath: art?.path}));
            if (items.length === 3) break;
        }
        return items;
    }
    readonly property var currentEntry: recent.find(entry => entry.key === currentKey) ?? null
    readonly property var chosen: {
        const previous = recent.find(entry => entry.key === chosenKey);
        if (previous) return previous;
        const shader = chosenKey.startsWith("shader:") ? ShaderWallpaper.shader(chosenKey.slice(7)) : null;
        if (!shader) return null;
        const colors = ShaderWallpaper.active && !Config.options.background.shaderWallpaper.colors.length ? [] : shader.colors;
        return {key: chosenKey, name: shader.name, path: "", shader: shader.id, colors, poster: ShaderWallpaper.posterPath(shader.id)};
    }
    readonly property var displayed: chosen ?? currentEntry
    readonly property string displayTitle: displayed?.name || Translation.tr("Wallpaper")
    readonly property bool onlineRandom: Config.options.policies.weeb === 1
    readonly property var randomOptions: (onlineRandom ? [
        {value: "wallhaven", displayName: "Wallhaven"}, {value: "konachan", displayName: "Konachan"}
    ] : []).concat([{value: "collection", displayName: Translation.tr("Local wallpapers")}])
    property string lastSource: ""
    readonly property var randomSource: randomOptions.find(option => option.value === lastSource) ?? randomOptions[0]
    readonly property bool sideRail: width >= 560 && panorama.monitorWidth / panorama.monitorHeight < 2.4
    readonly property real railWidth: Math.min(170, Math.max(115, width * 0.205))
    readonly property bool settingsSearchable: true
    readonly property string title: Translation.tr("Current wallpaper")
    readonly property string searchText: [title, displayTitle, Translation.tr("Choose wallpaper"), Translation.tr("Recent wallpapers"),
        Translation.tr("Random wallpaper"), ...randomOptions.map(option => option.displayName)].join(" ")
    objectName: "wallpaperGallery"
    Layout.fillWidth: true
    spacing: 14

    readonly property var otherPictures: collection.filter(entry => entry.path !== currentEntry?.collectionPath && entry.path !== currentKey)
    function shuffle(source) {
        if (!randomOptions.some(option => option.value === source)) return;
        lastSource = source;
        chosenKey = "";
        if (source !== "collection") { randomRequested(source); return; }
        const personal = Wallpapers.filesInCurrentFolder().filter(path => path !== currentKey && path !== currentEntry?.collectionPath);
        const choices = personal.length ? personal : otherPictures.map(entry => entry.path);
        if (choices.length) applyRequested(choices[Math.floor(Math.random() * choices.length)]);
    }
    onCurrentKeyChanged: chosenKey = ""
    onPageShownChanged: {
        if (pageShown) Wallpapers.refreshHistory();
        else chosenKey = "";
    }

    // Resolve aliases once per set of files, and omit unavailable past pictures.
    Instantiator {
        id: pathLookup
        readonly property string files: root.pageShown ? JSON.stringify([...new Set([
            ...Wallpapers.recentWallpapers.map(entry => entry.path), ...root.collection.map(entry => entry.path)
        ].filter(path => path?.startsWith("/")))]) : "[]"
        model: files !== "[]" ? [files] : []
        delegate: Process {
            id: lookup
            required property string modelData
            readonly property var paths: JSON.parse(modelData)
            property var resolved: ({})
            command: ["sh", "-c", "for path do if [ -f \"$path\" ]; then realpath -zm -- \"$path\"; else printf '\\0'; fi; done", "recent-wallpapers", ...paths]
            running: true
            stdout: StdioCollector {
                onStreamFinished: {
                    const values = text.split("\0"), mapping = {};
                    lookup.paths.forEach((path, index) => mapping[path] = values[index]);
                    lookup.resolved = mapping;
                }
            }
        }
    }

    component Action: SettingsAction {
        id: action
        required property string materialIcon
        property bool primary: false
        property bool iconOnly: false
        readonly property color ink: primary ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
        implicitHeight: 38
        horizontalPadding: iconOnly ? 8 : 13
        verticalPadding: 0
        buttonRadius: Appearance.rounding.small
        colBackground: primary ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
        colBackgroundHover: primary ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer2Hover
        colRipple: primary ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer2Active
        contentItem: RowLayout {
            spacing: 6
            MaterialSymbol { text: action.materialIcon; iconSize: 19; color: action.ink }
            StyledText {
                visible: !action.iconOnly
                text: action.text; color: action.ink
                font.pixelSize: Appearance.font.pixelSize.small; font.weight: Font.Medium
            }
        }
    }

    component PhotoTile: SettingsAction {
        id: tile
        required property bool selected
        required property string picture
        property string fallbackPicture: ""
        property string missingIcon: "image"
        property string mediaIcon: ""
        property real heightRatio: 0.485
        property real maximumPhotoHeight: 88
        Accessible.checkable: true; Accessible.checked: selected
        Layout.fillWidth: true; Layout.minimumWidth: 0; Layout.preferredWidth: 1
        implicitHeight: contentItem.implicitHeight + 2 * padding
        padding: 3; buttonRadius: Appearance.rounding.small
        colBackground: selected ? Appearance.colors.colSecondaryContainer : "transparent"
        colBackgroundHover: selected ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer2Hover
        contentItem: ColumnLayout {
            spacing: 3
            Rectangle {
                id: photo
                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(44, Math.min(tile.maximumPhotoHeight, (tile.width - 6) * tile.heightRatio))
                color: Appearance.colors.colLayer3; radius: 7; clip: true
                layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
                layer.effect: OpacityMask {
                    maskSource: Rectangle { width: photo.width; height: photo.height; radius: photo.radius }
                }
                Image {
                    id: thumbnail
                    anchors.fill: parent
                    source: FileUtils.fileUrl(tile.picture)
                    cache: !tile.fallbackPicture
                    sourceSize: Qt.size(360, 0)
                    fillMode: Image.PreserveAspectCrop; asynchronous: true; autoTransform: true
                }
                Image {
                    anchors.fill: parent
                    visible: !!tile.fallbackPicture && thumbnail.status !== Image.Ready
                    source: visible ? FileUtils.fileUrl(tile.fallbackPicture) : ""
                    fillMode: Image.PreserveAspectCrop; asynchronous: true
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: !tile.fallbackPicture && (thumbnail.status === Image.Error || thumbnail.status === Image.Null)
                    text: tile.missingIcon; iconSize: 22; color: Appearance.colors.colSubtext
                }
                Rectangle {
                    visible: !!tile.mediaIcon
                    anchors { right: parent.right; bottom: parent.bottom; margins: 4 }
                    width: 22; height: 18; radius: 6; color: "#99000000"
                    MaterialSymbol { anchors.centerIn: parent; text: tile.mediaIcon; iconSize: 14; color: "white" }
                }
            }
            RowLayout {
                Layout.fillWidth: true; Layout.leftMargin: 3; Layout.rightMargin: 3
                spacing: 2
                StyledText {
                    Layout.fillWidth: true; Layout.minimumWidth: 0
                    text: tile.text; textFormat: Text.PlainText; elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: tile.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer2
                }
                MaterialSymbol { visible: tile.selected; text: "check"; iconSize: 15; color: Appearance.colors.colOnSecondaryContainer }
            }
        }
    }

    GridLayout {
        Layout.fillWidth: true
        columnSpacing: 12; rowSpacing: 10
        readonly property bool beside: root.width >= actions.preferred + columnSpacing + Math.max(165, Math.min(300, heading.implicitWidth))
        id: header
        ColumnLayout {
            Layout.row: 0; Layout.column: 0
            Layout.fillWidth: true; Layout.minimumWidth: 0; Layout.preferredWidth: 1
            spacing: 1
            StyledText {
                id: heading
                objectName: "wallpaperTitle"
                Layout.fillWidth: true
                text: root.displayTitle; textFormat: Text.PlainText; elide: Text.ElideRight
                color: Appearance.colors.colOnLayer2
                font.pixelSize: 27; font.weight: Font.DemiBold
            }
            StyledText {
                Layout.fillWidth: true
                text: [root.chosen ? Translation.tr("Wallpaper preview") : Translation.tr("Current wallpaper"), root.displayed?.author]
                    .filter(Boolean).join("  ·  ")
                textFormat: Text.PlainText; elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext
            }
        }
        Flow {
            id: actions
            readonly property real preferred: chooseGroup.width + spacing + shuffleGroup.width
            Layout.row: header.beside ? 0 : 1; Layout.column: header.beside ? 1 : 0
            Layout.fillWidth: !header.beside; Layout.preferredWidth: preferred; Layout.minimumWidth: 0
            spacing: 6
            Row {
                id: chooseGroup
                spacing: 2
                Action {
                    id: primaryAction
                    objectName: "wallpaperPrimaryAction"
                    primary: true
                    materialIcon: root.chosen ? "check" : "add_photo_alternate"
                    text: root.chosen ? Translation.tr("Apply") : Translation.tr("Choose wallpaper")
                    Accessible.name: root.chosen ? Translation.tr("Set wallpaper") : text
                    onClicked: {
                        if (!root.chosen) root.browse();
                        else if (root.chosen.shader) root.shaderRequested(root.chosen.shader, root.chosen.colors);
                        else root.applyRequested(root.chosen.path);
                    }
                }
                Action {
                    id: cancel
                    objectName: "wallpaperCancelPreview"
                    visible: !!root.chosen
                    iconOnly: true
                    materialIcon: "close"; text: Translation.tr("Cancel preview")
                    onClicked: root.chosenKey = ""
                    StyledToolTip { text: cancel.text }
                }
            }
            Rectangle {
                id: shuffleGroup
                width: shuffleButtons.implicitWidth; height: 38
                radius: Appearance.rounding.small; color: Appearance.colors.colLayer2
                Row {
                    id: shuffleButtons
                    anchors.centerIn: parent
                    Action {
                        objectName: "wallpaperRandomAction"
                        materialIcon: "shuffle"; text: Translation.tr("Random wallpaper")
                        Accessible.description: root.randomSource.displayName
                        colBackground: "transparent"
                        enabled: root.randomSource.value !== "collection" || root.otherPictures.length > 0
                        onClicked: root.shuffle(root.randomSource.value)
                        StyledToolTip { text: root.randomSource.displayName }
                    }
                    Rectangle {
                        visible: sourceButton.visible
                        anchors.verticalCenter: parent.verticalCenter
                        width: 1; height: 16; color: Appearance.colors.colOutlineVariant
                    }
                    ChoiceDropdown {
                        id: sourceButton
                        objectName: "wallpaperRandomSource"
                        visible: root.randomOptions.length > 1
                        readonly property bool compact: root.width < 445
                        displayText: compact ? "" : currentOption?.displayName ?? ""
                        width: compact ? 32 : implicitWidth
                        height: 38
                        leftPadding: compact ? 3 : 9; rightPadding: compact ? 3 : 6
                        buttonRadius: Appearance.rounding.small
                        colBackground: "transparent"
                        colBackgroundHover: Appearance.colors.colLayer2Hover
                        options: root.randomOptions
                        currentValue: root.randomSource.value
                        popupWidth: 215
                        Accessible.name: Translation.tr("Random wallpaper source") + " · " + root.randomSource.displayName
                        focusPolicy: Qt.StrongFocus
                        Keys.onReturnPressed: openPopup()
                        Keys.onEnterPressed: openPopup()
                        onSelected: value => root.shuffle(value)
                        StyledToolTip { text: sourceButton.Accessible.name }
                    }
                }
            }
        }
    }

    GridLayout {
        Layout.fillWidth: true
        columnSpacing: 16; rowSpacing: 12
        WallpaperPanorama {
            id: panorama
            Layout.row: 0; Layout.column: 0
            Layout.fillWidth: true; Layout.minimumWidth: 0; Layout.preferredWidth: 540
            Layout.alignment: Qt.AlignTop
            pageShown: root.pageShown
            sample: root.chosen
            maxScreenHeight: Math.max(245, Math.min(435, (root.Window.window?.height ?? 780) * 0.52))
        }
        ColumnLayout {
            id: filmstrip
            objectName: "wallpaperFilmstrip"
            visible: root.recent.length > 0
            Layout.row: root.sideRail ? 0 : 1; Layout.column: root.sideRail ? 1 : 0
            Layout.fillWidth: true; Layout.minimumWidth: 0
            Layout.preferredWidth: root.sideRail ? root.railWidth : 1
            Layout.maximumWidth: root.sideRail ? root.railWidth : Infinity
            Layout.alignment: Qt.AlignTop
            spacing: 6
            StyledText {
                Layout.fillWidth: true; Layout.leftMargin: 3
                text: Translation.tr("Recent wallpapers")
                color: Appearance.colors.colOnLayer2; font.pixelSize: Appearance.font.pixelSize.small; font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            GridLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignLeft
                readonly property int slots: root.sideRail ? 1 : filmstrip.width < 275 ? 2 : 3
                readonly property real cellWidth: (filmstrip.width + columnSpacing) / slots - columnSpacing
                Layout.maximumWidth: (cellWidth + columnSpacing) * Math.min(slots, root.recent.length) - columnSpacing
                columns: slots
                uniformCellWidths: true
                columnSpacing: 6; rowSpacing: 5
                Repeater {
                    model: root.recent
                    delegate: PhotoTile {
                        required property var modelData
                        selected: root.displayed?.key === modelData.key
                        objectName: "wallpaperSample-" + modelData.id
                        text: modelData.name
                        picture: modelData.poster ?? ""
                        fallbackPicture: modelData.shader ? ShaderWallpaper.posterPath(modelData.shader) : ""
                        mediaIcon: modelData.shader ? "animation" : FileUtils.isVideoPath(modelData.path) ? "movie" : ""
                        missingIcon: mediaIcon || "hide_image"
                        Accessible.description: modelData.shader ? Translation.tr("Animated wallpaper") : mediaIcon ? Translation.tr("Live wallpaper") : ""
                        onClicked: root.chosenKey = modelData.key === root.currentKey ? "" : modelData.key
                    }
                }
            }
        }
    }

    ColumnLayout {
        id: liveGallery
        objectName: "live"
        readonly property bool settingsSearchable: true
        readonly property string title: Translation.tr("Live wallpapers")
        readonly property string searchText: [title, Translation.tr("Animated wallpaper"), Translation.tr("Choose a video"),
            ...ShaderWallpaper.shaders.map(shader => shader.name)].join(" ")
        Layout.fillWidth: true
        Layout.topMargin: 2
        spacing: 5
        RowLayout {
            Layout.fillWidth: true
            StyledText {
                Layout.fillWidth: true
                text: liveGallery.title
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.normal; font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer2
            }
            Action {
                id: freeze
                visible: ShaderWallpaper.active
                materialIcon: "pause_circle"
                iconOnly: true
                text: Translation.tr("Stop the animation")
                Accessible.description: Translation.tr("Keeps a still picture of it as the wallpaper")
                onClicked: Config.options.background.shaderWallpaper.name = ""
                StyledToolTip { text: freeze.text + " · " + freeze.Accessible.description }
            }
            Action {
                objectName: "wallpaperChooseVideo"
                materialIcon: "video_library"
                text: Translation.tr("Choose a video")
                onClicked: root.videoRequested()
            }
        }
        GridLayout {
            Layout.fillWidth: true
            columns: width >= 490 ? 4 : 2
            uniformCellWidths: true; columnSpacing: 8; rowSpacing: 5
            Repeater {
                model: ShaderWallpaper.shaders
                delegate: PhotoTile {
                    id: shaderTile
                    required property var modelData
                    readonly property string key: "shader:" + modelData.id
                    selected: root.displayed?.key === key
                    objectName: "wallpaperLive-" + modelData.id
                    text: modelData.name
                    Accessible.description: modelData.description
                    picture: root.pageShown ? ShaderWallpaper.posterPath(modelData.id) : ""
                    heightRatio: 9 / 16
                    maximumPhotoHeight: 104
                    onClicked: {
                        root.chosenKey = key === root.currentKey ? "" : key;
                        primaryAction.forceActiveFocus(Qt.OtherFocusReason);
                        root.previewSelected();
                    }
                    StyledToolTip { text: shaderTile.modelData.description }
                }
            }
        }
    }
}
