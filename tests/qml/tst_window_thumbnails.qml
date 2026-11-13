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
    function init() { WindowPreviewPolicy.compositorVersion = ""; HyprlandData.identifier = ""; WindowPreviews.frames = ({}); GlobalStates.screenLocked = false; }
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
        WindowPreviews.handle(JSON.stringify({event:"frame", id:"ab12", path:"/frame.png", revision:"1", width:280, height:140}));
        verify(WindowPreviews.frames.ab12);
        WindowPreviews.update(first, "cd34", 280, 180, true, false);
        verify(WindowPreviews.frames.ab12, "another subscriber still needs this frame");
        WindowPreviews.release(second);
        verify(!WindowPreviews.frames.ab12);
        WindowPreviews.handle(JSON.stringify({event:"frame", id:"ab12", path:"/late.png", revision:"2", width:280, height:140}));
        verify(!WindowPreviews.frames.ab12, "late closed-window results must be discarded");
        WindowPreviews.release(first);
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
    function test_return_to_cached_preview_does_not_wait_for_capture() {
        WindowPreviewPolicy.compositorVersion = "0.57.0";
        HyprlandData.identifier = "ab12";
        const view = makePreview();
        view.retainWhileHidden = true;
        WindowPreviews.frames = ({ab12: {source: Qt.resolvedUrl("frame-red.png"), width:280, height:140}});
        tryVerify(() => view.hasContent);
        const spy = createTemporaryObject(spyFactory, this, {target:view, signalName:"hasContentChanged"});
        view.visible = false;
        compare(view.subscription, 0, "a cached image must not keep capturing a hidden window");
        verify(!WindowPreviews.frames.ab12, "the cache must not depend on the capture file surviving");
        view.visible = true;
        verify(view.subscription > 0);
        compare(spy.count, 0, "returning to a visited window must keep its ready image");
        compare(grabImage(view).red(160, 90), 255);
        WindowPreviews.frames = ({ab12: {source: Qt.resolvedUrl("frame-blue.png"), width:280, height:140}});
        tryVerify(() => grabImage(view).blue(160, 90) === 255);
        compare(spy.count, 0);
        view.visible = false;
        GlobalStates.screenLocked = true;
        verify(!view.hasContent, "lock must also clear images of invisible visited windows");
    }
    function test_cached_preview_is_invalidated_when_its_window_closes() {
        WindowPreviewPolicy.compositorVersion = "0.57.0";
        HyprlandData.identifier = "ab12";
        const view = makePreview();
        view.retainWhileHidden = true;
        WindowPreviews.frames = ({ab12: {source: Qt.resolvedUrl("frame-red.png"), width:280, height:140}});
        tryVerify(() => view.hasContent);
        view.visible = false;
        view.toplevel.closed();
        verify(!view.hasContent);
        view.visible = true;
        compare(view.subscription, 0);
    }
    function test_visited_window_pool_is_bounded_and_cleared_on_hide_lock_and_close() {
        const windows = [];
        for (let i = 0; i < 12; ++i) windows.push(createTemporaryObject(sourceFactory, this));
        ToplevelManager.toplevels.values = windows;
        const pool = createTemporaryObject(poolFactory, this, {active:true, retainedLimit:2});
        for (const window of windows) {
            pool.current = [window];
            verify(pool.windows.includes(window));
            verify(pool.windows.length <= 3, "at most two visited windows plus the current one");
        }
        pool.current = [windows[10]];
        verify(pool.windows.includes(windows[11]));
        ToplevelManager.toplevels.values = windows.slice(0, 11);
        verify(!pool.windows.includes(windows[11]), "closed windows must leave the pool");
        GlobalStates.screenLocked = true;
        compare(pool.windows.length, 0);
        GlobalStates.screenLocked = false;
        compare(pool.windows.length, 1, "unlock must not restore old cached images");
        pool.active = false;
        compare(pool.windows.length, 0);
    }
    function test_popup_waits_for_complete_group_and_ignores_superseded_requests() {
        const browser = createTemporaryObject(sourceFactory, this);
        const dolphin = createTemporaryObject(sourceFactory, this);
        const terminal = createTemporaryObject(sourceFactory, this);
        ToplevelManager.toplevels.values = [browser, dolphin, terminal];
        const pool = createTemporaryObject(poolFactory, this, {active:true, current:[browser]});
        compare(pool.displayed.length, 0, "first hover must not expose an unready card");
        pool.setReady(browser, true);
        compare(pool.displayed[0], browser);
        pool.current = [dolphin];
        compare(pool.displayed[0], browser, "the complete old card stays while the new image loads");
        pool.current = [terminal];
        pool.setReady(dolphin, true);
        compare(pool.displayed[0], browser, "a late result for a skipped icon must not be presented");
        pool.setReady(terminal, true);
        compare(pool.displayed[0], terminal);
        pool.setReady(dolphin, false);
        pool.current = [browser, dolphin];
        compare(pool.displayed[0], terminal, "do not show a partial group with a blank second card");
        pool.setReady(dolphin, true);
        compare(pool.displayed.length, 2);
        compare(pool.displayed[0], browser);
        compare(pool.displayed[1], dolphin);
        pool.active = false;
        compare(pool.displayed.length, 0);
        pool.setReady(browser, true);
        compare(pool.displayed.length, 0, "dismissed requests must never reopen the popup");
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
