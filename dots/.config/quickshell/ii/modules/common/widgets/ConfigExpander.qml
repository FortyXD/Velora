import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Rows folded under a "More options" row inside a settings card, for fine-tuning most people never need.
 * Folded rows are only clipped, not hidden, so settings search still finds them; revealing one
 * (ContentPage.revealItem) unfolds it first.
 */
ColumnLayout {
    id: root
    property string title: Translation.tr("More options")
    property string description: ""
    property string buttonIcon: "tune"
    property bool expanded: false
    default property alias contentData: foldedRows.contentData

    property bool instant: false // Unfold without animation, so a reveal can scroll right away
    function settingsReveal() {
        if (root.expanded) return false;
        root.instant = true;
        root.expanded = true;
        Qt.callLater(() => root.instant = false);
        return true;
    }

    Layout.fillWidth: true
    spacing: 0

    RippleButton {
        id: header
        Layout.fillWidth: true
        implicitHeight: Math.max(46, contentItem.implicitHeight + 10 * 2)
        leftPadding: 12
        rightPadding: 14
        buttonRadius: Appearance.rounding.small
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colRipple: Appearance.colors.colLayer2Active
        onClicked: root.expanded = !root.expanded

        contentItem: RowLayout {
            spacing: 12
            ConfigIconTile {
                icon: root.buttonIcon
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1
                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    visible: root.description.length > 0 && !root.expanded
                    Layout.fillWidth: true
                    text: root.description
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
            MaterialSymbol {
                text: "expand_more"
                iconSize: 22
                rotation: root.expanded ? 180 : 0
                color: Appearance.colors.colSubtext
                Behavior on rotation {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }
    }

    Item {
        Layout.fillWidth: true
        implicitHeight: root.expanded ? foldedRows.implicitHeight + 1 : 0
        Layout.preferredHeight: implicitHeight // With an implicit height of 0 a layout keeps the last height
        clip: true
        enabled: root.expanded
        opacity: root.expanded ? 1 : 0
        Behavior on implicitHeight {
            enabled: !root.instant
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }
        Behavior on opacity {
            enabled: !root.instant
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        Rectangle { // Separator under the header
            x: 16
            width: parent.width - 32
            height: 1
            color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.3)
        }
        SeparatedColumn {
            id: foldedRows
            y: 1
            anchors {
                left: parent.left
                right: parent.right
            }
        }
    }
}
