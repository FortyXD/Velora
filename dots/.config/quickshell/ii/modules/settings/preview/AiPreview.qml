import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    property string modelName: ""
    property string modelSource: ""
    readonly property real radius: Appearance.rounding.normal

    signal sectionRequested(string section)

    Layout.fillWidth: true
    implicitHeight: previewBody.implicitHeight + 44

    MiniScreen {
        anchors.fill: parent
        crop: "top"
        scrim: 0.24
    }

    Rectangle {
        anchors.fill: parent
        opacity: 0.55
        radius: root.radius

        gradient: Gradient {
            GradientStop {
                color: Appearance.colors.colPrimaryContainer
                position: 0
            }

            GradientStop {
                color: Appearance.colors.colLayer1
                position: 1
            }
        }
    }

    ColumnLayout {
        id: previewBody

        spacing: 12

        anchors {
            left: parent.left
            margins: 22
            right: parent.right
            top: parent.top
        }

        RowLayout {
            Layout.fillWidth: true

            MaterialSymbol {
                color: Appearance.colors.colOnLayer1
                iconSize: 22
                text: "neurology"
            }

            StyledText {
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.DemiBold
                text: Translation.tr("Your AI")
            }

            Item {
                Layout.fillWidth: true
            }

            StyledText {
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                text: Translation.tr("Example")
            }
        }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            Layout.maximumWidth: 520
            Layout.preferredWidth: 460
            border.color: Appearance.colors.colOutlineVariant
            color: Appearance.colors.colLayer0Base
            implicitHeight: chat.implicitHeight + 24
            radius: Appearance.rounding.normal

            ColumnLayout {
                id: chat

                spacing: 8

                anchors {
                    left: parent.left
                    margins: 12
                    right: parent.right
                    top: parent.top
                }

                ConfigNavRow {
                    buttonIcon: root.modelSource === Translation.tr("Cloud") ? "cloud" : "computer"
                    description: Config.options.policies.ai === 0 ? Translation.tr(
                                                                        "AI is off. Your models and connections are kept.") :
                                                                    root.modelSource
                    objectName: "aiPreviewModel"
                    title: root.modelName

                    onClicked: {
                        forceActiveFocus();
                        root.sectionRequested(Assistant.enabled ? "assistant-model" : "chat");
                    }
                }

                RippleButton {
                    Layout.alignment: Qt.AlignRight
                    Layout.preferredWidth: Math.min(280, chat.width - 20)
                    bottomPadding: 10
                    buttonRadius: Appearance.rounding.normal
                    colBackground: Appearance.colors.colPrimaryContainer
                    colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                    implicitHeight: contentItem.implicitHeight + 20
                    leftPadding: 14
                    rightPadding: 14
                    topPadding: 10

                    contentItem: StyledText {
                        color: Appearance.colors.colOnPrimaryContainer
                        font.pixelSize: Appearance.font.pixelSize.small
                        text: Translation.tr("Help me plan my day")
                        wrapMode: Text.Wrap
                    }

                    onClicked: {
                        forceActiveFocus();
                        root.sectionRequested("chat");
                    }
                }

                RippleButton {
                    Layout.alignment: Qt.AlignLeft
                    Layout.preferredWidth: Math.min(300, chat.width - 20)
                    bottomPadding: 10
                    buttonRadius: Appearance.rounding.normal
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    implicitHeight: contentItem.implicitHeight + 20
                    leftPadding: 14
                    objectName: "aiPreviewChat"
                    rightPadding: 14
                    topPadding: 10

                    contentItem: StyledText {
                        font.pixelSize: Appearance.font.pixelSize.small
                        text: Translation.tr("Let's start with the most important task.")
                        wrapMode: Text.Wrap
                    }

                    onClicked: {
                        forceActiveFocus();
                        root.sectionRequested("chat");
                    }
                }

                ConfigNavRow {
                    buttonIcon: "touch_app"
                    buttonRadius: Appearance.rounding.normal
                    colBackground: Appearance.colors.colLayer2
                    description: Translation.tr("Desktop actions") + " · " + (Assistant.enabled
                                                                              ? Translation.tr("On") :
                                                                                Translation.tr("Off"))
                    objectName: "aiPreviewAction"
                    title: Translation.tr("Open my project folder")

                    onClicked: {
                        forceActiveFocus();
                        root.sectionRequested("assistant");
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr("Select a part of the preview to change its settings.")
            wrapMode: Text.Wrap
        }
    }
}
