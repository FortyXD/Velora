import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    required property string scene
    required property bool shown
    property bool showReplay: false
    readonly property bool playing: animation.running
    property real progress: 1
    readonly property int duration: Appearance.scaledDuration(scene === "recording" ? 1150 : scene === "overlay" ? 520 : 800)
    readonly property bool canAnimate: duration > 0 && (scene !== "overlay" || Config.options.overlay.openingZoomAnimation)

    function settle() {
        animation.stop();
        progress = 1;
    }
    function replay() {
        if (!loader.item || !shown || !canAnimate) {
            settle();
            return;
        }
        if (animation.running) return;
        rewind.duration = Math.round(Appearance.scaledDuration(140) * progress);
        animation.start();
    }
    onCanAnimateChanged: if (!canAnimate) settle()
    onShownChanged: if (!shown) settle()

    SequentialAnimation {
        id: animation
        NumberAnimation {
            id: rewind
            target: root; property: "progress"; to: 0
            easing.type: Easing.InOutCubic
        }
        NumberAnimation {
            target: root; property: "progress"; from: 0; to: 1
            duration: root.duration
            easing.type: root.scene === "recording" ? Easing.Linear : Easing.OutCubic
        }
    }
    Loader {
        id: loader
        anchors.fill: parent
        active: root.shown
        sourceComponent: root.scene === "recording" ? film : root.scene === "overlay" ? overlay : selection
        onLoaded: { root.progress = 0; root.replay(); }
    }
    Component { id: film; RecordingPreview { progress: root.progress } }
    Component { id: overlay; OverlayPreview { progress: root.progress } }
    Component { id: selection; CaptureAreaPreview { progress: root.progress; selector: root.scene === "selection" } }

    Connections {
        target: root.shown && root.scene === "selection" ? Config.options.search.imageSearch : null
        function onUseCircleSelectionChanged() { root.replay() }
    }
    Connections {
        target: root.shown && root.scene === "overlay" ? Config.options.overlay : null
        function onOpeningZoomAnimationChanged() { root.replay() }
    }
    RippleButton {
        visible: root.showReplay
        enabled: root.canAnimate
        anchors { right: parent.right; bottom: parent.bottom; margins: 7 }
        implicitWidth: 30; implicitHeight: 30; buttonRadius: 15
        colBackground: Appearance.colors.colLayer2Base
        colBackgroundHover: Appearance.colors.colLayer2Hover
        Accessible.name: Translation.tr("Replay animation")
        onClicked: root.replay()
        contentItem: MaterialSymbol {
            text: "replay"; iconSize: 17
            horizontalAlignment: Text.AlignHCenter; color: Appearance.colors.colOnLayer2
        }
        StyledToolTip { text: Translation.tr("Replay animation") }
    }
}
