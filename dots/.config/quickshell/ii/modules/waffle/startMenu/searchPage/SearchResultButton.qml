import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.waffle.looks

WChoiceButton {
    id: root

    required property LauncherSearchResult entry
    property bool firstEntry: false

    signal requestFocus()

    checked: focus
    animateChoiceHighlight: false
    implicitWidth: contentLayout.implicitWidth + leftPadding + rightPadding
    implicitHeight: contentLayout.implicitHeight + topPadding + bottomPadding

    onClicked: {
        execute();
    }

    function execute() {
        const keepOpen = root.entry.keepOpen;
        root.entry.execute();
        if (!keepOpen) GlobalStates.searchOpen = false;
    }

    horizontalPadding: 0
    verticalPadding: 0

    contentItem: RowLayout {
        id: contentLayout
        spacing: 0

        WButton {
            id: launchButton
            Layout.fillWidth: true
            Layout.fillHeight: true
            horizontalPadding: 10
            verticalPadding: 11
            implicitHeight: Math.max(root.firstEntry ? 62 : 36, entryContentRow.implicitHeight + 8 * 2)
            implicitWidth: entryContentRow.implicitWidth + leftPadding + rightPadding
            topRightRadius: 0
            bottomRightRadius: 0
            onClicked: root.click()
            contentItem: Item {
                RowLayout {
                    id: entryContentRow
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 8

                    SearchEntryIcon {
                        entry: root.entry
                        iconSize: 24
                    }
                    EntryNameColumn {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                    }
                }
            }
        }
        Rectangle {
            id: separator
            opacity: (root.hovered && !root.checked) ? 1 : 0
            Layout.fillHeight: true
            implicitWidth: 1
            color: ColorUtils.transparentize(Looks.colors.fg, 0.75)
        }
        WButton {
            visible: !root.checked
            Layout.fillHeight: true
            implicitWidth: 47
            topLeftRadius: 0
            bottomLeftRadius: 0
            onClicked: root.requestFocus()
            contentItem: Item {
                FluentIcon {
                    anchors.centerIn: parent
                    icon: "chevron-right"
                    implicitSize: 14
                }
            }
        }
    }

    component EntryNameColumn: ColumnLayout {
        spacing: 4

        WText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: root.entry.name
            font.pixelSize: Looks.font.pixelSize.large
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        WText {
            Layout.fillWidth: true
            visible: root.firstEntry
            text: root.entry.type
            color: Looks.colors.accentUnfocused
            elide: Text.ElideRight
        }
        WText {
            objectName: "lensResultPath"
            Layout.fillWidth: true
            visible: root.entry.lensPath.startsWith("/")
            text: visible ? root.entry.lensPath : ""
            textFormat: Text.PlainText
            elide: Text.ElideMiddle
            color: Looks.colors.accentUnfocused
            StyledToolTip { text: parent.text; extraVisibleCondition: root.hovered && parent.truncated }
        }
        WText {
            Layout.fillWidth: true
            visible: root.entry.lensPath !== ""
            text: root.entry.comment
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            color: Looks.colors.accentUnfocused
        }
        Image {
            visible: root.checked && root.entry.preview !== ""
            source: visible ? root.entry.preview : ""
            cache: false
            fillMode: Image.PreserveAspectFit
            Layout.preferredWidth: 160
            Layout.preferredHeight: visible ? 90 : 0
        }
    }

    MouseArea {
        anchors.fill: parent
        // hoverEnabled: true
        acceptedButtons: Qt.NoButton
        cursorShape: Qt.PointingHandCursor
    }
}
