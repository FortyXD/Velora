import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

SettingsBranchLink {
    id: root
    required property string scene
    property int pictureHeight: 150
    readonly property bool shown: branch.page.pageShown && branch.page.tab === branch.page.overviewKey
    Layout.fillWidth: true
    Layout.fillHeight: true
    Layout.minimumWidth: 0
    Layout.preferredWidth: 1
    implicitHeight: contentItem.implicitHeight + topPadding + bottomPadding
    padding: 8; leftPadding: 8; rightPadding: 8
    buttonRadius: Appearance.rounding.normal
    colBackground: Appearance.colors.colLayer2
    Accessible.name: title
    Accessible.description: summary
    onHoveredChanged: if (hovered && shown) preview.replay()
    onVisualFocusChanged: if (visualFocus && shown) preview.replay()

    contentItem: ColumnLayout {
        spacing: 0
        ToolsPreview {
            id: preview
            Layout.fillWidth: true
            Layout.preferredHeight: root.pictureHeight
            scene: root.scene
            shown: root.shown
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 8; Layout.rightMargin: 6
            Layout.topMargin: 8; Layout.bottomMargin: 5
            spacing: 8
            ColumnLayout {
                Layout.fillWidth: true; Layout.minimumWidth: 0
                spacing: 2
                StyledText {
                    Layout.fillWidth: true
                    text: root.title; wrapMode: Text.Wrap
                    color: Appearance.colors.colOnLayer2
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.summary; wrapMode: Text.WordWrap
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
            MaterialSymbol {
                text: "chevron_right"; iconSize: 18; color: Appearance.colors.colSubtext
                transform: Translate {
                    x: root.hovered ? 2 : 0
                    Behavior on x { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.OutCubic } }
                }
            }
        }
    }
}
