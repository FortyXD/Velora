import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * A widget on the bar canvas, drawn roughly like the real one: its icon, and for a few types what
 * they show (the time, the charge, workspace dots). Click selects it; dragging past a few pixels
 * reports scene positions so the page can move it.
 */
Item {
    id: root
    required property var itemData
    property bool vertical: false
    property bool selected: false
    property bool dimmed: false
    property color contentColor: Appearance.colors.colOnLayer0
    readonly property var meta: BarWidgetCatalog.get(root.itemData.type)
    readonly property string type: root.itemData.type
    readonly property bool hovered: mouseArea.containsMouse && !mouseArea.dragging
    readonly property bool elastic: !!root.meta?.elastic && root.type !== "spacer"

    signal clicked()
    signal dragStarted(real sceneX, real sceneY, real offsetX, real offsetY)
    signal dragMoved(real sceneX, real sceneY)
    signal dragEnded(real sceneX, real sceneY)

    // What it shows next to the icon on a horizontal bar
    readonly property string liveText: {
        if (root.vertical) return "";
        switch (root.type) {
        case "clock": return DateTime.time;
        case "battery": return Battery.available ? `${Math.round(Battery.percentage * 100)}%` : "";
        case "activeWindow": return Translation.tr("Window title");
        case "media":
        case "island": return Translation.tr("Now playing");
        case "text": return root.itemData.options?.text ?? "";
        case "customCommand": return "$ " + (root.itemData.options?.command ?? "").split(" ")[0];
        case "networkSpeed": return "↓ 1.2 MB/s";
        case "weather": return "18°";
        default: return "";
        }
    }
    readonly property string icon: root.type === "battery" ? (Battery.isCharging ? "battery_charging_full" : "battery_full")
        : root.type === "appButton" ? (root.itemData.options?.icon || "terminal")
        : (root.meta?.icon ?? "help")
    readonly property real base: 30

    implicitWidth: root.vertical ? root.base
        : root.type === "workspaces" ? 92
        : root.type === "separator" ? 9
        : root.type === "spacer" ? 34
        : Math.max(root.base, content.implicitWidth + (root.liveText.length > 0 ? 18 : 8)) + (root.elastic ? 40 : 0)
    implicitHeight: !root.vertical ? root.base
        : root.type === "workspaces" ? 92
        : root.type === "separator" ? 9
        : root.type === "spacer" ? 26
        : root.type === "clock" ? 44
        : root.base
    opacity: root.dimmed ? 0.3 : 1

    Rectangle { // Selection and hover
        anchors.fill: parent
        radius: Math.min(width, height) / 2
        color: root.selected ? Appearance.colors.colPrimary
            : root.hovered ? ColorUtils.transparentize(root.contentColor, 0.86) : "transparent"
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    readonly property color drawColor: root.selected ? Appearance.colors.colOnPrimary : root.contentColor

    // Workspaces: a row (column) of dots with the current one stretched
    Grid {
        visible: root.type === "workspaces"
        anchors.centerIn: parent
        columns: root.vertical ? 1 : 5
        spacing: 6
        Repeater {
            model: 5
            Rectangle {
                required property int index
                readonly property bool current: index === 1
                width: root.vertical ? 8 : (current ? 20 : 8)
                height: root.vertical ? (current ? 20 : 8) : 8
                radius: 4
                color: current ? (root.selected ? Appearance.colors.colOnPrimary : Appearance.colors.colPrimary)
                    : ColorUtils.transparentize(root.drawColor, index === 0 || index === 3 ? 0.3 : 0.65)
            }
        }
    }

    // Separator and flexible space
    Rectangle {
        visible: root.type === "separator"
        anchors.centerIn: parent
        width: root.vertical ? 16 : 1
        height: root.vertical ? 1 : 16
        color: ColorUtils.transparentize(root.drawColor, 0.5)
    }
    Rectangle {
        visible: root.type === "spacer"
        anchors.fill: parent
        anchors.margins: 3
        radius: 6
        color: "transparent"
        border.width: 1
        border.color: ColorUtils.transparentize(root.drawColor, 0.55)
        MaterialSymbol {
            anchors.centerIn: parent
            text: root.vertical ? "unfold_more" : "unfold_more_double"
            rotation: root.vertical ? 0 : 90
            iconSize: 14
            color: ColorUtils.transparentize(root.drawColor, 0.4)
        }
    }

    // Everything else: icon, maybe a value
    GridLayout {
        id: content
        visible: !["workspaces", "separator", "spacer"].includes(root.type)
        anchors.centerIn: parent
        columns: root.vertical ? 1 : 2
        rowSpacing: 0
        columnSpacing: 4
        MaterialSymbol {
            visible: !(root.vertical && root.type === "clock")
            Layout.alignment: Qt.AlignCenter
            text: root.meta ? root.icon : "error"
            iconSize: 18
            fill: root.selected ? 1 : 0
            color: root.meta ? root.drawColor : Appearance.colors.colError
        }
        StyledText {
            visible: root.liveText.length > 0 || (root.vertical && root.type === "clock")
            Layout.alignment: Qt.AlignCenter
            Layout.maximumWidth: 120
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            text: root.vertical ? DateTime.time.replace(":", "\n") : root.liveText
            lineHeight: 0.9
            font.pixelSize: Appearance.font.pixelSize.small
            font.family: Appearance.font.family.numbers
            color: root.drawColor
        }
    }

    Rectangle { // Hidden on narrow screens
        visible: (root.itemData.hideAt ?? 0) > 0
        anchors {
            right: parent.right
            top: parent.top
            margins: 1
        }
        width: 6
        height: 6
        radius: 3
        color: Appearance.colors.colTertiary
    }

    StyledToolTip {
        extraVisibleCondition: !mouseArea.dragging
        text: (root.meta?.name ?? root.type) + ((root.itemData.hideAt ?? 0) > 0 ? ` · ${Translation.tr("Hidden on narrow screens")}` : "")
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        cursorShape: dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor

        property bool dragging: false
        property real pressX
        property real pressY

        onPressed: mouse => {
            pressX = mouse.x;
            pressY = mouse.y;
            dragging = false;
        }
        onPositionChanged: mouse => {
            if (!pressed) return;
            const scene = mapToItem(null, mouse.x, mouse.y);
            if (!dragging) {
                if (Math.abs(mouse.x - pressX) + Math.abs(mouse.y - pressY) < 6) return;
                dragging = true;
                root.dragStarted(scene.x, scene.y, pressX, pressY);
            }
            root.dragMoved(scene.x, scene.y);
        }
        onReleased: mouse => {
            const scene = mapToItem(null, mouse.x, mouse.y);
            if (dragging) {
                dragging = false;
                root.dragEnded(scene.x, scene.y);
            } else {
                root.clicked();
            }
        }
        onCanceled: {
            if (dragging) {
                dragging = false;
                root.dragEnded(-1, -1);
            }
        }
    }
}
