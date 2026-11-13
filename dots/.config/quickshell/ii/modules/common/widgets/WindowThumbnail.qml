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
    // Prepare a requested card before its popup is mapped; never paint a placeholder.
    property bool preparing: false
    // A popup may keep a few visited delegates alive while another app is hovered.
    // Keep only their decoded image; hidden delegates never hold a capture subscription.
    property bool retainWhileHidden: false
    property bool sourceClosed: false
    property bool componentReady: false
    readonly property bool external: !WindowPreviewPolicy.allowed
    readonly property string stableId: String(HyprlandData.clientForToplevel(toplevel)?.stableId ?? "")
    readonly property bool capturing: (preparing || (visible && !!root.Window.window?.visible))
        && !!toplevel && !sourceClosed && !GlobalStates.screenLocked
        && (!external || stableId.length > 0)
    property int subscription: 0
    readonly property var frame: external && capturing ? (WindowPreviews.frames[stableId] ?? null) : null
    property Image displayedImage: null
    property Image pendingImage: null
    property var displayedFrame: null
    property string attemptedSource: ""
    property string imageId: ""
    readonly property bool hasContent: external ? displayedImage !== null : capture.hasContent
    readonly property size sourceSize: external ? Qt.size(displayedFrame?.width ?? 0, displayedFrame?.height ?? 0) : capture.sourceSize
    implicitWidth: hasContent ? (external ? (displayedFrame?.width ?? 160) : capture.implicitWidth) : (constraintSize.width || 160)
    implicitHeight: hasContent ? (external ? (displayedFrame?.height ?? 90) : capture.implicitHeight) : (constraintSize.height || 90)

    function clearImages() {
        pendingImage = null;
        displayedImage = null;
        displayedFrame = null;
        attemptedSource = "";
        imageId = stableId;
        firstImage.source = "";
        secondImage.source = "";
    }
    function loadFrame() {
        if (!componentReady) return;
        if (imageId !== stableId || !external || !toplevel || sourceClosed
            || GlobalStates.screenLocked || (!capturing && !retainWhileHidden)) clearImages();
        if (!capturing) {
            const pending = pendingImage;
            pendingImage = null;
            if (pending) { pending.source = ""; attemptedSource = ""; }
            return;
        }
        if (!frame) return;
        // Decode off-screen and keep just the latest waiting frame, never a queue.
        if (pendingImage || attemptedSource === String(frame.source)) return;
        attemptedSource = String(frame.source);
        const next = displayedImage === firstImage ? secondImage : firstImage;
        pendingImage = next;
        next.frame = frame;
        next.source = frame.source;
    }
    function imageFinished(image) {
        if (pendingImage !== image) return;
        if (image.status === Image.Ready) {
            const previous = displayedImage;
            displayedFrame = image.frame;
            displayedImage = image;
            pendingImage = null;
            if (previous) previous.source = "";
            Qt.callLater(loadFrame);
        } else if (image.status === Image.Error) {
            pendingImage = null;
            image.source = "";
            Qt.callLater(loadFrame);
        }
    }
    onFrameChanged: loadFrame()

    function subscribe() {
        // Initial property bindings can fire before subscription's initializer.
        // Acquiring then would lose the token when the initializer writes zero.
        if (!componentReady) return;
        if (capturing && external) {
            if (subscription) WindowPreviews.update(subscription, stableId,
                constraintSize.width || 280, constraintSize.height || 180, live, paintCursor);
            else subscription = WindowPreviews.acquire(stableId,
                constraintSize.width || 280, constraintSize.height || 180, live, paintCursor);
        } else if (subscription) { WindowPreviews.release(subscription); subscription = 0; }
    }
    onCapturingChanged: { subscribe(); loadFrame(); }
    onStableIdChanged: { subscribe(); loadFrame(); }
    onExternalChanged: subscribe()
    onLiveChanged: subscribe()
    onConstraintSizeChanged: subscribe()
    onPaintCursorChanged: subscribe()
    Component.onCompleted: { componentReady = true; subscribe(); loadFrame(); }
    Component.onDestruction: if (subscription) WindowPreviews.release(subscription)

    onToplevelChanged: { sourceClosed = false; loadFrame(); }
    onSourceClosedChanged: loadFrame()
    onRetainWhileHiddenChanged: loadFrame()
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
        anchors.fill: parent
        visible: root.external && root.displayedImage === firstImage
        asynchronous: true
        cache: false
        fillMode: Image.PreserveAspectFit
        onStatusChanged: root.imageFinished(firstImage)
    }
    Image {
        id: secondImage
        property var frame: null
        anchors.fill: parent
        visible: root.external && root.displayedImage === secondImage
        asynchronous: true
        cache: false
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
