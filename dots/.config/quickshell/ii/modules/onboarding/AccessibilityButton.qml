import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Accessibility, on every step as on macOS: less motion and the on-screen keyboard, before anything
 * else is asked.
 */
Item {
    id: root
    required property var flow
    property bool open: false
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    RippleButton {
        id: button
        implicitWidth: 44
        implicitHeight: 44
        buttonRadius: height / 2
        toggled: root.open
        colBackgroundToggled: Appearance.colors.colSecondaryContainer
        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
        onClicked: root.open = !root.open
        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            text: "accessibility_new"
            iconSize: 24
            color: root.open ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer0
        }
    }

    StyledRectangularShadow {
        target: panel
        visible: panel.visible
    }
    Rectangle {
        id: panel
        anchors.bottom: button.top
        anchors.bottomMargin: 10
        anchors.left: button.left
        width: 320
        height: column.implicitHeight + 24
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant
        visible: opacity > 0
        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.94
        transformOrigin: Item.BottomLeft
        Behavior on opacity {
            NumberAnimation { duration: Motion.ms(180) }
        }
        Behavior on scale {
            NumberAnimation { duration: Motion.ms(260); easing.type: Easing.OutCubic }
        }

        ColumnLayout {
            id: column
            anchors.fill: parent
            anchors.margins: 12
            spacing: 4
            ConfigSwitch {
                buttonIcon: "motion_photos_off"
                text: Translation.tr("Less motion")
                checked: Motion.reduced
                onCheckedChanged: {
                    if (checked === Motion.reduced) return;
                    Motion.reduced = checked;
                    root.flow.setConfig("appearance.animationSpeed", checked ? 0 : 1);
                }
            }
            RippleButton {
                Layout.fillWidth: true
                implicitHeight: 44
                buttonRadius: Appearance.rounding.normal
                onClicked: root.flow.shell("osk", "toggle")
                contentItem: RowLayout {
                    spacing: 12
                    MaterialSymbol {
                        Layout.leftMargin: 10
                        text: "keyboard"
                        iconSize: 22
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("On-screen keyboard")
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }
        }
    }
}
