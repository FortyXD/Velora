import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Picks rows × columns the way a table size is picked: hover over the cells to span a block,
 * click to keep it. The current size stays highlighted.
 */
ColumnLayout {
    id: root
    property int rows: 2
    property int columns: 5
    property int maxRows: 6
    property int maxColumns: 10
    property int hoverRows: 0
    property int hoverColumns: 0
    readonly property bool hovering: root.hoverRows > 0

    signal picked(int rows, int columns)

    readonly property bool settingsSearchable: true
    property string searchText: `${Translation.tr("Rows")} ${Translation.tr("Columns")} ${Translation.tr("Workspaces")}`

    Layout.fillWidth: true
    Layout.margins: 12
    spacing: 8

    StyledText {
        text: root.hovering ? Translation.tr("%1 × %2 · %3 workspaces").arg(root.hoverRows).arg(root.hoverColumns).arg(root.hoverRows * root.hoverColumns)
            : Translation.tr("%1 × %2 · %3 workspaces").arg(root.rows).arg(root.columns).arg(root.rows * root.columns)
        font.pixelSize: Appearance.font.pixelSize.small
        font.family: Appearance.font.family.numbers
        color: root.hovering ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
    }

    Grid {
        id: grid
        columns: root.maxColumns
        spacing: 4

        HoverHandler {
            onHoveredChanged: if (!hovered) {
                root.hoverRows = 0;
                root.hoverColumns = 0;
            }
        }

        Repeater {
            model: root.maxRows * root.maxColumns
            delegate: Rectangle {
                id: cell
                required property int index
                readonly property int row: Math.floor(index / root.maxColumns) + 1
                readonly property int column: index % root.maxColumns + 1
                readonly property bool inHover: root.hovering && cell.row <= root.hoverRows && cell.column <= root.hoverColumns
                readonly property bool inCurrent: cell.row <= root.rows && cell.column <= root.columns
                width: 30
                height: 20
                radius: 5
                color: cell.inHover ? Appearance.colors.colPrimary
                    : cell.inCurrent ? Appearance.colors.colSecondaryContainer
                    : Appearance.colors.colLayer3
                border.width: cell.inCurrent && !root.hovering ? 1 : 0
                border.color: Appearance.colors.colPrimary
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: {
                        root.hoverRows = cell.row;
                        root.hoverColumns = cell.column;
                    }
                    onClicked: root.picked(cell.row, cell.column)
                }
            }
        }
    }
}
