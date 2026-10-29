import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * Top card of a connection page (Wi-Fi, Bluetooth): a big icon in the page's color, what is
 * connected right now and the main switch. Extra rows (`default` content) go under a line.
 */
Rectangle {
    id: root
    property string icon: ""
    property color iconColor: Appearance.colors.colPrimary
    property bool busy: false // Shows an activity ring without rotating the connection icon
    property string title: ""
    property string subtitle: ""
    property string detail: ""
    property bool checked: false
    property bool switchEnabled: true
    property string switchLabel: ""
    default property alias extraData: extraColumn.data

    signal toggled()

    readonly property bool settingsSearchable: true
    readonly property bool settingsSection: true
    property string searchText: `${root.title} ${root.switchLabel}`

    Layout.fillWidth: true
    implicitHeight: content.implicitHeight + 40
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer2

    ColumnLayout {
        id: content
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 20
        }
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            spacing: 18

            Rectangle {
                implicitWidth: 72
                implicitHeight: 72
                radius: 22
                gradient: Gradient {
                    GradientStop { position: 0; color: root.checked ? Qt.lighter(root.iconColor, 1.18) : Appearance.colors.colLayer3 }
                    GradientStop { position: 1; color: root.checked ? root.iconColor : Appearance.colors.colLayer3 }
                }
                StatusIcon {
                    anchors.centerIn: parent
                    text: root.icon
                    iconSize: 40
                    fill: root.checked ? 1 : 0
                    color: root.checked ? "white" : Appearance.colors.colSubtext
                    busy: root.busy
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    elide: Text.ElideRight
                    font {
                        family: Appearance.font.family.title
                        pixelSize: 22
                        variableAxes: Appearance.font.variableAxes.title
                    }
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    visible: root.subtitle.length > 0
                    Layout.fillWidth: true
                    text: root.subtitle
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: root.checked ? Appearance.colors.colOnLayer2 : Appearance.colors.colSubtext
                }
                StyledText {
                    visible: root.detail.length > 0
                    Layout.fillWidth: true
                    text: root.detail
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }

            StyledSwitch {
                Layout.alignment: Qt.AlignVCenter
                scale: 1
                enabled: root.switchEnabled
                checkable: false // Follows the real state, which arrives a moment after the click
                checked: root.checked
                onClicked: root.toggled()
            }
        }

        ColumnLayout {
            id: extraColumn
            visible: children.length > 0
            Layout.fillWidth: true
            spacing: 4
        }
    }
}
