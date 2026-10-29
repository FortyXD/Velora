import QtQuick
import QtQuick.Layouts
import QtTest

TestCase {
    name: "WindowSwitcher"
    width: 800
    height: 500
    visible: true
    when: windowShown
    property var switcher: null
    Component { id: factory; WindowSwitcher {} }
    Component {
        id: previewFactory
        Item {
            id: preview
            width: 800
            height: 500
            property int selectedIndex: 1
            property alias grid: grid
            property alias tiles: tiles
            GridLayout {
                id: grid
                x: 16
                y: 16
                columns: 3
                rowSpacing: 10
                columnSpacing: 10
                Repeater {
                    id: tiles
                    model: 3
                    delegate: WindowSwitcherTile {
                        required property int index
                        implicitWidth: 228
                        implicitHeight: 160
                        selected: preview.selectedIndex === index
                    }
                }
            }
        }
    }

    function window(address, history, workspace = "1") {
        return { address, focusHistoryID: history, workspace: { name: workspace }, mapped: true, class: "app" };
    }
    function focusWindow(address) {
        Hyprland.activeToplevel = { address: address.substring(2) };
        Hyprland.rawEvent({ name: "activewindowv2", data: address.substring(2) });
    }
    function selected() { return switcher.windows[switcher.index].address; }
    function init() {
        Hyprland.calls = [];
        Hyprland.activeToplevel = { address: "a" };
        HyprlandData.windowList = [window("0xa", 0), window("0xb", 1), window("0xc", 2)];
        switcher = factory.createObject(this);
        verify(switcher !== null);
    }
    function cleanup() { switcher.destroy(); }

    function verifyHighlight(preview) {
        for (let i = 0; i < preview.tiles.count; i++) {
            const tile = preview.tiles.itemAt(i);
            const highlight = findChild(tile, "selectionHighlight");
            verify(highlight !== null);
            compare(highlight.visible, i === preview.selectedIndex);
            compare(highlight.width, tile.width + 8);
            compare(highlight.height, tile.height + 8);
            const origin = highlight.mapToItem(preview.grid, 0, 0);
            compare(origin.x, tile.x - 4);
            compare(origin.y, tile.y - 4);
        }
    }

    function test_first_popup_highlights_second_card_without_another_tab() {
        const preview = createTemporaryObject(previewFactory, this);
        verify(preview !== null);
        tryCompare(preview.grid, "implicitWidth", 704);
        compare(preview.selectedIndex, 1);
        verifyHighlight(preview);
        preview.selectedIndex = 2;
        verifyHighlight(preview);
    }

    function test_highlight_follows_wrapping_and_resizing() {
        const preview = createTemporaryObject(previewFactory, this);
        tryCompare(preview.grid, "implicitWidth", 704);
        preview.grid.columns = 1;
        tryCompare(preview.grid, "implicitHeight", 500);
        verifyHighlight(preview);
        preview.tiles.itemAt(1).implicitHeight = 190;
        tryCompare(preview.grid, "implicitHeight", 530);
        verifyHighlight(preview);
    }

    function test_second_window_and_repeated_quick_swaps_before_clients_refresh() {
        switcher.step(1);
        compare(selected(), "0xb");
        switcher.commit();
        focusWindow("0xb");
        // The subprocess still reports A as most recent: the event history must win.
        switcher.step(1);
        compare(selected(), "0xa");
        switcher.commit();
        focusWindow("0xa");
        switcher.step(1);
        compare(selected(), "0xb");
        verify(Hyprland.calls[0].includes('address:0xb'));
    }

    function test_focus_event_seeds_previous_window_on_first_use() {
        // First event after a reload, before the cached client list catches up.
        focusWindow("0xb");
        switcher.step(1);
        compare(selected(), "0xa");
    }

    function test_live_focus_overrides_stale_client_history() {
        Hyprland.activeToplevel = { address: "c" };
        switcher.step(1);
        compare(switcher.windows[0].address, "0xc");
        compare(selected(), "0xa");
    }

    function test_forward_backward_and_wrap_keep_the_session_order() {
        switcher.step(1);
        compare(selected(), "0xb");
        focusWindow("0xc");
        switcher.step(1);
        compare(selected(), "0xc");
        switcher.step(1);
        compare(selected(), "0xa");
        switcher.step(-1);
        compare(selected(), "0xc");
        switcher.close();
        focusWindow("0xa");
        switcher.step(-1);
        compare(selected(), "0xb");
    }

    function test_never_focused_and_minimized_windows_follow_recent_windows() {
        HyprlandData.windowList = [window("0xd", -1), window("0xe", 2, "special:minimized"), window("0xa", 0), window("0xb", 1)];
        switcher.step(1);
        compare(switcher.windows.map(w => w.address), ["0xa", "0xb", "0xd", "0xe"]);
    }

    function test_closing_a_window_preserves_selected_address() {
        switcher.step(1);
        Hyprland.rawEvent({ name: "closewindow", data: "a" });
        compare(selected(), "0xb");
        Hyprland.rawEvent({ name: "closewindow", data: "b" });
        compare(selected(), "0xc");
        Hyprland.rawEvent({ name: "closewindow", data: "c" });
        compare(switcher.active, false);
        compare(switcher.shown, false);
    }

    function test_delayed_popup_and_cancel_do_not_switch_focus() {
        switcher.step(1);
        compare(switcher.shown, false);
        tryCompare(switcher, "shown", true, 500);
        compare(selected(), "0xb");
        switcher.close();
        compare(switcher.shown, false);
        compare(Hyprland.calls.length, 0);
    }

    function test_empty_and_single_window() {
        HyprlandData.windowList = [];
        Hyprland.activeToplevel = null;
        switcher.step(1);
        compare(switcher.active, false);
        HyprlandData.windowList = [window("0xa", 0)];
        switcher.step(-1);
        compare(selected(), "0xa");
        switcher.step(1);
        compare(selected(), "0xa");
    }
}
