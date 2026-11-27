pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: root
    bottomContentPadding: 24

    property var updateStatus: ({})
    property var systemDisk: null
    readonly property var update: {
        const s = root.updateStatus;
        if (s.error) return { icon: "warning", text: Translation.tr("Couldn't check for updates"), detail: String(s.error) };
        const stamp = new Date(s.checked_at);
        const checked = s.checked_at && !isNaN(stamp.getTime())
            ? Translation.tr("Checked %1").arg(stamp.toLocaleString(Qt.locale(Translation.languageCode), Locale.ShortFormat)) : "";
        if (s.diverged || (s.available && s.dirty))
            return { icon: "pause_circle", text: Translation.tr("Updates paused"), detail: checked };
        if (s.installation_pending && s.behind === 0)
            return { icon: "download", text: Translation.tr("Finish update"), detail: checked };
        if (s.available) return { icon: "download", text: s.latest_version
            ? Translation.tr("Version %1 available").arg(s.latest_version) : Translation.tr("Update available"), detail: checked };
        return s.checked_at ? { icon: "check_circle", text: Translation.tr("Up to date"), detail: checked }
            : { icon: "schedule", text: Translation.tr("Not checked yet"), detail: "" };
    }

    function diskAmount(bytes, unit) {
        return (bytes / unit).toLocaleString(Qt.locale(Translation.languageCode), "f", unit === 1e12 ? 2 : 1);
    }

    FileView {
        path: `${Quickshell.env("XDG_STATE_HOME") || `${FileUtils.trimFileProtocol(Directories.home)}/.local/state`}/velora/update.json`
        watchChanges: true
        onFileChanged: reload()
        onLoadFailed: error => root.updateStatus = error === FileViewError.FileNotFound ? {} : { error: Translation.tr("Could not read update status") }
        onLoaded: {
            try { root.updateStatus = JSON.parse(text()) ?? {}; }
            catch (error) { root.updateStatus = { error: Translation.tr("Could not read update status") }; }
        }
    }

    Process {
        id: diskUsage
        command: ["df", "-B1", "--output=size,used,avail", "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [size, used, avail] = (text.trim().split("\n")[1] ?? "").trim().split(/\s+/).map(Number);
                root.systemDisk = size > 0 && used >= 0 && avail >= 0 ? { size, used, avail } : null;
            }
        }
    }
    Component.onCompleted: if (pageShown) diskUsage.running = true
    onPageShownChanged: if (pageShown) diskUsage.running = true

    component PageAction: SettingsAction {
        id: action
        required property string pageKey
        readonly property var entry: (ApplicationWindow.window?.pages ?? []).find(page => page.key === action.pageKey)
        property string title: entry?.name ?? ""
        property string description: ""
        readonly property string buttonIcon: entry?.icon ?? ""
        readonly property bool settingsSearchable: true
        readonly property string searchText: [title, entry?.name, description].join(" ")
        objectName: "general-" + pageKey
        text: title
        Accessible.description: description
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        buttonRadius: Appearance.rounding.normal
        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        onClicked: ApplicationWindow.window?.openPage(pageKey)
    }

    PageAction {
        id: identity
        pageKey: "about"
        title: Translation.tr("About this computer")
        description: [SystemInfo.distroName, root.updateStatus.current_version].filter(Boolean).join(" · ")
        padding: 0
        implicitHeight: Math.max(144, identityText.implicitHeight + 36)
        contentItem: Item {
            Item {
                id: art
                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                width: Math.min(parent.width * 0.42, 300)
                readonly property real cut: Math.min(width * 0.42, height * 0.58)
                readonly property real corner: identity.buttonRadius
                readonly property string wallpaper: Config.options.background.wallpaperPath
                readonly property string still: FileUtils.isVideoPath(wallpaper) ? Config.options.background.thumbnailPath : wallpaper

                Canvas {
                    id: artwork
                    anchors.fill: parent
                    readonly property color backing: Appearance.colors.colPrimaryContainer
                    readonly property string picture: root.pageShown && art.still ? Qt.resolvedUrl(art.still).toString() : ""
                    property string requestedSource: ""
                    property size imageSize: Qt.size(0, 0)
                    onPictureChanged: {
                        if (requestedSource) unloadImage(requestedSource);
                        imageSize = Qt.size(0, 0);
                        requestedSource = picture;
                        if (picture) loadImage(picture, Qt.size(680, 420));
                        requestPaint();
                    }
                    onImageLoaded: requestPaint()
                    onBackingChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d"), w = width, h = height, r = art.corner;
                        if (!ctx || w <= 0 || h <= 0) return;
                        if (picture && imageSize.width === 0 && isImageLoaded(picture)) {
                            const image = ctx.createImageData(picture);
                            if (image) imageSize = Qt.size(image.width, image.height);
                        }
                        ctx.clearRect(0, 0, w, h);
                        ctx.save();
                        ctx.beginPath();
                        ctx.moveTo(art.cut, 0);
                        ctx.lineTo(w - r, 0);
                        ctx.quadraticCurveTo(w, 0, w, r);
                        ctx.lineTo(w, h - r);
                        ctx.quadraticCurveTo(w, h, w - r, h);
                        ctx.lineTo(0, h);
                        ctx.closePath();
                        ctx.clip();
                        ctx.fillStyle = backing;
                        ctx.fillRect(0, 0, w, h);
                        if (imageSize.width > 0 && imageSize.height > 0) {
                            const scale = Math.max(w / imageSize.width, h / imageSize.height);
                            const dw = imageSize.width * scale, dh = imageSize.height * scale;
                            ctx.drawImage(picture, (w - dw) / 2, (h - dh) / 2, dw, dh);
                            const shade = ctx.createLinearGradient(0, 0, 0, h);
                            shade.addColorStop(0, "transparent");
                            shade.addColorStop(1, "rgba(0,0,0,0.48)");
                            ctx.fillStyle = shade;
                            ctx.fillRect(0, 0, w, h);
                        }
                        ctx.restore();
                    }
                }
                VeloraLogo {
                    anchors { right: parent.right; bottom: parent.bottom; margins: 19 }
                    size: 34
                    color: artwork.imageSize.width > 0 ? "white" : Appearance.colors.colOnPrimaryContainer
                }
            }
            ColumnLayout {
                id: identityText
                anchors { left: parent.left; right: art.left; verticalCenter: parent.verticalCenter; leftMargin: 24 }
                spacing: 3
                StyledText {
                    text: "Velora"
                    font.family: Appearance.font.family.title
                    font.pixelSize: Appearance.font.pixelSize.title + 9
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    Layout.fillWidth: true
                    text: identity.description
                    wrapMode: Text.Wrap
                    color: Appearance.colors.colSubtext
                }
                RowLayout {
                    Layout.topMargin: 9
                    spacing: 6
                    MaterialSymbol { text: "info"; iconSize: 17; color: Appearance.colors.colPrimary }
                    StyledText {
                        Layout.maximumWidth: Math.max(0, identityText.width - 50)
                        text: identity.title
                        wrapMode: Text.Wrap
                        color: Appearance.colors.colPrimary
                        font.pixelSize: Appearance.font.pixelSize.smallie
                    }
                    MaterialSymbol { text: "chevron_right"; iconSize: 16; color: Appearance.colors.colPrimary }
                }
            }
        }
    }

    component Metric: PageAction {
        id: metric
        required property string value
        property string detail: ""
        property bool meter: false
        property string statusIcon: ""
        property color ink: Appearance.colors.colOnLayer2
        description: [value, detail].filter(Boolean).join(" · ")
        Layout.preferredWidth: 1
        Layout.fillHeight: true
        horizontalPadding: 18
        verticalPadding: 15
        implicitHeight: Math.max(112, contentItem.implicitHeight + 30)
        contentItem: ColumnLayout {
            spacing: 6
            RowLayout {
                spacing: 8
                MaterialSymbol { text: metric.buttonIcon; iconSize: 20; color: Appearance.colors.colSubtext }
                StyledText {
                    Layout.fillWidth: true
                    text: metric.title
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    wrapMode: Text.Wrap
                }
                MaterialSymbol { text: "chevron_right"; iconSize: 17; color: Appearance.colors.colSubtext }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 7
                MaterialSymbol { visible: !!metric.statusIcon; text: metric.statusIcon; iconSize: 22; color: metric.ink }
                StyledText {
                    Layout.fillWidth: true
                    text: metric.value
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.DemiBold
                    color: metric.ink
                }
            }
            Rectangle {
                visible: metric.meter && !!root.systemDisk
                Layout.fillWidth: true
                implicitHeight: 5
                radius: height / 2
                color: Appearance.colors.colSecondaryContainer
                Rectangle {
                    height: parent.height
                    radius: height / 2
                    property real fraction: root.pageShown && root.systemDisk ? Math.min(1, root.systemDisk.used / root.systemDisk.size) : 0
                    width: parent.width * fraction
                    color: Appearance.colors.colPrimary
                    Behavior on fraction { NumberAnimation { duration: Appearance.scaledDuration(240); easing.type: Easing.OutCubic } }
                }
            }
            StyledText {
                visible: !!metric.detail
                Layout.fillWidth: true
                text: metric.detail
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: width >= 660 ? 2 : 1
        uniformCellWidths: true
        columnSpacing: 12
        rowSpacing: 10
        Metric {
            pageKey: "storage"
            meter: true
            value: {
                const disk = root.systemDisk;
                if (!disk) return Translation.tr("Storage unavailable");
                const unit = disk.size >= 1e12 ? 1e12 : 1e9;
                const format = unit === 1e12 ? Translation.tr("%1 TB free of %2 TB") : Translation.tr("%1 GB free of %2 GB");
                return format.arg(root.diskAmount(disk.avail, unit)).arg(root.diskAmount(disk.size, unit));
            }
        }
        Metric {
            pageKey: "updates"
            statusIcon: root.update.icon
            value: root.update.text
            detail: root.update.detail
            ink: root.updateStatus.error ? Appearance.colors.colError : root.updateStatus.available ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
        }
    }

    component PageLink: ConfigNavRow {
        id: link
        required property string pageKey
        readonly property var entry: (ApplicationWindow.window?.pages ?? []).find(page => page.key === link.pageKey)
        objectName: "general-" + pageKey
        buttonIcon: entry?.icon ?? ""
        title: entry?.name ?? ""
        Accessible.name: title
        Accessible.description: valueText
        onClicked: ApplicationWindow.window?.openPage(pageKey)
    }

    ContentSection {
        title: ""
        PageLink { pageKey: "datetime"; valueText: `${DateTime.time} · ${DateTime.shortDate}` }
        PageLink { pageKey: "language"; buttonIcon: "translate"; valueText: Translation.languageNames[Translation.languageCode] ?? Translation.languageCode }
        PageLink { pageKey: "apps" }
        PageLink { pageKey: "shortcuts"; title: Translation.tr("Keyboard Shortcuts"); buttonIcon: "keyboard_command_key" }
    }
    GeneralQuickSettings { objectName: "generalQuickSettings" }
}
