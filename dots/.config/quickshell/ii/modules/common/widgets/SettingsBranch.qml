import QtQuick

SettingsTabPage {
    id: root
    required property SettingsDetailPage page
    property Component header
    default property alias sections: pane.contentData
    readonly property Item firstSection: headerLoader.item ?? sections[0] ?? null

    anchors.fill: parent
    current: page.tab
    enabled: shown
    onRevealRequested: key => page.navigateToSection(key)

    Loader {
        id: headerLoader
        width: parent.width
        sourceComponent: root.header
    }
    SettingsScrollPane {
        id: pane
        anchors {
            top: headerLoader.bottom
            topMargin: headerLoader.item ? 14 : 0
            left: parent.left; right: parent.right; bottom: parent.bottom
        }
    }
}
