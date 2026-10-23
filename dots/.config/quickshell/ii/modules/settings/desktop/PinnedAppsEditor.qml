import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.settings

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

    AppPickerPopup {
        id: appPicker
        title: Translation.tr("Pin an app to the dock")
        excludedIds: root.pinned
        onPicked: entry => Config.options.dock.pinnedApps = root.pinned.concat([entry.id])
    }
}
