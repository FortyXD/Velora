import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * The dock's pinned apps as icons: hover one to move it left or right or unpin it,
 * and add more from a searchable list of installed apps.
 */
ColumnLayout {
    id: root
    readonly property var pinned: Config.options.dock.pinnedApps ?? []

    readonly property bool settingsSearchable: true
    property string searchText: `${Translation.tr("Pinned apps")} ${Translation.tr("Add an app")}`

    Layout.fillWidth: true
    Layout.margins: 10
    spacing: 6

    function move(index, delta) {
        let list = [...root.pinned];
        const target = index + delta;
        if (target < 0 || target >= list.length) return;
        [list[index], list[target]] = [list[target], list[index]];
        Config.options.dock.pinnedApps = list;
    }

    Flow {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: root.pinned
            delegate: Rectangle {
                id: appTile
                required property string modelData
                required property int index
                width: 84
                height: 92
                radius: Appearance.rounding.normal
                color: tileHover.hovered ? Appearance.colors.colLayer2Hover : "transparent"

                HoverHandler {
                    id: tileHover
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 6
                    spacing: 4
                    IconImage {
                        Layout.alignment: Qt.AlignHCenter
                        implicitSize: 44
                        source: Quickshell.iconPath(TaskbarApps.iconFor(appTile.modelData), "image-missing")
                    }
                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: TaskbarApps.displayName(appTile.modelData)
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer2
                    }
                }

                Row { // Shown on hover
                    visible: tileHover.hovered
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 2
                    spacing: 0
                    TileAction {
                        visible: appTile.index > 0
                        symbol: "chevron_left"
                        tip: Translation.tr("Move left")
                        onClicked: root.move(appTile.index, -1)
                    }
                    TileAction {
                        symbol: "close"
                        tip: Translation.tr("Unpin")
                        onClicked: TaskbarApps.togglePin(appTile.modelData)
                    }
                    TileAction {
                        visible: appTile.index < root.pinned.length - 1
                        symbol: "chevron_right"
                        tip: Translation.tr("Move right")
                        onClicked: root.move(appTile.index, 1)
                    }
                }
            }
        }

        RippleButton { // Add
            width: 84
            height: 92
            buttonRadius: Appearance.rounding.normal
            colBackgroundHover: Appearance.colors.colLayer2Hover
            onClicked: appPicker.open()
            contentItem: ColumnLayout {
                spacing: 4
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 44
                    implicitHeight: 44
                    radius: 14
                    color: "transparent"
                    border.width: 1
                    border.color: Appearance.colors.colOutline
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "add"
                        iconSize: 24
                        color: Appearance.colors.colOnLayer2
                    }
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("Add an app")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer2
                }
            }
        }
    }

    component TileAction: RippleButton {
        id: action
        property string symbol
        property string tip
        implicitWidth: 24
        implicitHeight: 24
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colLayer3
        colBackgroundHover: Appearance.colors.colLayer3Hover
        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            text: action.symbol
            iconSize: 16
            color: Appearance.colors.colOnLayer2
        }
        StyledToolTip {
            text: action.tip
        }
    }

    Popup {
        id: appPicker
        parent: Overlay.overlay
        modal: true
        anchors.centerIn: parent
        width: Math.min(440, (parent?.width ?? 440) - 40)
        height: Math.min(520, (parent?.height ?? 520) - 40)
        padding: 14
        onOpened: {
            searchField.text = "";
            searchField.forceActiveFocus();
        }

        readonly property var apps: {
            const query = searchField.text.trim().toLowerCase();
            const pinnedIds = root.pinned.map(id => id.toLowerCase());
            return DesktopEntries.applications.values
                .filter(entry => !entry.noDisplay && !pinnedIds.includes(entry.id.toLowerCase()))
                .filter(entry => query.length === 0 || entry.name.toLowerCase().includes(query) || entry.id.toLowerCase().includes(query))
                .sort((a, b) => a.name.localeCompare(b.name));
        }

        background: Rectangle {
            radius: Appearance.rounding.normal
            color: ColorUtils.applyAlpha(Appearance.colors.colLayer1, 1)
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant
        }

        contentItem: ColumnLayout {
            spacing: 10
            StyledText {
                text: Translation.tr("Pin an app to the dock")
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colOnLayer1
            }
            TextField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: Translation.tr("Search apps")
                placeholderTextColor: Appearance.colors.colSubtext
                color: Appearance.colors.colOnLayer3
                leftPadding: 14
                topPadding: 10
                bottomPadding: 10
                font.pixelSize: Appearance.font.pixelSize.small
                background: Rectangle {
                    implicitHeight: 40
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer3
                    border.width: searchField.activeFocus ? 2 : 0
                    border.color: Appearance.colors.colPrimary
                }
                Keys.onEscapePressed: appPicker.close()
            }
            StyledListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                model: appPicker.apps
                delegate: RippleButton {
                    id: appRow
                    required property var modelData
                    width: ListView.view.width
                    implicitHeight: 44
                    buttonRadius: Appearance.rounding.small
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    onClicked: {
                        Config.options.dock.pinnedApps = root.pinned.concat([appRow.modelData.id]);
                        appPicker.close();
                    }
                    contentItem: RowLayout {
                        spacing: 12
                        IconImage {
                            Layout.leftMargin: 6
                            implicitSize: 28
                            source: Quickshell.iconPath(appRow.modelData.icon, "image-missing")
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: appRow.modelData.name
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                }
            }
        }
    }
}
