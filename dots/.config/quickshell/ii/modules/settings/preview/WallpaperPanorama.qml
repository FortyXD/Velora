pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.settings
import qs.modules.settings.presets
import qs.modules.ii.sidebars

ColumnLayout {
    id: root
    objectName: "wallpaperPanorama"
    required property bool pageShown
    property var sample: null
    property real maxScreenHeight: 284
    readonly property alias monitorWidth: frame.logicalWidth
    readonly property alias monitorHeight: frame.logicalHeight
    readonly property var parallax: Config.options.background.parallax
    property int workspace: 1
    property real position: 1
    property int sidebar: 0
    property real sidebarPosition: sidebar
    property bool playing: false
    property bool videoFailed: false
    readonly property bool animate: pageShown && Appearance.animationSpeed > 0
    property bool introSeen: false
    spacing: 4

    function takeControl() {
        introSeen = true;
        drift.stop();
        settle.stop();
    }
    function selectWorkspace(index) {
        takeControl();
        workspace = Math.max(0, Math.min(2, index));
        if (animate && Math.abs(position - workspace) > 0.001) {
            settle.to = workspace;
            settle.start();
        } else position = workspace;
    }
    onAnimateChanged: if (!animate) {
        settle.stop();
        drift.stop();
        if (slideSidebar.running) slideSidebar.complete();
        position = workspace;
    }
    NumberAnimation {
        id: settle
        target: root
        property: "position"
        duration: Appearance.scaledDuration(310)
        easing.type: Easing.OutCubic
    }
    Timer {
        interval: 180
        running: root.animate && root.parallax.enableWorkspace && media.settled && !root.introSeen
        onTriggered: { root.introSeen = true; drift.start(); }
    }
    SequentialAnimation {
        id: drift
        NumberAnimation { target: root; property: "position"; to: 1.85; duration: Appearance.scaledDuration(620); easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "position"; to: 1; duration: Appearance.scaledDuration(720); easing.type: Easing.InOutCubic }
    }
    Behavior on sidebarPosition {
        enabled: root.animate
        NumberAnimation { id: slideSidebar; duration: Appearance.scaledDuration(245); easing.type: Easing.OutCubic }
    }

    MonitorFrame {
        id: frame
        objectName: "panoramaFrame"
        Layout.fillWidth: true
        Layout.maximumWidth: root.maxScreenHeight * aspect
        clip: true
        activeFocusOnTab: true
        Accessible.role: Accessible.Slider
        Accessible.name: Translation.tr("Workspace panorama")
        Accessible.description: Translation.tr("Drag or use the arrow keys to switch workspaces.")
        Accessible.onIncreaseAction: root.selectWorkspace(root.workspace + 1)
        Accessible.onDecreaseAction: root.selectWorkspace(root.workspace - 1)
        Keys.onLeftPressed: root.selectWorkspace(root.workspace - 1)
        Keys.onRightPressed: root.selectWorkspace(root.workspace + 1)
        layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
        layer.effect: OpacityMask {
            maskSource: Rectangle { width: frame.width; height: frame.height; radius: Appearance.rounding.normal }
        }

        WallpaperPreviewMedia {
            id: media
            objectName: "panoramaMedia"
            anchors.fill: parent
            active: root.pageShown
            picture: root.sample ? root.sample.poster : currentPicture
            video: FileUtils.isVideoPath(root.sample ? root.sample.path : Config.options.background.wallpaperPath)
                ? (root.sample ? root.sample.path : Config.options.background.wallpaperPath) : ""
            shaderName: root.sample ? root.sample.shader ?? "" : ShaderWallpaper.active ? ShaderWallpaper.name : ""
            shaderColors: root.sample?.colors ?? Config.options.background.shaderWallpaper.colors
            crossfadePictures: true
            playVideo: root.playing
            zoom: root.parallax.workspaceZoom
            readonly property bool verticalPan: root.parallax.vertical || (root.parallax.autoVertical && portrait)
            readonly property real sidebarOffset: root.parallax.enableSidebar
                ? root.sidebarPosition * zoom / (2 * Math.max(1, Config.options.bar.workspaces.shown)) : 0
            fractionX: (root.parallax.enableWorkspace && !verticalPan ? root.position / 2 : 0.5) + sidebarOffset
            fractionY: root.parallax.enableWorkspace && verticalPan ? root.position / 2 : 0.5
            onMotionAllowedChanged: if (!motionAllowed) root.playing = false
            onVideoChanged: { root.playing = false; root.videoFailed = false; }
            onPlaybackFailed: { root.playing = false; root.videoFailed = true; }
        }

        PresetScene {
            id: desktop
            objectName: "panoramaDesktop"
            anchors.fill: parent
            monitor: frame
            showBackdrop: false
            populated: root.pageShown
            placementPicture: FileUtils.trimFileProtocol(media.picture)
            workspace: Math.round(root.position) + 1
            widgetOffsetX: media.offsetX * root.parallax.widgetsFactor / Math.max(1, media.zoom)
            widgetOffsetY: media.offsetY * root.parallax.widgetsFactor / Math.max(1, media.zoom)
        }

        // The same sidebar parts and margins as the desktop panels, in logical screen coordinates.
        Item {
            width: frame.logicalWidth; height: frame.logicalHeight
            scale: desktop.screenScale
            transformOrigin: Item.TopLeft
            enabled: false
            Repeater {
                model: [-1, 1]
                delegate: Loader {
                    id: panel
                    required property int modelData
                    readonly property real progress: Math.max(0, modelData * root.sidebarPosition)
                    readonly property real gap: Appearance.sizes.hyprlandGapsOut
                    readonly property real panelWidth: modelData < 0 && Config.options.sidebar.left.extendedByDefault
                        ? Appearance.sizes.sidebarWidthExtended : Appearance.sizes.sidebarWidth
                    readonly property real barDepth: desktop.barStyle.thickness > 0 ? desktop.barStyle.thickness : (desktop.vertical ? 46 : 40)
                    active: root.pageShown && progress > 0
                    asynchronous: true
                    width: Math.min(frame.logicalWidth, panelWidth) - gap - Appearance.sizes.elevationMargin
                    height: frame.logicalHeight - 2 * gap - (desktop.vertical ? 0 : barDepth)
                    y: gap + (!desktop.vertical && !desktop.bar.bottom ? barDepth : 0)
                    x: modelData < 0 ? (gap + (desktop.vertical && !desktop.bar.bottom ? barDepth : 0)) * progress - width * (1 - progress)
                        : frame.logicalWidth - (width + gap + (desktop.vertical && desktop.bar.bottom ? barDepth : 0)) * progress
                    sourceComponent: Rectangle {
                        color: Appearance.colors.colLayer0
                        border.color: Appearance.colors.colLayer0Border; border.width: 1
                        radius: Appearance.rounding.screenRounding - panel.gap + 1
                        SidebarPartsColumn {
                            anchors.fill: parent; anchors.margins: 10
                            side: panel.modelData < 0 ? "left" : "right"
                        }
                    }
                }
            }
        }

        HoverHandler { cursorShape: swipe.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor }
        DragHandler {
            id: swipe
            target: null
            yAxis.enabled: false
            property real startPosition
            onActiveChanged: {
                if (active) {
                    root.takeControl();
                    startPosition = root.position;
                    frame.forceActiveFocus(Qt.MouseFocusReason);
                } else root.selectWorkspace(Math.round(root.position));
            }
            onActiveTranslationChanged: if (active)
                root.position = Math.max(0, Math.min(2, startPosition - activeTranslation.x / (frame.width * 0.55)));
        }
        Rectangle {
            anchors.fill: parent; radius: Appearance.rounding.normal
            visible: frame.activeFocus; color: "transparent"; border.width: 2; border.color: Appearance.colors.colPrimary
        }
    }

    component PanelButton: SettingsAction {
        id: button
        required property int side
        objectName: side < 0 ? "panoramaLeftSidebar" : "panoramaRightSidebar"
        implicitWidth: 34; implicitHeight: 30; buttonRadius: 12
        text: side < 0 ? Translation.tr("Left sidebar") : Translation.tr("Right sidebar")
        Accessible.checkable: true
        Accessible.checked: root.sidebar === side
        colBackground: root.sidebar === side ? Appearance.colors.colSecondaryContainer : "transparent"
        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            text: button.side < 0 ? "left_panel_open" : "right_panel_open"
            iconSize: 18
            color: root.sidebar === button.side ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
        }
        onClicked: { root.takeControl(); root.sidebar = root.sidebar === side ? 0 : side; }
        StyledToolTip { text: button.text }
    }
    RowLayout {
        Layout.fillWidth: true
        Layout.maximumWidth: frame.width
        Layout.alignment: Qt.AlignHCenter
        spacing: 5
        StyledText {
            visible: frame.width >= (media.video && !media.hasShader ? 360 : 275)
            Layout.leftMargin: 3
            Layout.fillWidth: true
            color: Appearance.colors.colSubtext
            text: Translation.tr("Workspace %1").arg(Math.round(root.position) + 1)
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
        PanelButton { side: -1 }
        Slider {
            id: scrub
            objectName: "wallpaperWorkspaceSlider"
            Layout.preferredWidth: Math.max(54, Math.min(118, frame.width * 0.24)); implicitHeight: 30
            from: 0; to: 2; stepSize: 0; live: true
            leftPadding: 8; rightPadding: 8
            value: root.position
            Accessible.name: Translation.tr("Workspace panorama")
            Accessible.description: Translation.tr("Drag or use the arrow keys to switch workspaces.")
            onPressedChanged: if (pressed) root.takeControl()
            onMoved: { root.takeControl(); root.position = value; root.workspace = Math.round(value); }
            Keys.onLeftPressed: root.selectWorkspace(Math.max(0, Math.ceil(root.position) - 1))
            Keys.onRightPressed: root.selectWorkspace(Math.min(2, Math.floor(root.position) + 1))
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Home || event.key === Qt.Key_End) {
                    root.selectWorkspace(event.key === Qt.Key_Home ? 0 : 2);
                    event.accepted = true;
                }
            }
            background: Item {
                x: scrub.leftPadding; width: scrub.availableWidth; height: scrub.height
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width; height: 2; radius: 1
                    color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.76)
                }
                Repeater {
                    model: 3
                    Rectangle {
                        required property int index
                        x: index * parent.width / 2 - width / 2; anchors.verticalCenter: parent.verticalCenter
                        width: 5; height: 5; radius: 3; color: Appearance.colors.colOnLayer1
                    }
                }
            }
            handle: Rectangle {
                width: 15; height: 10; radius: 5
                x: scrub.leftPadding + scrub.visualPosition * scrub.availableWidth - width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: Appearance.colors.colOnLayer1
                border.width: scrub.visualFocus ? 2 : 0; border.color: Appearance.colors.colPrimary
            }
            StyledToolTip { text: Translation.tr("Workspace %1").arg(Math.round(root.position) + 1) }
        }
        PanelButton { side: 1 }
        SettingsToolButton {
            objectName: "panoramaPlay"
            visible: !!media.video && !media.hasShader
            enabled: media.motionAllowed
            materialIcon: root.playing ? "pause" : "play_arrow"
            mainText: root.playing ? Translation.tr("Pause") : Translation.tr("Play")
            onClicked: { root.takeControl(); root.videoFailed = false; root.playing = !root.playing; }
        }
    }
    StyledText {
        Layout.fillWidth: true
        visible: root.videoFailed || media.unavailable
        text: root.videoFailed ? Translation.tr("Could not play this preview") : Translation.tr("Wallpaper preview unavailable")
        horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
        color: Appearance.colors.colOnLayer1; font.pixelSize: Appearance.font.pixelSize.smallie
    }
}
