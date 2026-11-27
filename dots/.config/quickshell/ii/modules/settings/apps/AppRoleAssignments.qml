pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    required property var roles
    required property var info
    required property var assignments
    required property var currentNames
    required property var webmailServices
    required property var searchForRole
    required property bool loaded
    required property bool pageActive
    property string expandedRole: "browser"
    signal choose(string role, Item trigger)
    signal assign(string role, string appId)
    signal saveCommand(string role, string command)
    signal setWebmail(string service)
    signal ensureVisible(Item card)

    Layout.fillWidth: true
    spacing: 5
    StyledText {
        Layout.fillWidth: true
        Layout.bottomMargin: 3
        text: Translation.tr("Everyday actions")
        font.pixelSize: Appearance.font.pixelSize.larger
        font.weight: Font.DemiBold
    }
    Repeater {
        id: cards
        model: root.roles
        delegate: AppAssignmentCard {
            id: card
            required property string modelData
            required property int index
            roleId: modelData
            info: root.info[modelData]
            roleData: root.assignments[modelData] ?? {}
            currentName: root.currentNames[modelData] ?? ""
            services: root.webmailServices
            roleSearch: root.searchForRole(modelData)
            expanded: root.expandedRole === modelData
            loaded: root.loaded
            pageActive: root.pageActive
            onExpandRequested: open => root.expandedRole = open ? modelData : ""
            onSettled: root.ensureVisible(card)
            onMoveFocus: offset => cards.itemAt(index + offset)?.header.forceActiveFocus(Qt.TabFocusReason)
            onBrowse: trigger => root.choose(modelData, trigger)
            onAssign: appId => root.assign(modelData, appId)
            onSaveCommand: value => root.saveCommand(modelData, value)
            onSetWebmail: value => root.setWebmail(value)
        }
    }
}
