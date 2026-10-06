import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

/**
 * Saved chats: save the current one, load or delete others.
 */
Rectangle {
    id: root
    signal closed()

    readonly property var chatNames: Ai.savedChats
        .map(path => FileUtils.trimFileExt(FileUtils.fileNameForPath(path)).trim())
        .filter(name => name.length > 0)
        .sort((a, b) => (a === "lastSession" ? -1 : b === "lastSession" ? 1 : a.localeCompare(b)))

    // A readable name from the first user message, made unique with the time
    function suggestedName() {
        const firstUserMessage = Ai.messageIDs.map(id => Ai.messageByID[id]).find(message => message?.role === "user");
        const words = (firstUserMessage?.rawContent ?? "").replace(/[^A-Za-z0-9\u0400-\u04FF ]/g, " ").trim().split(/\s+/).slice(0, 6).join(" ");
        const time = Qt.formatDateTime(new Date(), "yyyy-MM-dd hh.mm");
        return words.length > 0 ? `${words} (${time})` : time;
    }

    color: Appearance.colors.colLayer2
    radius: Appearance.rounding.normal
    border.width: 1
    border.color: Appearance.colors.colOutlineVariant

    Keys.onEscapePressed: root.closed()

    ColumnLayout {
        anchors {
            fill: parent
            margins: 8
        }
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false // Nested layouts fill height by default
            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnLayer2
                text: Translation.tr("Chats")
            }
            RippleButtonWithIcon {
                enabled: Ai.messageIDs.length > 0
                materialIcon: "save"
                mainText: Translation.tr("Save current")
                buttonRadius: Appearance.rounding.small
                onClicked: Ai.saveChat(root.suggestedName())
            }
        }

        StyledListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            popin: false
            model: root.chatNames

            delegate: RippleButton {
                id: chatRow
                required property string modelData
                width: ListView.view.width
                implicitHeight: 40
                leftPadding: 10
                rightPadding: 4
                buttonRadius: Appearance.rounding.small
                onClicked: {
                    Ai.loadChat(chatRow.modelData);
                    root.closed();
                }

                contentItem: RowLayout {
                    spacing: 6
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.colors.colOnLayer2
                        text: chatRow.modelData === "lastSession" ? "history" : "chat"
                    }
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer2
                        text: chatRow.modelData === "lastSession" ? Translation.tr("Last session") : chatRow.modelData
                    }
                    RippleButton {
                        visible: chatRow.modelData !== "lastSession"
                        implicitWidth: 30
                        implicitHeight: 30
                        buttonRadius: Appearance.rounding.full
                        onClicked: {
                            Quickshell.execDetached(["rm", "-f", `${Directories.aiChats}/${chatRow.modelData}.json`]);
                            Ai.savedChats = Ai.savedChats.filter(path => FileUtils.trimFileExt(FileUtils.fileNameForPath(path)).trim() !== chatRow.modelData);
                        }
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            iconSize: Appearance.font.pixelSize.normal
                            color: Appearance.colors.colSubtext
                            text: "delete"
                        }
                        StyledToolTip {
                            text: Translation.tr("Delete")
                        }
                    }
                }
            }
        }

        StyledText {
            visible: root.chatNames.length === 0
            Layout.fillWidth: true
            Layout.margins: 8
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            text: Translation.tr("No saved chats yet")
        }
    }
}
