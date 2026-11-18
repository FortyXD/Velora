import QtQuick
import qs.modules.common

// Both bar editors use scene coordinates; their widgets can be scaled and arranged in either direction.
Item {
    id: root
    required property var zones
    property bool vertical: false
    property bool dragging: false
    property string excludedUid: ""
    property real crossReach: 24
    property real alongReach: Infinity
    property var target: null
    signal chosen(string zone, int index)
    anchors.fill: parent
    z: 110
    onEnabledChanged: if (!enabled) clear()
    onVerticalChanged: clear()
    onDraggingChanged: clear()
    function clear() { target = null; }

    function overSlot(x, y, tolerance = 0) {
        const slot = target?.slot;
        if (!slot?.visible || !slot.targeted) return false;
        const p = slot.mapFromItem(null, x, y);
        return p.x >= -tolerance && p.x <= slot.width + tolerance && p.y >= -tolerance && p.y <= slot.height + tolerance;
    }
    function use(zone, host, after) {
        if (!zone) { clear(); return null; }
        const all = zone.items;
        const items = excludedUid ? all.filter(i => i.uid !== excludedUid) : all;
        const index = host ? items.findIndex(i => i.uid === host.uid) + Number(after) : 0;
        const slot = host?.editSlot ?? zone.emptySlot;
        if (target?.slot !== slot || target.after !== after || target.index !== index) {
            target = {zone: zone.zoneName, index: index, slot: slot, after: after,
                noop: !!excludedUid && all.findIndex(i => i.uid === excludedUid) === index};
        }
        return target;
    }
    function updateAt(x, y, moving) {
        if (!enabled) { clear(); return null; }
        if (overSlot(x, y, 2)) return target;
        let best = null, bestDistance = Infinity;
        let nearZone = null, nearHost = null, nearAfter = false, edgeDistance = Infinity;
        for (const zone of zones) {
            if (!zone.visible) continue;
            const p = zone.mapFromItem(null, x, y);
            const along = vertical ? p.y : p.x, across = vertical ? p.x : p.y;
            const length = vertical ? zone.height : zone.width, thickness = vertical ? zone.width : zone.height;
            const reach = moving ? crossReach : 1;
            if (across < -reach || across > thickness + reach) continue;
            const distance = Math.max(0, -along, along - length);
            if (moving) {
                if (distance <= alongReach && distance < bestDistance) { best = zone; bestDistance = distance; }
                continue;
            }
            const hosts = zone.orderedHosts();
            if (!hosts.length && Math.abs(along - length / 2) <= 13 && Math.abs(across - thickness / 2) <= 14) {
                nearZone = zone; nearHost = null; nearAfter = false; edgeDistance = 0;
            }
            for (const host of hosts) {
                const q = host.mapFromItem(null, x, y);
                const t = vertical ? q.y : q.x, cross = vertical ? q.x : q.y;
                const size = vertical ? host.height : host.width, depth = vertical ? host.width : host.height;
                if (cross < -2 || cross > depth + 2 || t < -4 || t > size + 4) continue;
                const after = t > size / 2;
                const d = Math.abs(after ? size - t : t);
                if (d <= Math.min(8, size * 0.22) && d < edgeDistance) {
                    nearZone = zone; nearHost = host; nearAfter = after; edgeDistance = d;
                }
            }
        }
        if (!moving) return use(nearZone, nearHost, nearAfter);
        if (!best) return use(null);
        const hosts = best.orderedHosts().filter(h => h.uid !== excludedUid);
        for (const host of hosts) {
            const p = host.mapFromItem(null, x, y);
            if ((vertical ? p.y - host.height / 2 : p.x - host.width / 2) < 0) return use(best, host, false);
        }
        return use(best, hosts[hosts.length - 1], hosts.length > 0);
    }
    HoverHandler {
        id: hover
        enabled: root.enabled && !root.dragging
        onPointChanged: if (hovered) root.updateAt(point.scenePosition.x, point.scenePosition.y, false)
        onHoveredChanged: {
            if (root.dragging) return;
            if (hovered) root.updateAt(point.scenePosition.x, point.scenePosition.y, false);
            else root.clear();
        }
    }
    MouseArea {
        anchors.fill: parent
        enabled: root.enabled && !root.dragging && !!root.target
        acceptedButtons: Qt.LeftButton
        property var pressedSlot: null
        onPressed: mouse => {
            const p = mapToItem(null, mouse.x, mouse.y);
            if (!root.overSlot(p.x, p.y)) { mouse.accepted = false; return; }
            pressedSlot = root.target;
        }
        onClicked: if (pressedSlot && root.target?.slot === pressedSlot.slot) root.chosen(pressedSlot.zone, pressedSlot.index)
        onCanceled: pressedSlot = null
    }

    function capture() {
        const points = new Map();
        if (Appearance.animationSpeed > 0) {
            for (const zone of zones) for (const host of zone.orderedHosts()) {
                points.set(host.uid, host.mapToItem(null, host.width / 2, host.height / 2));
            }
        }
        return points;
    }
    function settle(points, uid, releasePoint) {
        if (uid && releasePoint) points.set(uid, releasePoint);
        if (!points.size || Appearance.animationSpeed <= 0) return;
        layoutFrame.points = points;
        layoutFrame.restart();
    }
    Timer {
        id: layoutFrame
        property var points: null
        interval: 16
        onTriggered: {
            if (!root.enabled || root.dragging) return;
            for (const zone of root.zones) for (const host of zone.orderedHosts()) {
                const previous = points.get(host.uid);
                if (!previous) continue;
                const p = host.mapFromItem(null, previous.x, previous.y);
                const dx = p.x - host.width / 2, dy = p.y - host.height / 2;
                if (Math.abs(dx) + Math.abs(dy) > 1) host.editSlot.settle(dx, dy);
            }
            points = null;
        }
    }
}
