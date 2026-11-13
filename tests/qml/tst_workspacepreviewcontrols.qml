import QtQuick
import QtTest

Item {
    id: scene
    width: 640; height: 480
    property bool leaveMode: true
    property int edge: 0
    Item {
        id: panel
        x: scene.edge === 1 ? 540 : 20
        y: scene.edge === 3 ? 380 : 20
        width: scene.edge < 2 ? 60 : 580
        height: scene.edge < 2 ? 420 : 60
        HoverHandler { id: panelPointer; blocking: false }
        MouseArea {
            id: target
            width: 40; height: 40
            x: 10; y: 10
            hoverEnabled: true
            property int clicks: 0
            onClicked: clicks++
        }
    }
    QtObject { id: preferences; property bool enabled: true }
    // Another monitor has its own panel presence. It cannot retain this popup.
    Item { id: otherPanel; property bool hovered: false }
    PopupState {
        id: popup
        hoverTarget: target
        hoverEnabled: preferences.enabled && !GlobalStates.barEditing
        openDelay: 40
        closeDelay: 70
        interactive: !scene.leaveMode
        keepOpen: scene.leaveMode && panelPointer.hovered
        closeImmediately: scene.leaveMode && !panelPointer.hovered
    }
    TestCase {
        name: "WorkspacePreviewControls"
        when: windowShown
        function init() {
            mouseMove(scene, 320, 240);
            scene.edge=0; scene.leaveMode=true;
            preferences.enabled=false;
            popup.hoverControlled=true;
            popup.hideInstantly=false;
            popup.popupHovered=false;
            otherPanel.hovered=false;
            GlobalStates.barEditing=false;
            preferences.enabled=true;
            wait(120);
        }
        function enter() {
            mouseMove(target,20,20);
            tryCompare(panelPointer,"hovered",true);
            tryCompare(popup,"wanted",true);
            compare(popup.active,true);
        }
        function test_panel_boundaries_data() {
            return [{tag:"left",edge:0},{tag:"right",edge:1},
                    {tag:"top",edge:2},{tag:"bottom",edge:3}];
        }
        function test_panel_boundaries(data) {
            scene.edge=data.edge;
            enter();
            mouseClick(target,20,20);
            verify(target.clicks>0); // Passive panel measurement does not steal buttons.
            mouseMove(panel,panel.width-10,panel.height-10);
            tryCompare(target,"containsMouse",false);
            compare(panelPointer.hovered,true);
            wait(160); // Beyond both grace and exit animation.
            compare(popup.wanted,true); compare(popup.active,true);
            otherPanel.hovered=true;
            mouseMove(scene,320,240);
            tryCompare(panelPointer,"hovered",false);
            // No grace/lingering even with animations enabled, on any edge.
            compare(popup.wanted,false); compare(popup.lingering,false); compare(popup.active,false);
            popup.popupHovered=true; wait(100);
            compare(popup.active,false); // Entering the old popup cannot resurrect it.
        }
        function test_unrelated_panel_area_never_opens_or_finishes_delay() {
            mouseMove(panel,30,200);
            tryCompare(panelPointer,"hovered",true);
            wait(100); compare(popup.active,false);
            mouseMove(target,20,20);
            tryCompare(popup.openTimer,"running",true);
            mouseMove(panel,30,200);
            tryCompare(popup.openTimer,"running",false);
            wait(100); compare(popup.active,false);
            mouseMove(target,20,20); tryCompare(popup,"wanted",true);
        }
        function test_disable_reenable_and_cancel_delayed_open() {
            mouseMove(target,20,20);
            tryCompare(popup.openTimer,"running",true);
            preferences.enabled=false;
            compare(popup.openTimer.running,false);
            compare(popup.closeTimer.running,false);
            wait(160); compare(popup.active,false); compare(popup.wanted,false);
            preferences.enabled=true;
            compare(popup.wanted,false); tryCompare(popup,"wanted",true);
            preferences.enabled=false;
            compare(popup.wanted,false); compare(popup.lingering,false); compare(popup.active,false);
            mouseMove(panel,30,200); preferences.enabled=true;
            wait(100); compare(popup.active,false);
        }
        function test_interactive_crossing_mode_change_and_flick() {
            scene.leaveMode=false;
            enter();
            mouseMove(scene,320,240);
            compare(popup.wanted,true); // Grace for crossing to the preview.
            popup.popupHovered=true;
            wait(120); compare(popup.wanted,true);
            scene.leaveMode=true;
            compare(popup.active,false); compare(popup.wanted,false);
            compare(popup.popupHovered,false);
            scene.leaveMode=false;
            wait(100); compare(popup.active,false);
            enter(); popup.hideInstantly=true;
            mouseMove(scene,320,240);
            compare(popup.wanted,false); verify(popup.dismissed);
            popup.popupHovered=true; wait(100); compare(popup.wanted,false);
            popup.popupHovered=false; popup.hideInstantly=false;
            enter();
        }
        function test_mode_change_while_elsewhere_on_panel() {
            enter(); mouseMove(panel,30,200);
            compare(popup.wanted,true);
            scene.leaveMode=false;
            wait(180); compare(popup.active,false);
            scene.leaveMode=true; wait(100); compare(popup.active,false);
        }
        function test_interactive_grace_to_panel_only_keeps_preview() {
            scene.leaveMode=false; enter();
            mouseMove(panel,30,200);
            compare(popup.wanted,true); verify(popup.closeTimer.running);
            scene.leaveMode=true;
            wait(160); compare(popup.wanted,true); compare(popup.active,true);
            compare(popup.closeTimer.running,false);
            mouseMove(scene,320,240); tryCompare(popup,"active",false);
        }
        function test_editing_closes_even_when_elsewhere_on_panel() {
            enter(); mouseMove(panel,30,200); compare(popup.wanted,true);
            GlobalStates.barEditing=true;
            compare(popup.active,false); compare(popup.wanted,false);
            GlobalStates.barEditing=false; wait(120); compare(popup.active,false);
        }
        function test_owner_controlled_popup_not_affected() {
            preferences.enabled=false;
            popup.hoverControlled=false;
            popup.active=true;
            mouseMove(target,20,20); mouseMove(scene,320,240); wait(160);
            compare(popup.active,true);
            compare(popup.openTimer.running,false); compare(popup.closeTimer.running,false);
            popup.active=Qt.binding(() => popup.wanted || popup.lingering);
        }
    }
}
