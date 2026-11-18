import QtQuick
import QtTest
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.settings
import qs.modules.ii.bar.edit
import qs.modules.ii.bar.layout

FloatingWindow {
    id: window
    implicitWidth: 900
    implicitHeight: 650
    property int scenario: 0
    property int step: 0
    property bool working: false
    property bool slotInMotion: false
    property real positionBefore: 0
    readonly property bool vertical: (scenario % 2) === 1
    readonly property bool realBar: scenario >= 2
    readonly property string orientation: vertical ? "vertical" : "horizontal"
    readonly property var surface: realBar ? live : input.findChild(settings, "barLayoutCanvas")
    property point pointer
    function expect(ok, reason) {
        if (!ok) { console.log("CHECK_FAIL", scenario, step, reason); Qt.quit(); }
        return ok;
    }
    function host(uid) {
        for (const z of surface.zoneItems) {
            const hit = z.orderedHosts().find(h => h.uid === uid);
            if (hit) return hit;
        }
        return null;
    }
    function pos(item, fraction) {
        return item.mapToItem(window.contentItem, item.width * (vertical ? 0.5 : fraction), item.height * (vertical ? fraction : 0.5));
    }
    function move(p, buttons = Qt.NoButton) { input.mouseMove(window.contentItem, p.x, p.y, 2, buttons); }
    function order() { return BarLayout.current(orientation).zones.start.map(i => i.uid).join(","); }
    function initialize() {
        Config.options.bar.vertical = vertical;
        Config.options.appearance.animationSpeed = 1;
        GlobalStates.barEditSelection = "";
        settings.selectedUid = "";
        const items = ["one", "two", "three"].map(uid => ({uid, type:"text", options:{text:uid}, pill:true}));
        BarLayout.apply(orientation, {balanceCenter:false,zones:{start:items}});
        move(Qt.point(840,610));
        slotInMotion = false;
    }
    TestCase { id: input; when: false }
    BarConfig { id: settings; anchors.fill: parent; visible: !window.realBar }
    BarLayoutView {
        id: live
        visible: window.realBar
        editing: visible
        vertical: window.vertical
        width: vertical ? 48 : parent.width
        height: vertical ? parent.height : 44
        controller: liveController
    }
    BarEditController { id: liveController; view: live }
    Timer {
        interval: 16; running: window.working; repeat: true
        onTriggered: {
            const slot = window.surface?.editGuide.target?.slot;
            if (slot && slot.amount > 0.2 && slot.amount < 26) window.slotInMotion = true;
        }
    }
    Timer {
        interval: 230; repeat: true; running: true
        onTriggered: {
            if (!Config.ready) return;
            const g = window.surface?.editGuide;
            switch (window.step) {
            case 0:
                window.initialize(); window.working = true; break;
            case 1:
                if (!window.host("two")) return;
                window.move(window.pos(window.host("two"), 0.5)); break;
            case 2: {
                if (!window.expect(!g.target, "center opened a slot")) return;
                const second = window.host("two");
                const center = window.pos(second, 0.5);
                window.positionBefore = window.vertical ? center.y : center.x;
                window.move(window.pos(second, 0.02)); break;
            }
            case 3: {
                const target = g.target;
                if (!window.expect(target?.zone === "start" && target.index === 1 && window.slotInMotion, "edge failed: target=" + target?.index + " motion=" + slotInMotion + " enabled=" + g.enabled + " p=" + window.pos(window.host("two"),0.02) + " area=" + g.width+"x"+g.height+" host="+window.host("two").width+"x"+window.host("two").height)) return;
                const center = window.pos(window.host("two"),0.5);
                if (!window.expect(Math.abs((window.vertical ? center.y : center.x) - window.positionBefore) > 2, "neighbours did not make room")) return;
                let open = 0;
                for (const z of window.surface.zoneItems) open += z.orderedHosts().filter(h=>h.editSlot.targeted).length;
                if (!window.expect(open === 1, "unrelated slots opened")) return;
                const p=window.pos(target.slot, 0.5);
                input.mouseClick(window.contentItem,p.x,p.y); break;
            }
            case 4:
                if (!window.expect((window.realBar ? live.pickedInsertion?.index : settings.addIndex) === 1, "slot click lost index")) return;
                window.move(window.pos(window.host("one"),0.5)); break;
            case 5: {
                const p = window.pos(window.host("one"),0.5);
                input.mousePress(window.contentItem,p.x,p.y);
                window.pointer = window.pos(window.host("three"),0.93);
                window.move(window.pointer,Qt.LeftButton); break;
            }
            case 6:
                if (!window.expect(g.dragging && g.target?.index === 2, "drag destination " + g.target?.index)) return;
                input.mouseRelease(window.contentItem,window.pointer.x,window.pointer.y); break;
            case 7:
                if (!window.expect(window.order() === "two,three,one" && !g.dragging, "move did not commit " + window.order())) return;
                BarLayout.undo(); window.move(Qt.point(855,602)); break;
            case 8:
                if (!window.expect(window.order() === "one,two,three" && !g.target, "undo or exit")) return;
                window.move(window.pos(window.surface.zoneItems[2],0.5)); break;
            case 9: {
                if (!window.expect(g.target?.zone === "center" && g.target.index === 0, "empty zone did not open locally")) return;
                const from = window.pos(window.host("one"),0.5);
                window.move(from);
                input.mousePress(window.contentItem,from.x,from.y);
                window.pointer = window.pos(window.surface.zoneItems[2],0.5);
                window.move(window.pointer,Qt.LeftButton); break;
            }
            case 10:
                if (!window.expect(g.dragging && g.target?.zone === "center", "cross-zone drag lost target")) return;
                input.mouseRelease(window.contentItem,window.pointer.x,window.pointer.y); break;
            case 11:
                if (!window.expect(BarLayout.find(BarLayout.current(window.orientation),"one")?.zone === "center", "cross-zone move did not commit")) return;
                window.working=false;
                if (++window.scenario === 4) { console.log("DRIVER_PASS"); Qt.quit(); return; }
                window.step=0; return;
            }
            window.step++;
        }
    }
    Timer { interval: 21500; running: true; onTriggered: { console.log("CHECK_FAIL timeout",window.scenario,window.step); Qt.quit(); } }
}
