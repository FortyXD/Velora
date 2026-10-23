import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.panels.lock

/**
 * Everything on the lock screen, placed by services/LockLayout.qml. The same scene is the real lock
 * screen (with a context), the full-size editor and the miniature in the settings app, so what you
 * arrange is what you get.
 *   context      LockContext on the real lock screen; null elsewhere (nothing can be typed or pressed)
 *   liveData     real music, notifications, battery…; off in the settings app, which shows examples
 *   editing      outlines, dragging with guides; parts without content show a placeholder
 *   showBackdrop draws the blurred wallpaper itself (the real lock screen has Background.qml for that)
 */
Item {
    id: root
    property var context: null
    property bool liveData: true
    property bool editing: false
    property bool showBackdrop: false
    property bool playVideo: false
    property real editScale: 1 // How big the scene is drawn, for outlines and snapping
    property string selectedId: ""
    property bool exiting: false
    property bool startHidden: false // Parts wait for playEntrance()
    readonly property string animations: (PowerSaving.cutAnimations && Config.options.lock.animations === "full") ? "calm" : Config.options.lock.animations
    readonly property alias passwordBar: passwordBar

    signal elementSelected(string id)
    signal elementMoved(string id, real x, real y)
    signal elementReset(string id)

    readonly property var hosts: ({
        "clock": clockHost, "greeting": greetingHost, "password": passwordHost, "user": userHost, "power": powerHost,
        "message": messageHost, "media": mediaHost, "weather": weatherHost, "notifications": notificationsHost, "timer": timerHost
    })

    function host(id) {
        return root.hosts[id] ?? null;
    }

    function selectElement(id) {
        root.selectedId = id;
        root.elementSelected(id);
    }

    // `clockFrom`: where the desktop clock was (screen coordinates), so the lock clock glides from there
    function playEntrance(clockFrom) {
        for (const id of LockElementCatalog.ids) root.host(id)?.startEntrance(id === "clock" ? clockFrom : null);
    }

    onExitingChanged: {
        if (!root.exiting) return;
        for (const id of LockElementCatalog.ids) root.host(id)?.startExit();
    }

    // ---- Placement ----

    readonly property real margin: 16
    function clampCenter(point, w, h) {
        const x = Math.max(root.margin + w / 2, Math.min(root.width - root.margin - w / 2, point.x));
        const y = Math.max(root.margin + h / 2, Math.min(root.height - root.margin - h / 2, point.y));
        return Qt.point(x, y);
    }

    // User and power sit on the sides of the password field, the message above it
    function attachedCenter(id, w, h) {
        const p = passwordHost.center;
        const pw = passwordHost.visualWidth;
        const ph = passwordHost.visualHeight;
        if (id === "user") return Qt.point(p.x - pw / 2 - 10 - w / 2, p.y);
        if (id === "power") return Qt.point(p.x + pw / 2 + 10 + w / 2, p.y);
        return Qt.point(p.x, p.y - ph / 2 - 16 - h / 2);
    }

    // Guides while dragging: the middle and thirds of the screen, and the middles of the other parts
    property real guideX: -1
    property real guideY: -1
    function snap(movingHost, point) {
        const threshold = 10 / root.editScale;
        let xs = [root.width / 2, root.width / 3, root.width * 2 / 3];
        let ys = [root.height / 2, root.height / 3, root.height * 2 / 3];
        for (const id of LockElementCatalog.ids) {
            const other = root.host(id);
            if (!other || other === movingHost || !other.shown || other.attached) continue;
            xs.push(other.center.x);
            ys.push(other.center.y);
        }
        const nearest = (value, candidates) => candidates.reduce((best, c) => Math.abs(c - value) < Math.abs(best - value) ? c : best, candidates[0]);
        const nx = nearest(point.x, xs);
        const ny = nearest(point.y, ys);
        root.guideX = Math.abs(nx - point.x) < threshold ? nx : -1;
        root.guideY = Math.abs(ny - point.y) < threshold ? ny : -1;
        return Qt.point(root.guideX >= 0 ? nx : point.x, root.guideY >= 0 ? ny : point.y);
    }
    function clearGuides() {
        root.guideX = -1;
        root.guideY = -1;
    }

    // ---- Content ----

    Loader {
        anchors.fill: parent
        active: root.showBackdrop
        sourceComponent: LockBackdrop {
            playVideo: root.playVideo
        }
    }

    // Click on empty space: nothing selected
    MouseArea {
        anchors.fill: parent
        enabled: root.editing
        visible: enabled
        onPressed: root.selectElement("")
    }

    LockElementHost {
        id: clockHost
        elementId: "clock"
        scene: root
        LockClock {}
    }
    LockElementHost {
        id: greetingHost
        elementId: "greeting"
        scene: root
        LockGreeting {}
    }
    LockElementHost {
        id: passwordHost
        elementId: "password"
        scene: root
        LockPasswordBar {
            id: passwordBar
            context: root.context
        }
    }
    LockElementHost {
        id: userHost
        elementId: "user"
        scene: root
        hasContent: userChip.hasContent
        LockUserChip {
            id: userChip
            liveData: root.liveData
        }
    }
    LockElementHost {
        id: powerHost
        elementId: "power"
        scene: root
        hasContent: powerChip.hasContent
        LockPowerChip {
            id: powerChip
            context: root.context
            liveData: root.liveData
        }
    }
    LockElementHost {
        id: messageHost
        elementId: "message"
        scene: root
        hasContent: lockMessage.hasContent && !inputWarning.shown
        LockMessage {
            id: lockMessage
        }
    }
    LockElementHost {
        id: mediaHost
        elementId: "media"
        scene: root
        hasContent: lockMedia.hasContent || !root.liveData
        LockMedia {
            id: lockMedia
            liveData: root.liveData
            placeholder: root.editing
            wanted: mediaHost.item.show
        }
    }
    LockElementHost {
        id: weatherHost
        elementId: "weather"
        scene: root
        hasContent: lockWeather.hasContent || !root.liveData
        LockWeather {
            id: lockWeather
            showHours: weatherHost.item.hours ?? false
        }
    }
    LockElementHost {
        id: notificationsHost
        elementId: "notifications"
        scene: root
        hasContent: lockNotifications.hasContent
        LockNotifications {
            id: lockNotifications
            liveData: root.liveData
        }
    }
    LockElementHost {
        id: timerHost
        elementId: "timer"
        scene: root
        hasContent: lockTimer.hasContent
        LockTimer {
            id: lockTimer
            liveData: root.liveData
        }
    }

    // Why the password may be rejected: lockout from PAM, wrong layout, Caps Lock
    Rectangle {
        id: inputWarning
        readonly property string message: !root.context ? ""
            : root.context.pamNotice.length > 0 ? root.context.pamNotice
            : root.context.nonLatinInput ? Translation.tr("Not typing in Latin letters. Check the keyboard layout (%1)").arg(HyprlandXkb.currentLayoutCode)
            : root.context.capsLock ? Translation.tr("Caps Lock is on")
            : ""
        readonly property bool shown: message.length > 0
        property string shownMessage: ""
        onMessageChanged: if (message.length > 0) shownMessage = message

        x: Math.round(passwordHost.center.x - width / 2)
        y: Math.round(passwordHost.center.y - passwordHost.visualHeight / 2 - 12 - height)
        z: 3
        implicitWidth: warningRow.implicitWidth + 28
        implicitHeight: warningRow.implicitHeight + 14
        radius: height / 2
        color: Appearance.colors.colErrorContainer
        opacity: shown ? passwordHost.opacity : 0
        visible: opacity > 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        Row {
            id: warningRow
            anchors.centerIn: parent
            spacing: 8
            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                fill: 1
                text: (root.context?.pamNotice.length ?? 0) > 0 ? "lock_clock" : "warning"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnErrorContainer
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: inputWarning.shownMessage
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnErrorContainer
            }
        }
    }

    // Guides
    Rectangle {
        visible: root.editing && root.guideX >= 0
        x: root.guideX - width / 2
        width: 1.5 / root.editScale
        height: root.height
        color: Appearance.colors.colPrimary
        z: 5
    }
    Rectangle {
        visible: root.editing && root.guideY >= 0
        y: root.guideY - height / 2
        width: root.width
        height: 1.5 / root.editScale
        color: Appearance.colors.colPrimary
        z: 5
    }
}
