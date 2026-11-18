import QtQuick
import QtTest
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

FloatingWindow {
    id: window
    implicitWidth: 398
    implicitHeight: 340
    property int step: 0
    property bool sampled: false
    property var originalFront
    property point originalPosition
    readonly property var messages: Array.from({length: 27}, (_, i) => ({
        notificationId:i+1, summary:"Сообщение " + (i+1),
        body:i % 2 ? "Короткое сообщение." : "Подробное сообщение со второй строкой, чтобы проверить карточки разной высоты.",
        actions:[], time: Date.now()-60000*(27-i)
    }))
    function fail(msg) { console.log("CHECK_FAIL",step,msg); Qt.quit(); }
    TestCase { id: input; when: false }
    StyledListView {
        id: feed; anchors.fill: parent; clip: true; model: 1
        delegate: NotificationGroup {
            required property int index
            width: ListView.view.width
            notificationGroup: ({appName:"Чат", notifications:window.messages})
        }
    }
    Timer {
        interval: 12; repeat: true; running: window.step === 2
        onTriggered: {
            const g=feed.itemAtIndex(0);
            if (g.reveal > 0.05 && g.reveal < 0.95 && g.revealedHeight > 5 && g.revealedHeight < g.fullHistoryHeight) window.sampled=true;
        }
    }
    Timer {
        interval: 360; repeat: true; running: true
        onTriggered: {
            const g=feed.itemAtIndex(0);
            if (!g || !Config.ready) return;
            const history=input.findChild(g,"notificationHistory");
            switch (window.step) {
            case 0:
                Config.options.appearance.animationSpeed=1;
                window.originalFront=input.findChild(g,"notificationFront");
                if (!window.originalFront) { window.fail("front card"); return; }
                window.originalPosition=window.originalFront.mapToItem(feed,0,0);
                break;
            case 1:
                input.mouseClick(window.originalFront,100,30); break;
            case 2: {
                if (!g.expanded || !window.sampled) { window.fail("no reveal frames"); return; }
                const p=window.originalFront.mapToItem(feed,0,0);
                if (p.x!==window.originalPosition.x || p.y!==window.originalPosition.y) { window.fail("front moved"); return; }
                const count=Array.from({length:history.count},(_,i)=>history.itemAtIndex(i)).filter(Boolean).length;
                if (count < 2 || count >= history.count || g.messages.length !== 27) { window.fail("materialized "+count+"/"+history.count); return; }
                feed.positionViewAtEnd(); break;
            }
            case 3:
                if (history.itemAtIndex(25)?.notificationObject.notificationId !== 1) { window.fail("oldest message not reachable "+[history.viewportStart,history.implicitHeight,feed.contentY,feed.contentHeight,feed.height,g.height,g.y,g.reveal,history.count,history.itemAtIndex(25)?.notificationObject.notificationId]); return; }
                feed.positionViewAtBeginning(); break;
            case 4: {
                const button=input.findChild(window.originalFront,"notificationDisclosure");
                input.mouseClick(button,button.width/2,button.height/2); break;
            }
            case 5:
                if (g.expanded || g.reveal !== 0 || history.count !== 0 || window.originalFront.notificationObject.notificationId!==27) { window.fail("collapse did not release history"); return; }
                console.log("DRIVER_PASS"); Qt.quit(); return;
            }
            window.step++;
        }
    }
    Timer { interval: 7000; running:true; onTriggered:window.fail("timeout") }
}
