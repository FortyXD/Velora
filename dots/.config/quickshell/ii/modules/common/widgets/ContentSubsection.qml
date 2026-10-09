import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * A labelled block inside a section card: title, optional description and its own rows.
 * `tooltip` adds an info icon next to the title.
 */
Item {
    id: root
    property string title: ""
    property string tooltip: ""
    property string description: ""
    default property alias contentData: sectionContent.contentData

    readonly property bool settingsSearchable: root.title.length > 0
    property string searchText: `${root.title} ${root.description}`

    Layout.fillWidth: true
    implicitWidth: layout.implicitWidth
    implicitHeight: layout.implicitHeight

    ColumnLayout {
        id: layout
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        spacing: 6

        ColumnLayout { // Header
            visible: root.title.length > 0 || root.description.length > 0
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.topMargin: 10
            spacing: 1

            RowLayout {
                Layout.fillWidth: true
                visible: root.title.length > 0
                spacing: 6
                StyledText {
                    text: root.title
                    color: Appearance.colors.colOnLayer2
                    font.pixelSize: Appearance.font.pixelSize.small
                }
                MaterialSymbol {
                    visible: root.tooltip && root.tooltip.length > 0
                    text: "info"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colSubtext
                    MouseArea {
                        id: infoMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.WhatsThisCursor
                        StyledToolTip {
                            extraVisibleCondition: false
                            alternativeVisibleCondition: infoMouseArea.containsMouse
                            text: root.tooltip
                        }
                    }
                }
                Item { Layout.fillWidth: true }
            }
            StyledText {
                visible: root.description.length > 0
                Layout.fillWidth: true
                text: root.description
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        SeparatedColumn {
            id: sectionContent
            Layout.fillWidth: true
            Layout.bottomMargin: 4
        }
    }
}
