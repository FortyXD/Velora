pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets

RippleButton {
    id: root
    required property QsMenuEntry menuEntry
    property bool forceIconColumn: false
    property bool forceSpecialInteractionColumn: false
    readonly property bool hasIcon: menuEntry.icon.length > 0
    readonly property bool hasSpecialInteraction: menuEntry.buttonType !== QsMenuButtonType.None

    signal dismiss()
    signal openSubmenu(handle: QsMenuHandle)

    // Looks like the entries of the shell's other menus (ContextMenuPopup)
    readonly property color colContent: !root.enabled ? Appearance.colors.colSubtext
        : root.hovered ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
    colBackground: ColorUtils.transparentize(Appearance.colors.colLayer0)
    colBackgroundHover: menuEntry.isSeparator ? colBackground : Appearance.colors.colPrimary
    colRipple: Appearance.colors.colPrimaryActive
    enabled: !menuEntry.isSeparator && menuEntry.enabled
    opacity: 1

    horizontalPadding: 10
    implicitWidth: contentItem.implicitWidth + horizontalPadding * 2
    implicitHeight: menuEntry.isSeparator ? 9 : Appearance.popup.menuRowHeight
    Layout.fillWidth: true

    Rectangle {
        visible: root.menuEntry.isSeparator
        anchors.centerIn: parent
        width: parent.width - 16
        height: 1
        color: Appearance.colors.colOutlineVariant
    }

    releaseAction: () => { 
        if (menuEntry.hasChildren) {
            root.openSubmenu(root.menuEntry);
            return;
        }
        menuEntry.triggered();
        root.dismiss(); 
    }
    altAction: (event) => { // Not hog right-click
        event.accepted = false;
    }

    contentItem: RowLayout {
        id: contentItem
        anchors {
            verticalCenter: parent.verticalCenter
            left: parent.left
            right: parent.right
            leftMargin: root.horizontalPadding
            rightMargin: root.horizontalPadding
        }
        spacing: 8
        visible: !root.menuEntry.isSeparator

        // Interaction: checkbox or radio button
        Item {
            visible: root.hasSpecialInteraction || root.forceSpecialInteractionColumn
            implicitWidth: 16
            implicitHeight: 16

            Loader {
                anchors.fill: parent
                active: root.menuEntry.buttonType === QsMenuButtonType.RadioButton

                sourceComponent: StyledRadioButton {
                    enabled: false
                    padding: 0
                    checked: root.menuEntry.checkState === Qt.Checked
                }
            }

            Loader {
                anchors.fill: parent
                active: root.menuEntry.buttonType === QsMenuButtonType.CheckBox && root.menuEntry.checkState !== Qt.Unchecked

                sourceComponent: MaterialSymbol {
                    text: root.menuEntry.checkState === Qt.PartiallyChecked ? "check_indeterminate_small" : "check"
                    iconSize: Appearance.popup.menuIconSize
                    color: root.colContent
                }
            }
        }

        // Button icon
        Item {
            visible: root.hasIcon || root.forceIconColumn
            implicitWidth: 16
            implicitHeight: 16

            Loader {
                anchors.centerIn: parent
                active: root.menuEntry.icon.length > 0
                sourceComponent: IconImage {
                    asynchronous: true
                    source: root.menuEntry.icon
                    implicitSize: 16
                    mipmap: true
                }
            }
        }

        StyledText {
            id: label
            text: root.menuEntry.text
            font.pixelSize: Appearance.popup.textSize
            color: root.colContent
            elide: Text.ElideRight
            Layout.fillWidth: true
        }

        Loader {
            active: root.menuEntry.hasChildren

            sourceComponent: MaterialSymbol {
                text: "chevron_right"
                iconSize: Appearance.popup.menuIconSize
                color: root.colContent
            }
        }
    }
}
