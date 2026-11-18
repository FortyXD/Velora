import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Item {
    id: root
    required property bool shown
    property real progress: 1
    readonly property int enterDuration: Appearance.animation.elementMoveEnter.duration
    Layout.fillWidth: true
    implicitHeight: 112

    function replay() {
        enter.stop();
        progress = 1;
        if (shown && enterDuration > 0)
            enter.start();
    }
    onShownChanged: replay()
    onEnterDurationChanged: if (shown) replay()

    NumberAnimation {
        id: enter
        target: root
        property: "progress"
        from: 0
        to: 1
        duration: root.enterDuration
        easing.type: Appearance.animation.elementMoveEnter.type
        easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
    }

    Rectangle {
        id: stage
        x: 10; y: 8
        width: root.width - 20
        height: root.height - 16
        radius: Appearance.rounding.small
        color: ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colLayer2Base, 0.08)
        clip: true

        Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(40, (parent.width - 76) * 0.59)
            height: 60
            radius: 7
            color: Appearance.colors.colLayer2Base
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant
            Column {
                x: 9; y: 10; spacing: 5
                Repeater {
                    model: [0.42, 0.74, 0.58]
                    Rectangle {
                        required property real modelData
                        width: (parent.parent.width - 18) * modelData
                        height: 4; radius: 2
                        color: ColorUtils.mix(Appearance.colors.colSubtext, Appearance.colors.colLayer2Base, 0.38)
                    }
                }
            }
        }
        Rectangle {
            readonly property real endX: (stage.width - 76) * 0.53
            x: endX + (1 - root.progress) * width * 0.7
            y: 25 + (1 - root.progress) * 12
            width: Math.max(50, (stage.width - 76) * 0.45)
            height: 58; radius: 8
            scale: 0.92 + 0.08 * root.progress
            opacity: root.progress
            color: ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colLayer2Base, 0.30)
            border.width: 1
            border.color: ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colPrimaryContainer, 0.5)
            Column {
                x: 11; y: 11; spacing: 6
                Rectangle { width: parent.parent.width * 0.37; height: 6; radius: 3; color: Appearance.colors.colPrimary }
                Rectangle { width: parent.parent.width * 0.63; height: 4; radius: 2; color: ColorUtils.applyAlpha(Appearance.colors.colOnLayer2, 0.50) }
                Rectangle { width: parent.parent.width * 0.48; height: 4; radius: 2; color: ColorUtils.applyAlpha(Appearance.colors.colOnLayer2, 0.35) }
            }
        }
        RippleButton {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: 38
            implicitHeight: 38
            buttonRadius: 19
            enabled: root.enterDuration > 0
            Accessible.name: Translation.tr("Replay animation")
            colBackground: Appearance.colors.colLayer2Base
            colBackgroundHover: Appearance.colors.colLayer2Hover
            onClicked: root.replay()
            contentItem: MaterialSymbol {
                text: "replay"
                iconSize: 20
                horizontalAlignment: Text.AlignHCenter
                color: Appearance.colors.colOnLayer2
            }
            StyledToolTip { text: Translation.tr("Replay animation") }
        }
    }
}
