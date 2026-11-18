pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common

Item {
    id: root
    property var toplevel: null
    property bool live: true
    property bool paintCursor: false
    property size constraintSize: Qt.size(0, 0)
    property bool showFallbackIcon: true
    property bool showFallback: true
    // A consumer can request its first frame during the popup's opening delay.
    property bool preparing: false
    property int priority: 0
    property bool sourceClosed: false
    property bool componentReady: false
    readonly property bool external: !WindowPreviewPolicy.allowed
    readonly property var client: HyprlandData.clientForToplevel(toplevel)
    readonly property string stableId: String(client?.stableId ?? "")
    readonly property int sourceWidth: client?.size?.[0] ?? 0
    readonly property int sourceHeight: client?.size?.[1] ?? 0
    readonly property bool mapped: visible && !!root.Window.window?.visible
    readonly property bool capturing: (preparing || mapped)
        && !!toplevel && !sourceClosed && !GlobalStates.screenLocked
        && (!external || stableId.length > 0)
    property int subscription: 0
    readonly property bool nativeReady: !external && capturing && capture.hasContent
    readonly property var frame: capturing && !nativeReady
        ? ((external ? WindowPreviews.frames[stableId] : null) ?? WindowPreviews.cached(toplevel, stableId)) : null
    property Image displayedImage: null
    property Image pendingImage: null
    property var displayedFrame: null
    property string attemptedSource: ""
    property string attemptedCachedSource: ""
    property string imageId: ""
    readonly property bool hasContent: nativeReady || displayedImage !== null
    readonly property size sourceSize: nativeReady ? capture.sourceSize : Qt.size(displayedFrame?.width ?? 0, displayedFrame?.height ?? 0)
    readonly property real fit: sourceSize.width > 0 && sourceSize.height > 0 ? Math.min(1,
        (constraintSize.width || sourceSize.width) / sourceSize.width, (constraintSize.height || sourceSize.height) / sourceSize.height) : 1
    implicitWidth: sourceSize.width > 0 ? sourceSize.width * fit : (constraintSize.width || 160)
    implicitHeight: sourceSize.height > 0 ? sourceSize.height * fit : (constraintSize.height || 90)

    function clearImages() {
        pendingImage = null;
        displayedImage = null;
        displayedFrame = null;
        attemptedSource = "";
        attemptedCachedSource = "";
        imageId = stableId;
        firstImage.source = "";
        secondImage.source = "";
    }
    function loadFrame() {
        if (!componentReady) return;
        if (imageId !== stableId || !capturing) clearImages();
        if (!capturing) return;
        const cached = !displayedImage ? WindowPreviews.cached(toplevel, stableId) : null;
        const useCached = cached && String(cached.source) !== attemptedCachedSource;
        const nextFrame = useCached ? cached : frame;
        if (!nextFrame) return;
        // Decode off-screen and keep just the latest waiting frame, never a queue.
        if (pendingImage || attemptedSource === String(nextFrame.source)) return;
        attemptedSource = String(nextFrame.source);
        if (useCached) attemptedCachedSource = attemptedSource;
        const next = displayedImage === firstImage ? secondImage : firstImage;
        pendingImage = next;
        next.frame = nextFrame;
        next.fromStream = external && !useCached && nextFrame === WindowPreviews.frames[stableId];
        next.source = nextFrame.source;
    }
    function imageFinished(image) {
        if (pendingImage !== image) return;
        if (image.status === Image.Ready) {
            const previous = displayedImage;
            displayedFrame = image.frame;
            displayedImage = image;
            pendingImage = null;
            if (image.fromStream && capturing)
                WindowPreviews.remember(toplevel, stableId, image.frame);
            if (previous) previous.source = "";
            Qt.callLater(loadFrame);
        } else if (image.status === Image.Error) {
            pendingImage = null;
            image.source = "";
            Qt.callLater(loadFrame);
        }
    }
    onFrameChanged: loadFrame()

    // Native screencopy has no file URL. Keep a small in-memory grab of the
    // first rendered frame so another surface can display it while acquiring.
    function rememberNative() {
        if (!nativeReady || !mapped || !capture.width || !capture.height) return;
        const owner = toplevel;
        const id = stableId;
        const generation = WindowPreviews.lockGeneration;
        const size = Qt.size(Math.max(1, Math.round(implicitWidth)), Math.max(1, Math.round(implicitHeight)));
        capture.grabToImage(result => {
            if (owner === toplevel && capturing && !sourceClosed && generation === WindowPreviews.lockGeneration)
                WindowPreviews.remember(owner, id, {source: result.url, width: size.width, height: size.height}, result);
        }, size);
    }
    onNativeReadyChanged: if (nativeReady) Qt.callLater(rememberNative)
    onMappedChanged: if (mapped && nativeReady) Qt.callLater(rememberNative)

    function subscribe() {
        // Initial property bindings can fire before subscription's initializer.
        // Acquiring then would lose the token when the initializer writes zero.
        if (!componentReady) return;
        if (capturing && external) {
            if (subscription) WindowPreviews.update(subscription, stableId,
                constraintSize.width || 280, constraintSize.height || 180, live, paintCursor, priority, sourceWidth, sourceHeight);
            else subscription = WindowPreviews.acquire(stableId,
                constraintSize.width || 280, constraintSize.height || 180, live, paintCursor, priority, sourceWidth, sourceHeight);
        } else if (subscription) { WindowPreviews.release(subscription); subscription = 0; }
    }
    onCapturingChanged: { subscribe(); loadFrame(); }
    onStableIdChanged: { subscribe(); loadFrame(); }
    onExternalChanged: subscribe()
    onLiveChanged: subscribe()
    onConstraintSizeChanged: subscribe()
    onPaintCursorChanged: subscribe()
    onPriorityChanged: subscribe()
    onSourceWidthChanged: subscribe()
    onSourceHeightChanged: subscribe()
    Component.onCompleted: { componentReady = true; subscribe(); loadFrame(); }
    Component.onDestruction: if (subscription) WindowPreviews.release(subscription)

    onToplevelChanged: { sourceClosed = false; if (componentReady) clearImages(); loadFrame(); }
    onSourceClosedChanged: loadFrame()
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() { root.loadFrame(); }
    }
    Connections {
        target: root.toplevel
        function onClosed() { root.sourceClosed = true; }
    }

    function captureFrame() {
        if (root.external) { if (root.subscription) WindowPreviews.refresh(root.subscription); }
        else if (root.capturing && capture.captureSource) capture.captureFrame();
    }

    Rectangle {
        anchors.fill: parent
        visible: root.showFallback && !root.hasContent
        color: Appearance.colors.colLayer1
    }
    ScreencopyView {
        id: capture
        anchors.fill: parent
        visible: !root.external
        captureSource: root.capturing && !root.external ? root.toplevel : null
        constraintSize: root.constraintSize
        live: root.live && root.capturing
        paintCursor: root.paintCursor
    }
    Image {
        id: firstImage
        property var frame: null
        property bool fromStream: false
        anchors.fill: parent
        visible: !root.nativeReady && root.displayedImage === firstImage
        asynchronous: true
        cache: true
        fillMode: Image.PreserveAspectFit
        onStatusChanged: root.imageFinished(firstImage)
    }
    Image {
        id: secondImage
        property var frame: null
        property bool fromStream: false
        anchors.fill: parent
        visible: !root.nativeReady && root.displayedImage === secondImage
        asynchronous: true
        cache: true
        fillMode: Image.PreserveAspectFit
        onStatusChanged: root.imageFinished(secondImage)
    }
    Image {
        visible: root.showFallback && !root.hasContent && root.showFallbackIcon
        anchors.centerIn: parent
        width: Math.min(48, parent.width * 0.5, parent.height * 0.5)
        height: width
        source: Quickshell.iconPath(root.toplevel?.appId ?? "application-x-executable", "application-x-executable")
        sourceSize.width: width
        sourceSize.height: height
    }
}
