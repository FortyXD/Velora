pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.onboarding
import QtQuick
import QtQuick.Layouts

/**
 * Ready: what was chosen (each line leads back to its step), a burst of the new colors, and the way
 * out — the quick tour, or straight to the desktop.
 */
PageScaffold {
    id: root
    title: Translation.tr("You're all set")
    subtitle: Translation.tr("Velora is yours. Change any of this in Settings (Super+I).")

    readonly property var lookNames: ({ "velora": "Velora", "horizon": "Velora Horizon", "vertical": "Velora Vertical" })
    readonly property var summary: [
        { "step": "layout", "icon": "dashboard", "name": Translation.tr("Desktop"), "value": root.lookNames[root.flow.choices.look] ?? "Velora" },
        { "step": "layout", "icon": "select_window", "name": Translation.tr("Windows"),
          "value": root.flow.choices.windows === "tiling" ? Translation.tr("Tiling") : Translation.tr("Free windows") },
        { "step": "appearance", "icon": "contrast", "name": Translation.tr("Theme"),
          "value": root.flow.shownTheme === "light" ? Translation.tr("Light") : Translation.tr("Dark") },
        { "step": root.flow.hasExtras ? "install" : "extras", "icon": "download", "name": Translation.tr("Extras"),
          "value": root.flow.installState === "done" ? Translation.tr("Installed: %1").arg(root.flow.installing.length)
            : root.flow.installItems.length > 0 ? Translation.tr("Not installed: %1").arg(root.flow.installItems.length)
            : Translation.tr("Nothing more") },
    ]

    Repeater {
        model: root.summary
        delegate: Reveal {
            id: line
            required property var modelData
            required property int index
            order: 1 + index
            RippleButton {
                width: parent.width
                implicitHeight: 52
                buttonRadius: Appearance.rounding.normal
                colBackground: Appearance.colors.colLayer1
                onClicked: root.flow.go(line.modelData.step)
                contentItem: RowLayout {
                    spacing: 14
                    MaterialSymbol {
                        Layout.leftMargin: 16
                        text: line.modelData.icon
                        iconSize: 22
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: line.modelData.name
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        text: line.modelData.value
                        color: Appearance.colors.colSubtext
                    }
                    MaterialSymbol {
                        Layout.rightMargin: 12
                        text: "chevron_right"
                        iconSize: 20
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }
    }

    Reveal {
        order: 6
        StyledText {
            width: parent.width
            wrapMode: Text.Wrap
            text: Translation.tr("Online: weather by your IP address and the wallpaper of the day can be turned off in Settings. The AI assistant is off. Velora sends no telemetry.")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }
    }

    Reveal {
        order: 7
        RowLayout {
            width: parent.width
            spacing: 12
            RippleButton {
                implicitHeight: 36
                implicitWidth: undoText.implicitWidth + 28
                buttonRadius: height / 2
                onClicked: root.flow.undoAll()
                contentItem: StyledText {
                    id: undoText
                    horizontalAlignment: Text.AlignHCenter
                    text: Translation.tr("Undo all changes")
                    color: Appearance.colors.colSubtext
                }
            }
            Item { Layout.fillWidth: true }
            RippleButton {
                implicitHeight: 48
                implicitWidth: startText.implicitWidth + 40
                buttonRadius: height / 2
                colBackground: Appearance.colors.colLayer2
                onClicked: root.flow.finish(false)
                contentItem: StyledText {
                    id: startText
                    horizontalAlignment: Text.AlignHCenter
                    text: Translation.tr("Start using Velora")
                }
            }
            RippleButton {
                implicitHeight: 48
                implicitWidth: tourText.implicitWidth + 40
                buttonRadius: height / 2
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                focus: true
                Keys.onReturnPressed: root.flow.finish(true)
                onClicked: root.flow.finish(true)
                contentItem: StyledText {
                    id: tourText
                    horizontalAlignment: Text.AlignHCenter
                    text: Translation.tr("Take the quick tour (2 min)")
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnPrimary
                }
            }
        }
    }

    // A burst of the new colors, once
    Item {
        parent: root
        anchors.fill: parent
        visible: !Motion.reduced
        z: -1
        Repeater {
            model: 36
            delegate: Rectangle {
                id: bit
                required property int index
                readonly property real angle: (index / 36) * Math.PI * 2 + (index % 3) * 0.2
                readonly property real distance: 160 + (index * 37 % 140)
                readonly property var colors: [Appearance.colors.colPrimary, Appearance.colors.colSecondary, Appearance.colors.colTertiary,
                    Appearance.colors.colPrimaryContainer]
                x: parent.width / 2
                y: parent.height * 0.42
                width: 8 + index % 3 * 3
                height: width * (index % 2 ? 2.2 : 1)
                radius: index % 2 ? 2 : width / 2
                color: colors[index % colors.length]
                opacity: 0
                // Started once the page has its size, so the burst comes from its middle
                Timer {
                    running: true
                    interval: 300
                    onTriggered: burst.start()
                }
                ParallelAnimation {
                    id: burst
                    SequentialAnimation {
                        NumberAnimation { target: bit; property: "opacity"; to: 0.9; duration: 80 }
                        PauseAnimation { duration: 600 }
                        NumberAnimation { target: bit; property: "opacity"; to: 0; duration: 700 }
                    }
                    NumberAnimation { target: bit; property: "x"; to: bit.x + Math.cos(bit.angle) * bit.distance; duration: 1300; easing.type: Easing.OutCubic }
                    NumberAnimation { target: bit; property: "y"; to: bit.y + Math.sin(bit.angle) * bit.distance + 120; duration: 1300; easing.type: Easing.OutQuad }
                    NumberAnimation { target: bit; property: "rotation"; to: (bit.index % 2 ? 1 : -1) * 240; duration: 1300 }
                }
            }
        }
    }
}
