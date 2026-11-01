import "periodic_table.js" as PTable
import QtQuick

Item {
    id: root
    readonly property var elements: PTable.elements
    readonly property var series: PTable.series
    property real spacing: 6
    implicitWidth: mainLayout.implicitWidth
    implicitHeight: mainLayout.implicitHeight

    Column {
        id: mainLayout
        anchors.centerIn: parent
        spacing: root.spacing
        // Keep the complete table visible when the logical display is smaller than its natural size.
        scale: Math.min(1, root.width / Math.max(1, implicitWidth), root.height / Math.max(1, implicitHeight))

        Repeater { // Main table rows
            model: root.elements
            
            delegate: Row { // Table cells
                id: tableRow
                spacing: root.spacing
                required property var modelData
                
                Repeater {
                    model: tableRow.modelData
                    delegate: ElementTile {
                        required property var modelData
                        element: modelData
                    }

                }
            }
            
        }

        Item {
            id: gap
            implicitHeight: 20
        }

        Repeater { // Main table rows
            model: root.series
            
            delegate: Row { // Table cells
                id: seriesTableRow
                spacing: root.spacing
                required property var modelData
                
                Repeater {
                    model: seriesTableRow.modelData
                    delegate: ElementTile {
                        required property var modelData
                        element: modelData
                    }

                }
            }
            
        }
    }
    
}
