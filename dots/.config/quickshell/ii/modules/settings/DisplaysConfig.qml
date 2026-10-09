import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ContentPage {
    id: root
    property var monitors: []

    function refreshMonitors() {
        monitorsProc.running = false;
        monitorsProc.running = true;
    }

    Process {
        id: monitorsProc
        command: ["hyprctl", "monitors", "-j"]
        running: true
        stdout: StdioCollector {
            id: monitorsCollector
            onStreamFinished: {
                try {
                    root.monitors = JSON.parse(monitorsCollector.text);
                } catch (e) {
                    root.monitors = [];
                }
            }
        }
    }

    ContentSection {
        title: Translation.tr("Connected displays")
        description: Translation.tr("Resolution, scale and arrangement are set in monitors.lua and hyprland/general.lua")

        Repeater {
            model: root.monitors
            delegate: Item {
                id: monitorRow
                required property var modelData
                readonly property bool builtIn: modelData.name.startsWith("eDP") || modelData.name.startsWith("LVDS")
                Layout.fillWidth: true
                implicitHeight: monitorLayout.implicitHeight + 24

                RowLayout {
                    id: monitorLayout
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: 12
                        rightMargin: 14
                    }
                    spacing: 14

                    Rectangle { // Screen preview with the right proportions
                        readonly property real ratio: monitorRow.modelData.width / Math.max(1, monitorRow.modelData.height)
                        implicitWidth: 64
                        implicitHeight: Math.round(64 / ratio)
                        radius: 6
                        color: Appearance.colors.colLayer3
                        border.width: 2
                        border.color: monitorRow.modelData.focused ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: monitorRow.builtIn ? "laptop_chromebook" : "desktop_windows"
                            iconSize: 20
                            color: Appearance.colors.colSubtext
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        StyledText {
                            Layout.fillWidth: true
                            text: monitorRow.builtIn ? Translation.tr("Built-in display") : (monitorRow.modelData.model?.trim() || monitorRow.modelData.name)
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer2
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: `${monitorRow.modelData.name} · ${monitorRow.modelData.make?.trim() ?? ""}`
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                    GridLayout {
                        columns: 2
                        columnSpacing: 10
                        rowSpacing: 1
                        Repeater {
                            model: [
                                Translation.tr("Resolution"), `${monitorRow.modelData.width}×${monitorRow.modelData.height}`,
                                Translation.tr("Refresh rate"), `${Math.round(monitorRow.modelData.refreshRate)} Hz`,
                                Translation.tr("Scale"), `${Math.round(monitorRow.modelData.scale * 100)}%`
                            ]
                            delegate: StyledText {
                                required property var modelData
                                required property int index
                                Layout.alignment: index % 2 === 0 ? Qt.AlignRight : Qt.AlignLeft
                                text: modelData
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: index % 2 === 0 ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer2
                            }
                        }
                    }
                }
            }
        }

        ConfigNavRow {
            buttonIcon: "edit_document"
            title: Translation.tr("Edit monitor configuration")
            trailingIcon: "open_in_new"
            onClicked: Qt.openUrlExternally(`file://${FileUtils.trimFileProtocol(Directories.config)}/hypr/monitors.lua`)
        }
        ConfigNavRow {
            buttonIcon: "refresh"
            title: Translation.tr("Refresh list")
            trailingIcon: ""
            onClicked: root.refreshMonitors()
        }
    }

    ContentSection {
        title: Translation.tr("Refresh rate")
        description: Translation.tr("Variable refresh rate lowers flicker and stutter in games on displays that support it")

        HyprChoice {
            option: "misc:vrr"
            fallback: 0
            title: Translation.tr("Variable refresh rate")
            choices: [
                { displayName: Translation.tr("Off"), icon: "close", value: 0 },
                { displayName: Translation.tr("On"), icon: "check", value: 1 },
                { displayName: Translation.tr("Fullscreen only"), icon: "fullscreen", value: 2 }
            ]
        }
    }

    ContentSection {
        title: Translation.tr("Waking the screen")

        HyprSwitch {
            option: "misc:mouse_move_enables_dpms"
            fallback: true
            buttonIcon: "mouse"
            text: Translation.tr("Moving the mouse turns the screen on")
        }
        HyprSwitch {
            option: "misc:key_press_enables_dpms"
            fallback: true
            buttonIcon: "keyboard"
            text: Translation.tr("Pressing a key turns the screen on")
        }
    }

    ContentSection {
        title: Translation.tr("Look")

        ConfigNavRow {
            buttonIcon: "rounded_corner"
            title: Translation.tr("Screen corners")
            onClicked: ApplicationWindow.window?.openPage("appearance", Translation.tr("Screen corners"))
        }
    }
}
