import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire

/**
 * Chip that appears while an app uses the microphone, a camera or captures the screen.
 * Hover it to see which apps.
 */
MouseArea {
    id: root
    readonly property bool shown: Config.options.bar.indicators.privacy && Privacy.anyActive
    // Recognisable hues, pulled slightly toward the palette so they don't clash with the theme
    readonly property color micColor: ColorUtils.mix("#F29D38", Appearance.colors.colPrimary, 0.8)
    readonly property color cameraColor: ColorUtils.mix("#4CC26B", Appearance.colors.colPrimary, 0.8)
    readonly property color screenColor: Appearance.colors.colPrimary
    readonly property color accent: Privacy.screenSharing ? screenColor : Privacy.cameraActive ? cameraColor : micColor

    component PrivacyIcon: MaterialSymbol {
        required property bool active
        visible: active
        fill: 1
        iconSize: Appearance.font.pixelSize.large
    }

    hoverEnabled: !Config.options.bar.tooltips.clickToShow
    implicitWidth: revealer.implicitWidth
    implicitHeight: Appearance.sizes.baseBarHeight
    readonly property bool barVisible: root.shown || revealer.implicitWidth > 0
    visible: barVisible

    Revealer {
        id: revealer
        anchors.verticalCenter: parent.verticalCenter
        reveal: root.shown

        Rectangle {
            id: chip
            implicitWidth: iconRow.implicitWidth + 14
            implicitHeight: 24
            radius: height / 2
            color: ColorUtils.transparentize(root.accent, 0.82)
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            Row {
                id: iconRow
                anchors.centerIn: parent
                spacing: 2

                PrivacyIcon {
                    active: Privacy.micActive
                    text: "mic"
                    color: root.micColor
                }
                PrivacyIcon {
                    active: Privacy.cameraActive
                    text: "videocam"
                    color: root.cameraColor
                }
                PrivacyIcon {
                    active: Privacy.screenSharing
                    text: "screen_share"
                    color: root.screenColor
                }
            }
        }
    }

    // A single pop when something starts capturing
    onShownChanged: if (shown && Config.options.bar.microAnimations) popAnimation.restart()
    SequentialAnimation {
        id: popAnimation
        NumberAnimation { target: chip; property: "scale"; from: 0.6; to: 1.12; duration: 220; easing.type: Easing.OutCubic }
        NumberAnimation { target: chip; property: "scale"; to: 1; duration: 200; easing.type: Easing.InOutSine }
    }

    StyledPopup {
        hoverTarget: root

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 4

            // Full node properties (app names) are only available for tracked nodes
            PwObjectTracker {
                objects: [...Privacy.micClients, ...Privacy.cameraClients, ...Privacy.screenClients]
            }

            StyledPopupHeaderRow {
                icon: "privacy_tip"
                label: Translation.tr("In use")
            }

            Repeater {
                model: Privacy.micClients
                delegate: StyledPopupValueRow {
                    required property var modelData
                    icon: "mic"
                    label: Translation.tr("Microphone:")
                    value: Privacy.appName(modelData)
                }
            }
            Repeater {
                model: Privacy.cameraClients
                delegate: StyledPopupValueRow {
                    required property var modelData
                    icon: "videocam"
                    label: Translation.tr("Camera:")
                    value: Privacy.appName(modelData)
                }
            }
            Repeater {
                model: Privacy.screenClients
                delegate: StyledPopupValueRow {
                    required property var modelData
                    icon: "screen_share"
                    label: Translation.tr("Screen:")
                    value: Privacy.appName(modelData)
                }
            }
        }
    }
}
