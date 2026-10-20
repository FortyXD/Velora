import QtQuick
import qs.modules.common
import qs.modules.common.widgets

/**
 * Two-step "forget" for a saved network or a paired device: the first click asks
 * (the button turns into a red "Forget"), the second one does it. Settles back after a few seconds.
 */
RippleButton {
    id: root
    property string label: Translation.tr("Forget")
    property bool asking: false

    signal confirmed()

    implicitHeight: 34
    implicitWidth: root.asking ? labelText.implicitWidth + 28 : 34
    buttonRadius: Appearance.rounding.full
    colBackground: root.asking ? Appearance.colors.colErrorContainer : "transparent"
    colBackgroundHover: root.asking ? Appearance.colors.colErrorContainer : Appearance.colors.colLayer3Hover
    colRipple: Appearance.colors.colLayer3Active

    Behavior on implicitWidth {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    onClicked: {
        if (root.asking) {
            root.asking = false;
            root.confirmed();
        } else {
            root.asking = true;
            settleTimer.restart();
        }
    }

    Timer {
        id: settleTimer
        interval: 4000
        onTriggered: root.asking = false
    }

    contentItem: Item {
        MaterialSymbol {
            anchors.centerIn: parent
            visible: !root.asking
            text: "delete"
            iconSize: 19
            color: Appearance.colors.colSubtext
        }
        StyledText {
            id: labelText
            anchors.centerIn: parent
            visible: root.asking
            text: root.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colOnErrorContainer
        }
    }

    StyledToolTip {
        text: root.label
        extraVisibleCondition: !root.asking
    }
}
