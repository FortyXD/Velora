import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Effects
import QtQuick.Window

/**
 * One dock slot. It takes its resting size in the layout and draws its icon
 * magnified and shifted around the cursor, so the layout never has to change
 * while the pointer moves.
 */
Item {
    id: root

    required property DockContext dock
    property real baseCenter: x + width / 2 // Resting center in row coordinates
    property real slotWidth: separator ? dock.separatorWidth : dock.slotWidth
    property real appear: 1 // Goes 0 -> 1 when the tile is added and back when it is removed
    property bool separator: false
    property bool magnify: !separator
    property bool tint: false
    property string label: ""
    property bool showIndicator: false
    property bool indicatorActive: false
    property bool bouncing: false // Keeps bouncing while true, like an app that is starting
    property int attentionBounces: 0
    default property alias content: iconHolder.data

    readonly property alias hovered: mouseArea.containsMouse
    readonly property alias pressed: mouseArea.pressed
    readonly property real magnification: magnify ? dock.scaleAt(baseCenter) : 1
    readonly property real shift: dock.shiftAt(baseCenter)
    readonly property real visualCenter: baseCenter + shift
    readonly property real visualTop: height - dock.bottomPadding - dock.iconSize * magnification * appear
    property real bounceOffset: 0
    property real pressAmount: mouseArea.pressed && mouseArea.pressedButtons & Qt.LeftButton && !separator ? 1 : 0

    signal clicked()
    signal middleClicked()
    signal rightClicked()

    implicitWidth: slotWidth * appear
    implicitHeight: dock.barHeight

    onHoveredChanged: {
        if (hovered) dock.hoveredTile = root;
        else if (dock.hoveredTile === root) dock.hoveredTile = null;
    }

    Behavior on pressAmount {
        NumberAnimation {
            duration: 120
            easing.type: Easing.OutCubic
        }
    }

    Item {
        id: visual
        width: root.dock.iconSize
        height: root.dock.iconSize
        x: (root.width - width) / 2
        y: root.height - root.dock.bottomPadding - height
        opacity: root.appear
        transform: [
            Scale {
                origin.x: visual.width / 2
                origin.y: visual.height
                xScale: root.magnification * root.appear
                yScale: root.magnification * root.appear
            },
            Translate {
                x: root.shift
                y: -root.bounceOffset
            }
        ]

        Item {
            id: iconHolder
            anchors.fill: parent
            // Render the effect at the largest magnified size so it stays sharp
            layer.enabled: root.tint || root.pressAmount > 0
            layer.textureSize: Qt.size(width * root.dock.maxScale * Screen.devicePixelRatio, height * root.dock.maxScale * Screen.devicePixelRatio)
            layer.smooth: true
            layer.effect: MultiEffect {
                saturation: root.tint ? -0.8 : 0
                colorization: root.tint ? 0.12 : 0
                colorizationColor: Appearance.colors.colPrimary
                brightness: -0.35 * root.pressAmount
            }
        }

        Rectangle {
            visible: root.separator
            anchors.centerIn: parent
            width: 1
            height: parent.height * 0.8
            color: Appearance.colors.colOutlineVariant
        }

        MouseArea {
            id: mouseArea
            // Covers the whole column of the slot, so the label doesn't flicker between icons
            anchors {
                fill: parent
                leftMargin: -root.dock.gap / 2
                rightMargin: -root.dock.gap / 2
                topMargin: -root.dock.topPadding
                bottomMargin: -root.dock.bottomPadding
            }
            hoverEnabled: !root.separator
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            onPressed: mouse => {
                if (mouse.button === Qt.RightButton) root.rightClicked();
            }
            onClicked: mouse => {
                if (mouse.button === Qt.LeftButton) root.clicked();
                else if (mouse.button === Qt.MiddleButton) root.middleClicked();
            }
        }
    }

    Rectangle {
        id: indicator
        width: 5
        height: 5
        radius: width / 2
        x: (root.width - width) / 2 + root.shift
        y: root.height - root.dock.bottomPadding / 2 - height / 2
        color: root.indicatorActive ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.45)
        opacity: root.showIndicator ? root.appear : 0
        scale: root.showIndicator ? 1 : 0.3
        Behavior on opacity {
            NumberAnimation {
                duration: 200
                easing.type: Easing.OutCubic
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: 260
                easing.type: Easing.OutBack
            }
        }
        Behavior on color {
            ColorAnimation {
                duration: 200
            }
        }
    }

    // Bounce: up with deceleration, down with gravity, short rest between hops
    SequentialAnimation {
        id: bounceAnim
        NumberAnimation {
            target: root
            property: "bounceOffset"
            to: root.dock.bounceHeight
            duration: 300
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: root
            property: "bounceOffset"
            to: 0
            duration: 300
            easing.type: Easing.InQuad
        }
        PauseAnimation {
            duration: 90
        }
        onFinished: {
            if (root.attentionBounces > 0) root.attentionBounces--;
            Qt.callLater(root.continueBouncing);
        }
    }

    function continueBouncing() {
        if ((root.bouncing || root.attentionBounces > 0) && !bounceAnim.running) bounceAnim.start();
    }

    onBouncingChanged: continueBouncing()
    onAttentionBouncesChanged: continueBouncing()
    Component.onCompleted: continueBouncing()
}
