pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/** Shows `ConnectivityPrompts`' questions over everything, on the focused screen. */
Scope {
    id: root

    Loader {
        active: ConnectivityPrompts.current !== null
        sourceComponent: PanelWindow {
            id: panelWindow
            screen: Quickshell.screens.find(screen => screen.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]

            anchors {
                top: true
                left: true
                right: true
                bottom: true
            }

            color: "transparent"
            WlrLayershell.namespace: "quickshell:connectivityPrompt"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore

            Item {
                id: content
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: ConnectivityPrompts.answer(false)

                function submit(): void {
                    const values = {};
                    for (let index = 0; index < fieldRepeater.count; index++) {
                        const field = fieldRepeater.itemAt(index);
                        values[field.modelData.key] = field.text;
                    }
                    ConnectivityPrompts.answer(true, values);
                }

                Rectangle {
                    anchors.fill: parent
                    color: Appearance.colors.colScrim
                }

                // A card that fits its content, which changes from one question to the next
                Rectangle {
                    anchors.centerIn: parent
                    implicitWidth: 450
                    implicitHeight: dialogContent.implicitHeight + 40
                    radius: Appearance.rounding.large
                    color: Appearance.m3colors.m3surfaceContainerHigh

                    MouseArea {
                        anchors.fill: parent
                    }

                    ColumnLayout {
                        id: dialogContent
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: 20
                        spacing: 16

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            iconSize: 26
                            text: ConnectivityPrompts.symbol
                            color: Appearance.colors.colSecondary
                        }
                        WindowDialogTitle {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: ConnectivityPrompts.title
                        }
                        WindowDialogParagraph {
                            Layout.fillWidth: true
                            text: ConnectivityPrompts.message
                        }
                        StyledText {
                            visible: ConnectivityPrompts.code.length > 0
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: ConnectivityPrompts.code
                            font.pixelSize: Appearance.font.pixelSize.hugeass
                            font.family: Appearance.font.family.monospace
                            color: Appearance.colors.colOnLayer0
                        }
                        Repeater {
                            id: fieldRepeater
                            model: ConnectivityPrompts.fields
                            delegate: MaterialTextField {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                placeholderText: modelData.label
                                echoMode: modelData.hidden ? TextInput.Password : TextInput.Normal
                                Component.onCompleted: if (index === 0) forceActiveFocus()
                                onAccepted: content.submit()
                                Keys.onEscapePressed: ConnectivityPrompts.answer(false)
                            }
                        }
                        WindowDialogButtonRow {
                            Item {
                                Layout.fillWidth: true
                            }
                            DialogButton {
                                buttonText: ConnectivityPrompts.declineText
                                onClicked: ConnectivityPrompts.answer(false)
                            }
                            DialogButton {
                                visible: !ConnectivityPrompts.isNote
                                buttonText: ConnectivityPrompts.acceptText
                                onClicked: content.submit()
                            }
                        }
                    }
                }
            }
        }
    }
}
