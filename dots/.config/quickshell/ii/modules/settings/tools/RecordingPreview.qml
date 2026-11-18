import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.preview

Rectangle {
    id: root
    required property real progress
    readonly property var recording: Config.options.screenRecord
    readonly property bool withAudio: recording.audio !== "none"
    readonly property color accent: Appearance.colors.colPrimary
    radius: Appearance.rounding.small
    color: ColorUtils.mix(accent, Appearance.colors.colLayer2Base, 0.09)

    Item {
        id: timeline
        x: Math.round(parent.width * 0.08); width: parent.width - 2 * x
        anchors.verticalCenter: parent.verticalCenter
        height: Math.min(108, parent.height * 0.74)

        Row {
            id: frames
            width: parent.width; height: parent.height * 0.60; spacing: 3
            Repeater {
                model: 3
                MiniScreen {
                    id: frame
                    required property int index
                    width: (frames.width - 2 * frames.spacing) / 3
                    height: frames.height
                    wallpaperItem.sourceSize: Qt.size(880, 0)
                    wallpaperItem.width: frame.width * 1.6
                    wallpaperItem.height: frame.height * 1.6
                    wallpaperItem.x: (frame.width - wallpaperItem.width) * frame.index * 0.5
                    wallpaperItem.y: (frame.height - wallpaperItem.height) * (0.24 + frame.index * 0.20)
                    radius: 5
                    scrim: index === 1 ? 0.02 : 0.14
                    Rectangle {
                        visible: root.recording.mode === "region"
                        anchors.centerIn: parent
                        width: parent.width * 0.74; height: parent.height * 0.68
                        radius: 2; color: "transparent"; border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.8)
                    }
                }
            }
        }
        Column {
            id: tracks
            anchors { top: frames.bottom; bottom: parent.bottom; left: parent.left; right: parent.right; topMargin: 5 }
            spacing: 2
            Repeater {
                id: lanes
                model: root.recording.audio === "both" ? 2 : 1
                Rectangle {
                    id: lane
                    required property int index
                    width: tracks.width
                    height: (tracks.height - (lanes.count - 1) * tracks.spacing) / lanes.count
                    radius: 4
                    readonly property bool mic: root.recording.audio === "microphone" || index === 1
                    readonly property color ink: mic ? Appearance.colors.colTertiary : Appearance.colors.colSecondary
                    color: ColorUtils.mix(ink, Appearance.colors.colLayer2Base, root.withAudio ? 0.13 : 0.06)
                    MaterialSymbol {
                        anchors { left: parent.left; leftMargin: 5; verticalCenter: parent.verticalCenter }
                        text: !root.withAudio ? "volume_off" : lane.mic ? "mic" : "volume_up"
                        iconSize: Math.min(16, lane.height); color: lane.ink
                    }
                    Item {
                        anchors { fill: parent; leftMargin: 26; rightMargin: 5 }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width; height: 1; color: ColorUtils.applyAlpha(lane.ink, 0.5)
                        }
                        Repeater {
                            model: root.withAudio ? Math.max(1, Math.floor(parent.width / 5)) : 0
                            Rectangle {
                                required property int index
                                readonly property real amplitude: Math.abs(Math.sin(index * 0.72 + lane.index) * Math.cos(index * 0.23 + lane.index))
                                x: index * 5; anchors.verticalCenter: parent.verticalCenter
                                width: 3; height: Math.max(2, (lane.height - 5) * amplitude); radius: 1.5
                                color: lane.ink
                            }
                        }
                    }
                }
            }
        }
        Item {
            x: (0.08 + 0.65 * root.progress) * parent.width
            y: -5; height: parent.height + 9
            Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 2; height: parent.height; color: root.accent }
            Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 9; height: 5; radius: 2; color: root.accent }
        }
    }
}
