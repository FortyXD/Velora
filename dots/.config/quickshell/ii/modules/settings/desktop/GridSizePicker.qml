import QtQuick
import QtQuick.Layouts
import qs.services
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
    property bool rightToLeft: false
    property bool bottomUp: false
    readonly property bool hovering: root.hoverRows > 0

    signal picked(int rows, int columns)

    readonly property bool settingsSearchable: true
    property string searchText: `${Translation.tr("Rows")} ${Translation.tr("Columns")} ${Translation.tr("Workspaces")}`

    Layout.fillWidth: true
    Layout.margins: 12
    spacing: 8
    activeFocusOnTab: true
    Accessible.role: Accessible.SpinBox
    Accessible.name: Translation.tr("Workspaces in the overview")
    Accessible.description: Translation.tr("%1 × %2 · %3 workspaces").arg(rows).arg(columns).arg(rows * columns)
    Keys.onLeftPressed: picked(rows, Math.max(1, columns - 1))
    Keys.onRightPressed: picked(rows, Math.min(maxColumns, columns + 1))
    Keys.onUpPressed: picked(Math.max(1, rows - 1), columns)
    Keys.onDownPressed: picked(Math.min(maxRows, rows + 1), columns)

    StyledText {
        text: root.hovering ? Translation.tr("%1 × %2 · %3 workspaces").arg(root.hoverRows).arg(root.hoverColumns).arg(root.hoverRows * root.hoverColumns)
            : Translation.tr("%1 × %2 · %3 workspaces").arg(root.rows).arg(root.columns).arg(root.rows * root.columns)
        font.pixelSize: Appearance.font.pixelSize.small
        font.family: Appearance.font.family.numbers
        color: root.hovering ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer2
    }

    Item {
        id: gridArea
        Layout.fillWidth: true
        Layout.preferredWidth: 280
        readonly property int cellWidth: Math.max(12, Math.min(34, Math.floor((width - 3 * (root.maxColumns - 1)) / root.maxColumns)))
        implicitHeight: root.maxRows * Math.round(cellWidth * 0.7) + (root.maxRows - 1) * 3
        Grid {
            id: grid
            anchors.centerIn: parent
            columns: root.maxColumns
            spacing: 3

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
                    width: gridArea.cellWidth
                    height: Math.round(width * 0.7)
                    radius: 4
                    color: cell.inHover ? Appearance.colors.colPrimary
                        : cell.inCurrent ? Appearance.colors.colSecondaryContainer
                        : Appearance.colors.colLayer3
                    border.width: cell.inCurrent && !root.hovering ? 1 : 0
                    border.color: root.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                    StyledText {
                        anchors.centerIn: parent
                        visible: root.hovering ? cell.inHover : cell.inCurrent
                        readonly property int rows: root.hovering ? root.hoverRows : root.rows
                        readonly property int columns: root.hovering ? root.hoverColumns : root.columns
                        text: (root.bottomUp ? rows - cell.row : cell.row - 1) * columns
                            + (root.rightToLeft ? columns - cell.column : cell.column - 1) + 1
                        font.pixelSize: Math.max(8, Math.min(11, cell.height - 3))
                        color: root.hovering ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                    }
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
                        onClicked: { root.forceActiveFocus(); root.picked(cell.row, cell.column); }
                    }
                }
            }
        }
    }
}
