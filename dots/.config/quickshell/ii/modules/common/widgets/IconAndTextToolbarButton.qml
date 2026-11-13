import QtQuick
import QtQuick.Layouts
import qs.modules.common

ToolbarButton {
    id: iconBtn
    required property string iconText

    colBackgroundToggled: Appearance.colors.colSecondaryContainer
    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
    colRippleToggled: Appearance.colors.colSecondaryContainerActive
    property color colText: toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant

    contentItem: Item {
        implicitWidth: contentRow.implicitWidth
        implicitHeight: contentRow.implicitHeight

        // Controls sizes contentItem to availableWidth. Center the natural-size
        // group inside it, rather than centering a Row that is itself stretched.
        Row {
            id: contentRow
            anchors.centerIn: parent
            anchors.alignWhenCentered: false
            spacing: 4

            MaterialSymbol {
                visible: iconBtn.iconText.length > 0
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                iconSize: 22
                text: iconBtn.iconText
                color: iconBtn.colText
            }
            StyledText {
                visible: iconBtn.text.length > 0
                anchors.verticalCenter: parent.verticalCenter
                color: iconBtn.colText
                text: iconBtn.text
            }
        }
    }
}
