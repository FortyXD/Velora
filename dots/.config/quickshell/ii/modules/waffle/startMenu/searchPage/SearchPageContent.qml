pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.waffle.looks

BodyRectangle {
    id: root

    property alias context: searchResults.context
    property string searchText: LauncherSearch.query
    property alias currentIndex: searchResults.currentIndex

    ColumnLayout {
        anchors {
            fill: parent
            topMargin: 2
            leftMargin: 24
            rightMargin: 24
        }
        spacing: 12

        TagStrip {
            visible: !Assistant.panelOpen
            context: root.context
            Layout.fillWidth: true
            Layout.fillHeight: false
        }

        SearchResults {
            id: searchResults
            Layout.fillWidth: true
            Layout.fillHeight: !Assistant.panelOpen
            Layout.alignment: Qt.AlignTop
        }
        Item { visible: Assistant.panelOpen; Layout.fillWidth: true; Layout.fillHeight: true }
    }
}
