import QtQuick
import QtTest

TestCase {
    name: "WindowThumbnails"
    width: 640; height: 480
    visible: true
    when: windowShown
    Component { id: sourceFactory; QtObject { property string appId: "test"; signal closed() } }
    Component { id: thumbnailFactory; WindowThumbnail { width: 320; height: 180 } }
    Component { id: spyFactory; SignalSpy {} }
    Component { id: poolFactory; WindowPreviewPool {} }
    function init() {
        GlobalStates.screenLocked = true;
        WindowPreviewPolicy.compositorVersion = "";
        HyprlandData.identifier = "";
        WindowPreviews.cacheLifetime = 30000;
        GlobalStates.screenLocked = false;
    }
    function makePreview() {
        const source = createTemporaryObject(sourceFactory, this);
        return createTemporaryObject(thumbnailFactory, this, {toplevel: source});
    }
    function test_unsafe_and_unknown_versions_never_start_capture() {
        const view = makePreview();
        const backend = findChild(view, "captureBackend");
        for (const text of ["", "not-json", "{}", '{"version":"0.57.0"}', '{"tag":"v0.57.0"}']) {
            WindowPreviewPolicy.readVersion(text);
            view.captureFrame();
            compare(backend.requests, 0);
            verify(!view.capturing);
            verify(view.implicitWidth > 0 && view.implicitHeight > 0);
        }
    }
    function test_external_capture_tracks_stable_id_and_lock() {
        WindowPreviewPolicy.compositorVersion = "0.57.0";
        HyprlandData.identifier = "ab12";
        const view = makePreview();
        const backend = findChild(view, "captureBackend");
        tryVerify(() => view.subscription > 0);
        compare(Object.keys(WindowPreviews.subscriptions).length, 1, "construction must not orphan an early subscription");
        compare(backend.requests, 0);
        GlobalStates.screenLocked = true;
        tryCompare(view, "subscription", 0);
        compare(Object.keys(WindowPreviews.subscriptions).length, 0);
        GlobalStates.screenLocked = false;
        tryVerify(() => view.subscription > 0);
        view.toplevel.closed();
        tryCompare(view, "subscription", 0);
    }
    function test_close_stops_capture_before_object_destruction() {
        WindowPreviewPolicy.readVersion('{"version":"0.56.2"}');
        const view = makePreview();
        const backend = findChild(view, "captureBackend");
        tryVerify(() => view.capturing);
        view.captureFrame();
        verify(backend.requests > 0);
        const requests = backend.requests;
        view.toplevel.closed();
        compare(backend.captureSource, null);
        view.captureFrame();
        compare(backend.requests, requests);
        view.visible = false; view.visible = true;
        verify(!view.capturing, "a closed handle must not be reused after reopening");
        view.toplevel = createTemporaryObject(sourceFactory, this);
        tryVerify(() => view.capturing);
    }
    function test_external_frame_replacement_never_shows_fallback_or_changes_geometry() {
        WindowPreviewPolicy.compositorVersion = "0.57.0";
        HyprlandData.identifier = "ab12";
        const view = makePreview();
        WindowPreviews.frames = ({ab12: {source: Qt.resolvedUrl("frame-red.png"), width:280, height:140}});
        tryVerify(() => view.hasContent);
        const spy = createTemporaryObject(spyFactory, this, {target:view, signalName:"hasContentChanged"});
        const token = view.subscription;
        view.live = false;
        view.constraintSize = Qt.size(280, 160);
        compare(view.subscription, token, "settings changes must update the subscription in place");
        compare(WindowPreviews.subscriptions[token].live, false);
        compare(WindowPreviews.subscriptions[token].height, 160);
        verify(view.hasContent, "settings changes must retain the displayed frame");
        WindowPreviews.frames = ({ab12: {source: Qt.resolvedUrl("frame-blue.png"), width:280, height:140}});
        wait(150);
        compare(spy.count, 0, "Image.Loading must not replace the displayed frame with the fallback");
        compare(view.implicitWidth, 280);
        compare(view.implicitHeight, 140);
        const pixels = grabImage(view);
        compare(pixels.blue(160, 90), 255);
        compare(pixels.red(160, 90), 0);
        WindowPreviews.frames = ({ab12: {source: Qt.resolvedUrl("missing-frame.png"), width:280, height:140}});
        wait(150);
        verify(view.hasContent, "a failed decode must preserve the last complete frame");
        compare(spy.count, 0);
        const retained = grabImage(view);
        compare(retained.blue(160, 90), 255);
        compare(retained.red(160, 90), 0);
        view.visible = false;
        tryVerify(() => !view.hasContent);
    }
    function test_shared_frame_survives_subscriber_changes_and_rejects_closed_windows() {
        const first = WindowPreviews.acquire("ab12", 280, 180, true, false);
        const second = WindowPreviews.acquire("ab12", 280, 180, true, false);
        const generation = WindowPreviews.subscriptions[first].generation;
        WindowPreviews.handle(JSON.stringify({event:"frame", id:"ab12", generation, path:"/frame.png", revision:"1", width:280, height:140}));
        verify(WindowPreviews.frames.ab12);
        WindowPreviews.update(first, "cd34", 280, 180, true, false);
        verify(WindowPreviews.frames.ab12, "another subscriber still needs this frame");
        WindowPreviews.release(second);
        verify(!WindowPreviews.frames.ab12);
        const reopened = WindowPreviews.acquire("ab12", 280, 180, true, false);
        WindowPreviews.handle(JSON.stringify({event:"frame", id:"ab12", generation, path:"/late.png", revision:"2", width:280, height:140}));
        verify(!WindowPreviews.frames.ab12, "late closed-window results must be discarded");
        WindowPreviews.release(first);
        WindowPreviews.release(reopened);
    }
    function test_hidden_parent_and_missing_source_stop_capture() {
        WindowPreviewPolicy.readVersion('{"version":"0.56.2"}');
        const container = createTemporaryQmlObject('import QtQuick; Item {}', this);
        const view = createTemporaryObject(thumbnailFactory, container, {toplevel: createTemporaryObject(sourceFactory, this)});
        tryVerify(() => view.capturing);
        container.visible = false;
        tryVerify(() => !view.capturing);
        container.visible = true;
        tryVerify(() => view.capturing);
        view.toplevel = null;
        verify(!view.capturing);
    }
    function test_new_surface_can_paint_cached_pixels_before_a_fresh_capture() {
        WindowPreviewPolicy.compositorVersion = "0.57.0";
        HyprlandData.identifier = "ab12";
        const source = createTemporaryObject(sourceFactory, this);
        const first = createTemporaryObject(thumbnailFactory, this, {toplevel:source});
        WindowPreviews.frames = ({ab12: {source: Qt.resolvedUrl("frame-red.png"), width:280, height:140}});
        tryVerify(() => first.hasContent);
        first.visible = false;
        compare(Object.keys(WindowPreviews.subscriptions).length, 0);
        verify(!WindowPreviews.frames.ab12);
        first.destroy();
        wait(0);

        const next = createTemporaryObject(thumbnailFactory, this, {toplevel:source});
        verify(next.hasContent, "a different delegate must be ready on its first render");
        compare(grabImage(next).red(160, 90), 255);
        WindowPreviews.frames = ({ab12: {source: Qt.resolvedUrl("frame-blue.png"), width:280, height:140}});
        tryVerify(() => grabImage(next).blue(160, 90) === 255);
        next.visible = false;
        source.closed();
        verify(!WindowPreviews.cached(source, "ab12"));
        verify(!next.hasContent);
    }
    function test_cache_is_bounded_expires_and_drops_locked_or_recycled_handles() {
        const frame = {source:Qt.resolvedUrl("frame-red.png"), width:280, height:140};
        const windows = [];
        WindowPreviews.cacheLifetime = 120;
        for (let i = 0; i < 10; i++) {
            const window = createTemporaryObject(sourceFactory, this);
            windows.push(window);
            WindowPreviews.remember(window, String(i), frame);
        }
        compare(WindowPreviews.recent.length, 8);
        verify(!WindowPreviews.cached(windows[0], "0"));
        verify(!WindowPreviews.cached(windows[9], "8"));
        verify(WindowPreviews.cached(windows[2], "2"));
        tryCompare(WindowPreviews, "recent", []);
        WindowPreviews.remember(windows[9], "9", frame);
        GlobalStates.screenLocked = true;
        compare(WindowPreviews.recent.length, 0);
        GlobalStates.screenLocked = false;
        verify(!WindowPreviews.cached(windows[9], "9"));
    }
    function test_every_card_is_available_while_its_thumbnail_is_pending() {
        const browser = createTemporaryObject(sourceFactory, this);
        const terminal = createTemporaryObject(sourceFactory, this);
        ToplevelManager.toplevels.values = [browser, terminal];
        const pool = createTemporaryObject(poolFactory, this, {active:true, current:[browser,terminal]});
        compare(pool.windows, [browser,terminal]);
        pool.current = [terminal];
        compare(pool.windows, [terminal]);
        GlobalStates.screenLocked = true;
        compare(pool.windows.length, 0);
        GlobalStates.screenLocked = false;
        ToplevelManager.toplevels.values = [browser];
        compare(pool.windows.length, 0);
        pool.active = false;
        pool.current = [browser];
        compare(pool.windows.length, 0);
    }
    function test_preparation_captures_without_showing_a_placeholder() {
        WindowPreviewPolicy.compositorVersion = "0.57.0";
        HyprlandData.identifier = "ab12";
        const backdrop = createTemporaryQmlObject('import QtQuick; Rectangle {width:320; height:180; color:"#12ab34"}', this);
        const view = createTemporaryObject(thumbnailFactory, backdrop, {
            toplevel:createTemporaryObject(sourceFactory, this), showFallback:false});
        waitForRendering(backdrop);
        const empty = grabImage(backdrop);
        compare(empty.red(160, 90), 0x12, "no background tile or icon while the first image is missing");
        compare(empty.green(160, 90), 0xab);
        compare(empty.blue(160, 90), 0x34);
        view.visible = false;
        view.preparing = true;
        verify(view.capturing, "prepare must work before the popup becomes visible");
        verify(view.subscription > 0);
        WindowPreviews.frames = ({ab12: {source: Qt.resolvedUrl("frame-blue.png"), width:280, height:140}});
        tryVerify(() => view.hasContent);
        view.visible = true;
        compare(grabImage(view).blue(160, 90), 255);
        view.preparing = false;
        view.visible = false;
        compare(view.subscription, 0);
        verify(!view.hasContent);
    }
}
