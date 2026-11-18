import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

SettingsPanePopup {
    id: root
    property string title: ""
    default property alias settingsData: column.data
    property alias body: column
    width: Math.min(660, Math.max(0, (parent?.width ?? 692) - 32))
    height: Math.min(column.implicitHeight + header.implicitHeight + 40, Math.max(0, (parent?.height ?? 640) - 48))
    padding: 16
    onOpened: scroller.contentY = 0
    background: Rectangle {
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer1Base
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant
    }
    contentItem: ColumnLayout {
        spacing: 8
        RowLayout {
            id: header
            Layout.fillWidth: true
            StyledText {
                Layout.fillWidth: true
                text: root.title
                font.pixelSize: Appearance.font.pixelSize.large
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
            RippleButton {
                implicitWidth: 36; implicitHeight: 36
                buttonRadius: Appearance.rounding.full
                onClicked: root.close()
                contentItem: MaterialSymbol { text: "close"; iconSize: 20; horizontalAlignment: Text.AlignHCenter }
                StyledToolTip { text: Translation.tr("Close") }
            }
        }
        StyledFlickable {
            id: scroller
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: column.implicitHeight
            ScrollBar.vertical: ScrollBar {
                objectName: "settingsPopupScrollBar"
                policy: scroller.contentHeight > scroller.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
            }
            ColumnLayout {
                id: column
                width: scroller.width - (scroller.contentHeight > scroller.height ? 14 : 0)
                spacing: 12
            }
        }
    }
}
