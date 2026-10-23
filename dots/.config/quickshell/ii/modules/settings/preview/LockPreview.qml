import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * The lock screen in miniature, following Config.options.lock as it changes: blur and dimming, where the clock
 * sits, the "Locked" text and message, and what the bottom bars show.
 */
MiniScreen {
    id: root
    readonly property var lock: Config.options.lock
    readonly property real unit: root.width / 100 // Sizes scale with the preview
    scrim: 0

    FastBlur {
        anchors.fill: parent
        visible: root.lock.blur.enable
        source: root.wallpaperItem
        radius: Math.min(64, root.lock.blur.radius / 4)
        transform: Scale {
            origin.x: root.width / 2
            origin.y: root.height / 2
            xScale: root.lock.blur.extraZoom
            yScale: root.lock.blur.extraZoom
        }
    }
    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colLayer0
        opacity: Math.max(0, Math.min(0.8, root.lock.dim))
    }

    // Clock, in the middle or where the desktop clock is
    Column {
        id: clockColumn
        readonly property bool centered: root.lock.centerClock
        x: centered ? (root.width - width) / 2 : root.unit * 7
        y: centered ? root.height * 0.24 : root.unit * 6
        spacing: root.unit * 0.6
        Behavior on x {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on y {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        StyledText {
            anchors.horizontalCenter: clockColumn.centered ? parent.horizontalCenter : undefined
            text: DateTime.time
            font.pixelSize: Math.max(10, root.unit * 9)
            font.family: Config.options.background.widgets.clock.styleLocked === "digital" ? Appearance.font.family.expressive : Appearance.font.family.title
            font.variableAxes: ({ "wght": 600 })
            color: Appearance.colors.colOnLayer0
        }
        StyledText {
            visible: root.lock.showLockedText
            anchors.horizontalCenter: clockColumn.centered ? parent.horizontalCenter : undefined
            text: Translation.tr("Locked")
            font.pixelSize: Math.max(7, root.unit * 2.2)
            color: Appearance.colors.colOnLayer0
        }
    }

    // The bars with the password field
    Item {
        id: bars
        width: parent.width
        height: root.unit * 5
        y: root.lock.passwordPosition === "center" ? root.height * 0.7 - height : root.height - height - root.unit * 2
        Behavior on y {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        StyledText {
            visible: root.lock.message.length > 0
            anchors {
                horizontalCenter: parent.horizontalCenter
                bottom: parent.top
                bottomMargin: root.unit * 1.2
            }
            width: Math.min(implicitWidth, root.width * 0.6)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: root.lock.message
            font.pixelSize: Math.max(7, root.unit * 1.8)
            color: Appearance.colors.colOnLayer0
        }

        Row {
            anchors.centerIn: parent
            height: parent.height
            spacing: root.unit

            component Pill: Rectangle {
                height: bars.height
                radius: height / 2
                color: Appearance.colors.colLayer1
            }
            component PillIcon: MaterialSymbol {
                anchors.verticalCenter: parent?.verticalCenter
                iconSize: Math.max(7, root.unit * 2.4)
                fill: 1
                color: Appearance.colors.colOnSurfaceVariant
            }

            Pill { // User and keyboard layout
                visible: root.lock.showUser || root.lock.showKeyboardLayout
                width: leftRow.implicitWidth + root.unit * 3
                Row {
                    id: leftRow
                    anchors.centerIn: parent
                    spacing: root.unit
                    PillIcon { visible: root.lock.showUser; text: "account_circle" }
                    PillIcon { visible: root.lock.showKeyboardLayout; text: "keyboard_alt" }
                }
            }
            Pill { // Password field
                width: root.unit * 26
                Row {
                    anchors {
                        left: parent.left
                        leftMargin: root.unit * 2
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: root.unit * 0.8
                    Repeater {
                        model: 6
                        delegate: Rectangle {
                            required property int index
                            readonly property real size: root.unit * 1.6
                            anchors.verticalCenter: parent.verticalCenter
                            width: size
                            height: size
                            // Shapes vary like the real ones; dots are plain circles
                            radius: root.lock.materialShapeChars ? [size / 2, size * 0.2, size / 2, size * 0.35, size * 0.1, size / 2][index] : size / 2
                            rotation: root.lock.materialShapeChars ? index * 25 : 0
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                }
                Rectangle {
                    anchors {
                        right: parent.right
                        rightMargin: root.unit * 0.6
                        verticalCenter: parent.verticalCenter
                    }
                    width: parent.height - root.unit * 1.2
                    height: width
                    radius: width / 2
                    color: Appearance.colors.colPrimary
                    PillIcon {
                        anchors.centerIn: parent
                        text: "arrow_right_alt"
                        color: Appearance.colors.colOnPrimary
                    }
                }
            }
            Pill { // Battery and power buttons
                visible: root.lock.showBattery || root.lock.showPowerButtons
                width: rightRow.implicitWidth + root.unit * 3
                Row {
                    id: rightRow
                    anchors.centerIn: parent
                    spacing: root.unit
                    PillIcon { visible: root.lock.showBattery; text: "battery_android_full" }
                    PillIcon { visible: root.lock.showPowerButtons; text: "dark_mode" }
                    PillIcon { visible: root.lock.showPowerButtons; text: "power_settings_new" }
                    PillIcon { visible: root.lock.showPowerButtons; text: "restart_alt" }
                }
            }
        }
    }
}
