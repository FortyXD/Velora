import QtQuick

// Each picture owns its geometry and decode size. Loading the next picture cannot
// resize, move or reload the one that is still visible underneath it.
Item {
    id: root
    property int duration: 700
    property real devicePixelRatio: 1
    property real zoom: 1
    property bool workspaceParallax: false
    property bool autoVertical: true
    property bool vertical: false
    property real workspaceFraction: 0.5
    property real sidebarOffset: 0
    property var incoming: null
    property var current: null
    property var preloaded: null // Decoded ahead and kept hidden until show() asks for it
    readonly property bool ready: root.current !== null
    readonly property real offsetX: root.current ? root.current.x - (root.width - root.current.width) / 2 : 0
    readonly property real offsetY: root.current ? root.current.y - (root.height - root.current.height) / 2 : 0

    signal presented(string path)
    signal finished(string path)
    signal failed(string path)
    signal preloadReady(string path)

    function pictures() {
        return Array.from(stack.children);
    }

    function clear() {
        root.incoming = null;
        root.current = null;
        root.preloaded = null;
        for (const picture of root.pictures()) picture.destroy();
    }

    // Decodes a picture without showing it, so a later show() of the same one has nothing to wait for
    function preload(path, imageWidth, imageHeight) {
        if (root.preloaded?.path === path || root.current?.path === path) {
            root.preloadReady(path);
            return;
        }
        root.preloaded?.destroy();
        root.preloaded = pictureComponent.createObject(stack, {
            "path": path,
            "imageWidth": Math.max(1, imageWidth),
            "imageHeight": Math.max(1, imageHeight)
        });
        root.preloaded.reportPreload();
    }

    function cancelPending() {
        if (root.incoming && root.incoming !== root.current) root.incoming.destroy();
        root.incoming = null;
    }

    function show(path, imageWidth, imageHeight) {
        // A pending decode has never been displayed and can be discarded immediately.
        root.cancelPending();
        const ahead = root.preloaded;
        root.preloaded = null;
        // Above the current picture, as a new one would be
        if (ahead && ahead.path === path && ahead.status !== Image.Error && root.pictures().indexOf(ahead) > root.pictures().indexOf(root.current)) {
            root.incoming = ahead;
        } else {
            ahead?.destroy();
            root.incoming = pictureComponent.createObject(stack, {
                "path": path,
                "imageWidth": Math.max(1, imageWidth),
                "imageHeight": Math.max(1, imageHeight)
            });
        }
        // A cached image can already be ready before createObject returns.
        root.incoming.activate();
    }

    function settle(picture) {
        const pictures = root.pictures();
        for (const older of pictures.slice(0, pictures.indexOf(picture))) older.destroy();
        if (picture === root.incoming) root.finished(picture.path);
    }

    Item { id: stack; anchors.fill: parent }

    Component {
        id: pictureComponent
        Image {
            id: picture
            required property string path
            required property real imageWidth
            required property real imageHeight
            property bool activated: false
            readonly property real fit: Math.max(root.width / imageWidth, root.height / imageHeight) * Math.max(1, root.zoom)
            readonly property bool useVertical: root.vertical || (root.autoVertical && imageHeight > imageWidth)
            readonly property real fractionX: Math.max(0, Math.min(1, (root.workspaceParallax && !useVertical ? root.workspaceFraction : 0.5) + root.sidebarOffset))
            readonly property real fractionY: root.workspaceParallax && useVertical ? root.workspaceFraction : 0.5
            width: imageWidth * fit
            height: imageHeight * fit
            x: -(width - root.width) * fractionX
            y: -(height - root.height) * fractionY
            Behavior on x { NumberAnimation { duration: root.duration; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: root.duration; easing.type: Easing.OutCubic } }
            source: path
            sourceSize: Qt.size(Math.ceil(width * root.devicePixelRatio), Math.ceil(height * root.devicePixelRatio))
            asynchronous: true
            cache: false
            smooth: true
            fillMode: Image.PreserveAspectCrop
            opacity: 0

            function reportPreload() {
                // A picture that fails to decode has nothing more to wait for either
                if (picture === root.preloaded && (status === Image.Ready || status === Image.Error)) root.preloadReady(path);
            }
            function activate() {
                picture.reportPreload();
                if (picture !== root.incoming || picture.activated) return;
                if (status === Image.Error) {
                    root.incoming = null;
                    root.failed(path);
                    picture.destroy();
                } else if (status === Image.Ready) {
                    picture.activated = true;
                    const first = !root.ready;
                    root.current = picture;
                    root.presented(path);
                    if (first || root.duration === 0) {
                        opacity = 1;
                        root.settle(picture);
                    } else {
                        fade.start();
                    }
                }
            }
            onStatusChanged: activate()
            NumberAnimation {
                id: fade
                target: picture
                property: "opacity"
                to: 1
                duration: root.duration
                easing.type: Easing.InOutQuad
                onFinished: root.settle(picture)
            }
        }
    }
}
