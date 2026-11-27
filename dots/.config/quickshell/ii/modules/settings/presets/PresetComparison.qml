pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.settings.preview

ColumnLayout {
    id: root
    required property var preset
    required property var categories
    required property bool pageShown
    required property PresetCoverCache coverCache
    spacing: 5

    function focusDivider() { divider.forceActiveFocus(Qt.TabFocusReason); }

    readonly property bool allowMotion: pageShown && Appearance.animationSpeed > 0 && !PowerSaving.cutAnimations
    property bool introPending: true
    readonly property bool readyToReveal: pageShown && currentMedia.settled && after.backdropReady
    readonly property string coverKey: preset ? coverCache.key(preset, frame) : ""
    readonly property bool fullSelection: !!preset && categories.length === Presets.categoriesOf(preset).length
    property string attemptedCover: ""
    property var backdropGrab: null

    function grabCandidate(key) {
        if (!pageShown || !fullSelection || key !== coverKey) { backdropGrab = null; return; }
        const width = Math.min(680, Math.ceil(frame.width));
        const size = Qt.size(width, Math.max(1, Math.round(width / frame.aspect)));
        const started = candidate.grabToImage(result => {
            if (!root) return;
            if (root.pageShown && root.fullSelection && root.coverKey === key) root.coverCache.remember(key, result);
            root.backdropGrab = null;
        }, size);
        if (!started) backdropGrab = null;
    }

    // Capture the existing scene only after the user opens it. For a style that keeps
    // the wallpaper, briefly reuse a still of the same background visible underneath.
    Timer {
        interval: 160
        running: root.readyToReveal && (after.showBackdrop ? after.backdropAvailable : !currentMedia.unavailable)
            && after.widgetsSettled && root.fullSelection && !root.introPending
            && !reveal.running && !divider.pressed && root.attemptedCover !== root.coverKey && !root.coverCache.frames.has(root.coverKey)
        onTriggered: {
            const key = root.coverKey;
            root.attemptedCover = key;
            if (after.showBackdrop) root.grabCandidate(key);
            else currentMedia.grabToImage(result => {
                if (root && root.pageShown && root.fullSelection && root.coverKey === key) root.backdropGrab = result;
            });
        }
    }
    onReadyToRevealChanged: if (readyToReveal) Qt.callLater(root.startIntro)
    Component.onCompleted: if (readyToReveal) Qt.callLater(root.startIntro)
    function cancelIntro() {
        introPending = false;
        reveal.stop();
    }
    function startIntro() {
        if (!introPending) return;
        introPending = false;
        if (allowMotion) { divider.value = 1; reveal.start(); }
        else divider.value = 0.5;
    }
    onAllowMotionChanged: if (!allowMotion) {
        const wasIntroducing = introPending || reveal.running;
        cancelIntro();
        if (wasIntroducing) divider.value = 0.5;
    }

    SequentialAnimation {
        id: reveal
        objectName: "presetIntro"
        PauseAnimation { duration: Appearance.scaledDuration(130) }
        NumberAnimation { target: divider; property: "value"; to: 0; duration: Appearance.scaledDuration(900); easing.type: Easing.InOutCubic }
        PauseAnimation { duration: Appearance.scaledDuration(300) }
        NumberAnimation { target: divider; property: "value"; to: 0.5; duration: Appearance.scaledDuration(750); easing.type: Easing.InOutCubic }
    }
    // Give the new wallpaper its first frame before drawing the curtain. A remote poster can arrive later.
    Timer { interval: 750; running: root.introPending && root.pageShown; onTriggered: root.startIntro() }

    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.rightMargin: 4
        StyledText { text: Translation.tr("Current setup"); color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smallie }
        Item { Layout.fillWidth: true }
        StyledText { text: Translation.tr("With preset"); color: Appearance.colors.colPrimary; font.pixelSize: Appearance.font.pixelSize.smallie }
    }

    MonitorFrame {
        id: frame
        Layout.fillWidth: true
        clip: true

        WallpaperPreviewMedia {
            id: currentMedia
            anchors.fill: parent
            active: root.pageShown && !after.changesBackdrop
            zoom: Config.options.background.parallax.workspaceZoom
        }
        Item {
            width: divider.value * frame.width
            height: frame.height
            clip: true
            PresetScene {
                width: frame.width
                height: frame.height
                monitor: frame
                populated: root.pageShown
                showBackdrop: false
            }
        }
        Item {
            id: rightHalf
            x: divider.value * frame.width
            width: frame.width - x
            height: frame.height
            clip: true
            Item {
                id: candidate
                x: -rightHalf.x
                width: frame.width
                height: frame.height
                Image {
                    anchors.fill: parent
                    source: root.backdropGrab?.url ?? ""
                    onStatusChanged: if (status === Image.Ready) root.grabCandidate(root.attemptedCover)
                }
                PresetScene {
                    id: after
                    objectName: "candidateScene"
                    anchors.fill: parent
                    monitor: frame
                    populated: root.pageShown
                    preset: root.preset
                    categories: root.categories
                    showBackdrop: changesBackdrop
                    moving: root.pageShown
                    animateBar: root.pageShown && Appearance.animationSpeed > 0
                }
            }
        }
        Slider {
            id: divider
            objectName: "presetDivider"
            anchors.fill: parent
            padding: 0
            from: 0
            to: 1
            value: 0.5
            Component.onCompleted: if (root.allowMotion && root.introPending) value = 1
            stepSize: 0
            onPressedChanged: if (pressed) root.cancelIntro()
            Keys.onLeftPressed: { root.cancelIntro(); value = Math.max(0, value - 0.025); }
            Keys.onRightPressed: { root.cancelIntro(); value = Math.min(1, value + 0.025); }
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Home || event.key === Qt.Key_End) {
                    root.cancelIntro();
                    value = event.key === Qt.Key_Home ? 0 : 1;
                    event.accepted = true;
                }
            }
            snapMode: Slider.NoSnap
            live: true
            focusPolicy: Qt.StrongFocus
            Accessible.name: Translation.tr("Compare current setup and preset")
            // The divider reaches both edges without scaling either scene.
            background: null
            handle: Item {
                x: divider.value * frame.width
                width: 0
                height: frame.height
                Rectangle {
                    width: 24; height: parent.height
                    anchors.horizontalCenter: parent.horizontalCenter
                    opacity: reveal.running || divider.pressed ? 0.9 : 0
                    Behavior on opacity { NumberAnimation { duration: Appearance.scaledDuration(160) } }
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 0.47; color: "#68000000" }
                        GradientStop { position: 0.52; color: "#60ffffff" }
                        GradientStop { position: 1; color: "transparent" }
                    }
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 2; height: parent.height
                    color: Appearance.colors.colOnLayer2
                }
                Rectangle {
                    width: 34; height: 40; radius: 13
                    x: Math.max(-parent.x, Math.min(frame.width - parent.x - width, -width / 2))
                    anchors.verticalCenter: parent.verticalCenter
                    color: divider.pressed || divider.visualFocus ? Appearance.colors.colPrimary : Appearance.colors.colLayer2Base
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "unfold_more"; rotation: 90; iconSize: 20
                        color: divider.pressed || divider.visualFocus ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                    }
                }
            }
            HoverHandler { cursorShape: Qt.SplitHCursor }
        }
    }
}
