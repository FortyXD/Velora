import QtQuick

ConfigNavRow {
    required property SettingsBranch branch
    objectName: branch.key
    property string detail: ""
    property string summary: ""
    readonly property Item settingsDestination: branch.firstSection
    title: branch.page.sectionTitles[branch.key]
    searchText: [branch.page.sectionTitles[branch.key], title, detail, summary].join(" ")
    valueText: width >= 440 ? summary : ""
    description: width < 440 && summary ? summary : detail
    onClicked: {
        forceActiveFocus();
        branch.page.tab = branch.key;
    }
}
