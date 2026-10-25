pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.ii.sidebars
import QtQuick.Controls
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * What you copied (cliphist), newest first and searchable: click an entry to copy it again
 * (options: showImages, closeAfterCopy). Images are hidden like in the overview's clipboard search
 * while work safety is on.
 */
SidebarCard {
    id: root
    focusTarget: searchField
    readonly property var options: root.host?.options ?? {}
    readonly property var results: {
        const all = Cliphist.fuzzyQuery(searchField.text);
        return (root.options.showImages ?? true) ? all : all.filter(entry => !Cliphist.entryIsImage(entry));
    }
    property bool confirmWipe: false

    // Fresh when shown
    readonly property bool shown: root.host?.active ?? false
    onShownChanged: if (root.shown) Cliphist.refresh()

    function copy(entry) {
        Cliphist.copy(entry);
        if (root.options.closeAfterCopy ?? true) GlobalStates.closeSidebars();
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            ToolbarTextField {
                id: searchField
                Layout.fillWidth: true
                implicitHeight: 40
                placeholderText: Translation.tr("Search what you copied")
                Keys.onReturnPressed: if (root.results.length > 0) root.copy(root.results[0])
                Keys.onDownPressed: list.forceActiveFocus()
            }
            RippleButton {
                implicitWidth: 40
                implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                colBackground: root.confirmWipe ? Appearance.colors.colErrorContainer : "transparent"
                colBackgroundHover: root.confirmWipe ? Appearance.colors.colErrorContainerHover : Appearance.colors.colLayer1Hover
                enabled: Cliphist.entries.length > 0
                onClicked: {
                    if (!root.confirmWipe) {
                        root.confirmWipe = true;
                        confirmTimer.restart();
                        return;
                    }
                    root.confirmWipe = false;
                    Cliphist.wipe();
                }
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    text: root.confirmWipe ? "delete_forever" : "delete_sweep"
                    iconSize: 20
                    color: root.confirmWipe ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnLayer1
                }
                StyledToolTip {
                    text: root.confirmWipe ? Translation.tr("Click again to clear the whole history") : Translation.tr("Clear history")
                }
                Timer {
                    id: confirmTimer
                    interval: 3000
                    onTriggered: root.confirmWipe = false
                }
            }
        }

        StyledListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 4
            model: root.results
            keyNavigationEnabled: true
            Keys.onReturnPressed: if (currentIndex >= 0) root.copy(root.results[currentIndex])

            delegate: RippleButton {
                id: entryButton
                required property string modelData
                required property int index
                readonly property bool isImage: Cliphist.entryIsImage(modelData)
                readonly property bool blurImage: isImage && LauncherSearch.clipboardWorkSafetyActive
                    && (LauncherSearch.containsUnsafeLink(root.results[index - 1]) || LauncherSearch.containsUnsafeLink(root.results[index + 1]))
                width: list.width
                implicitHeight: entryButton.isImage ? (image.item?.height ?? 60) + 16 : Math.min(textLabel.implicitHeight, 64) + 18
                buttonRadius: Appearance.rounding.small
                colBackground: list.currentIndex === index && list.activeFocus ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                onClicked: root.copy(modelData)

                contentItem: Item {
                    StyledText {
                        id: textLabel
                        visible: !entryButton.isImage
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 4
                            rightMargin: 34
                        }
                        text: StringUtils.cleanCliphistEntry(entryButton.modelData)
                        wrapMode: Text.WrapAnywhere
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer2
                    }
                    Loader {
                        id: image
                        active: entryButton.isImage
                        anchors.verticalCenter: parent.verticalCenter
                        sourceComponent: CliphistImage {
                        visible: entryButton.isImage
                            entry: entryButton.modelData
                            maxWidth: list.width - 60
                            maxHeight: 140
                            blur: entryButton.blurImage
                        }
                    }
                }

                RippleButton { // Delete
                    anchors {
                        right: parent.right
                        top: parent.top
                        margins: 6
                    }
                    visible: entryButton.hovered
                    implicitWidth: 26
                    implicitHeight: 26
                    buttonRadius: Appearance.rounding.full
                    colBackgroundHover: Appearance.colors.colLayer3Hover
                    onClicked: Cliphist.deleteEntry(entryButton.modelData)
                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        text: "close"
                        iconSize: 16
                        color: Appearance.colors.colOnLayer2
                    }
                    StyledToolTip {
                        text: Translation.tr("Delete")
                    }
                }
            }

            StyledText {
                visible: root.results.length === 0
                anchors.centerIn: parent
                width: parent.width - 40
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: searchField.text.length > 0 ? Translation.tr("Nothing like that was copied") : Translation.tr("Copy something and it shows up here")
                color: Appearance.colors.colSubtext
            }
        }
    }
}
