import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

SettingsBranchLink {
    id: root
    default property alias diagram: miniature.data
    property color accent: Appearance.colors.colPrimary
    Accessible.name: title
    Accessible.description: summary
    Layout.fillWidth: true
    Layout.minimumWidth: 0
    Layout.preferredWidth: 1
    implicitHeight: Math.max(88, contentItem.implicitHeight + 24)
    colBackground: Appearance.colors.colLayer2
    buttonRadius: Appearance.rounding.normal
    contentItem: RowLayout {
        spacing: 12
        Rectangle {
            id: miniature
            implicitWidth: 64
            implicitHeight: 46
            radius: 9
            color: ColorUtils.mix(root.accent, Appearance.colors.colLayer2, 0.14)
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 4
            StyledText {
                Layout.fillWidth: true
                text: root.title
                wrapMode: Text.Wrap
                color: Appearance.colors.colOnLayer2
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
            }
            StyledText {
                Layout.fillWidth: true
                text: root.summary
                elide: Text.ElideRight
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }
        MaterialSymbol { text: "chevron_right"; iconSize: 17; color: Appearance.colors.colSubtext }
    }
}
