import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    required property DockContext dock
    property real bottomGap: Appearance.sizes.hyprlandGapsOut
    property real devicePixelRatio: Screen.devicePixelRatio
    property var colors: Appearance.colors
    readonly property alias row: row
    readonly property alias background: background
    signal appsRequested()

    StyledRectangularShadow {
        target: background
    }

    Rectangle {
        id: background
        x: row.x - root.dock.sidePadding - root.dock.growth / 2
        y: row.y
        width: row.width + root.dock.sidePadding * 2 + root.dock.growth
        height: root.dock.barHeight
        radius: Math.min(Appearance.rounding.large, height / 2)
        color: root.colors.colLayer0
        border.width: 1
        border.color: root.colors.colLayer0Border

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton
            onPressed: root.dock.dockMenuRequested(null)
        }
    }

    Row {
        id: row
        x: Math.round((parent.width - width) / 2)
        y: parent.height - root.bottomGap - root.dock.barHeight
        height: root.dock.barHeight

        DockApps {
            dock: root.dock
        }
        DockSeparator {
            dock: root.dock
        }
        DockTile {
            id: overviewTile
            dock: root.dock
            label: Translation.tr("Apps")
            onClicked: {
                root.dock.tileActivated(overviewTile);
                root.appsRequested();
            }
            onRightClicked: root.dock.dockMenuRequested(overviewTile)

            Rectangle {
                id: appsSquare
                anchors.fill: parent
                anchors.margins: Math.round(parent.width * 0.04)
                radius: width * 0.26
                color: root.colors.colPrimaryContainer

                // The "apps" symbol, drawn as dots on whole screen pixels: the font's glyph lands on
                // fractions of a pixel at this size, which leaves every dot a little different
                Grid {
                    id: appsDots
                    readonly property real dpr: root.devicePixelRatio
                    // Like the symbol at 55% of the square: dots of 4/24 of its size, 2/24 apart
                    readonly property real unit: appsSquare.width * 0.55 / 24 * dpr
                    readonly property real dot: Math.round(unit * 4) / dpr
                    x: Math.round((parent.width - width) / 2 * dpr) / dpr
                    y: Math.round((parent.height - height) / 2 * dpr) / dpr
                    columns: 3
                    spacing: Math.max(1, Math.round(unit * 2)) / dpr

                    Repeater {
                        model: 9
                        Rectangle {
                            width: appsDots.dot
                            height: appsDots.dot
                            radius: width / 2
                            color: root.colors.colOnPrimaryContainer
                        }
                    }
                }
            }
        }
    }
}
