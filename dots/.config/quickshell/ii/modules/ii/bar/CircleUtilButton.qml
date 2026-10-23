import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell

/**
 * Small round bar button with a Material icon.
 * Lights up while its feature is on (toggled; urgent uses error colors) and shrinks a little while pressed.
 */
RippleButton {
    id: button

    property string iconName
    property real iconFill: toggled ? 1 : 0
    property bool urgent: false
    property string tooltipText
    property color iconColor: !toggled ? Appearance.colors.colOnLayer2
        : urgent ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSecondaryContainer
    readonly property bool animate: Config.options.bar.microAnimations && !PowerSaving.cutAnimations

    implicitHeight: 26
    implicitWidth: implicitHeight

    colBackgroundToggled: urgent ? Appearance.colors.colErrorContainer : Appearance.colors.colSecondaryContainer
    colBackgroundToggledHover: urgent ? Appearance.colors.colErrorContainerHover : Appearance.colors.colSecondaryContainerHover
    colRippleToggled: urgent ? Appearance.colors.colErrorContainerActive : Appearance.colors.colSecondaryContainerActive

    scale: down && animate ? 0.86 : 1
    Behavior on scale {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    contentItem: Item {
        MaterialSymbol {
            id: iconSymbol
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            fill: button.iconFill
            iconSize: Appearance.font.pixelSize.large
            color: button.iconColor
            Component.onCompleted: text = button.iconName

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }

    // Swap icons with a quick shrink and pop instead of an instant replace
    onIconNameChanged: {
        if (!animate) {
            iconSymbol.text = iconName;
            return;
        }
        iconSwap.restart();
    }
    SequentialAnimation {
        id: iconSwap
        ParallelAnimation {
            NumberAnimation { target: iconSymbol; property: "scale"; to: 0.4; duration: 90; easing.type: Easing.InQuad }
            NumberAnimation { target: iconSymbol; property: "opacity"; to: 0; duration: 90 }
        }
        ScriptAction { script: iconSymbol.text = button.iconName }
        ParallelAnimation {
            NumberAnimation { target: iconSymbol; property: "scale"; to: 1; duration: 220; easing.type: Easing.OutBack }
            NumberAnimation { target: iconSymbol; property: "opacity"; to: 1; duration: 140 }
        }
    }

    // Tooltip after a short hover, so moving across the bar doesn't flash them
    property bool hoverSettled: false
    onHoveredChanged: if (!hovered) hoverSettled = false
    Timer {
        running: button.hovered && button.tooltipText.length > 0
        interval: 600
        onTriggered: button.hoverSettled = true
    }
    PopupToolTip {
        extraVisibleCondition: button.hoverSettled
        text: button.tooltipText
        anchorEdges: Config.options.bar.bottom ? Edges.Top : Edges.Bottom
    }
}
