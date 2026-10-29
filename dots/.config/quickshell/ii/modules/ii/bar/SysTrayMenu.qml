pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

PopupWindow {
    id: root
    required property QsMenuHandle trayItemMenuHandle
    property string trayItemId: ""
    property real popupBackgroundMargin: 0

    signal menuClosed
    signal menuOpened(qsWindow: var) // Correct type is QsWindow, but QML does not like that

    color: "transparent"
    property real padding: Appearance.sizes.elevationMargin

    implicitHeight: {
        let result = 0;
        for (let child of stackView.children) {
            result = Math.max(child.implicitHeight, result);
        }
        return result + popupBackground.padding * 2 + root.padding * 2;
    }
    implicitWidth: {
        let result = 0;
        for (let child of stackView.children) {
            result = Math.max(child.implicitWidth, result);
        }
        return result + popupBackground.padding * 2 + root.padding * 2;
    }

    function open() {
        root.visible = true;
        root.menuOpened(root);
    }

    function close() {
        root.visible = false;
        while (stackView.depth > 1)
            stackView.pop();
        root.menuClosed();
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.BackButton | Qt.RightButton
        onPressed: event => {
            if ((event.button === Qt.BackButton || event.button === Qt.RightButton) && stackView.depth > 1)
                stackView.pop();
        }

        StyledRectangularShadow {
            target: popupBackground
            opacity: popupBackground.opacity
        }

        Rectangle { // Looks like the shell's other menus (ContextMenuPopup)
            id: popupBackground
            readonly property real padding: Appearance.popup.menuPadding
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: Config.options.bar.vertical ? parent.verticalCenter : undefined
                top: Config.options.bar.vertical ? undefined : Config.options.bar.bottom ? undefined : parent.top
                bottom: Config.options.bar.vertical ? undefined : Config.options.bar.bottom ? parent.bottom : undefined
                margins: root.padding
            }

            color: Appearance.popup.colBackground
            radius: Appearance.popup.radius
            border.width: 1
            border.color: Appearance.popup.colBorder
            clip: true

            // Grows a little out of the bar while it fades in
            opacity: 0
            scale: 0.92
            transformOrigin: !Config.options.bar.vertical ? (Config.options.bar.bottom ? Item.Bottom : Item.Top)
                : (Config.options.bar.bottom ? Item.Right : Item.Left)
            Component.onCompleted: {
                opacity = 1;
                scale = 1;
            }
            implicitWidth: Math.max(190, stackView.implicitWidth + popupBackground.padding * 2)
            implicitHeight: stackView.implicitHeight + popupBackground.padding * 2

            Behavior on opacity {
                NumberAnimation {
                    duration: 140
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: 180
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on implicitHeight {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }
            Behavior on implicitWidth {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }

            StackView {
                id: stackView
                anchors {
                    fill: parent
                    margins: popupBackground.padding
                }
                pushEnter: NoAnim {}
                pushExit: NoAnim {}
                popEnter: NoAnim {}
                popExit: NoAnim {}

                implicitWidth: currentItem.implicitWidth
                implicitHeight: currentItem.implicitHeight

                initialItem: SubMenu {
                    handle: root.trayItemMenuHandle
                }
            }
        }
    }

    component NoAnim: Transition {
        NumberAnimation {
            duration: 0
        }
    }

    component SubMenu: ColumnLayout {
        id: submenu
        required property QsMenuHandle handle
        property bool isSubMenu: false
        property bool shown: false
        opacity: shown ? 1 : 0

        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        Component.onCompleted: shown = true
        StackView.onActivating: shown = true
        StackView.onDeactivating: shown = false
        StackView.onRemoved: destroy()

        QsMenuOpener {
            id: menuOpener
            menu: submenu.handle
        }

        spacing: 0

        Loader {
            Layout.fillWidth: true
            visible: submenu.isSubMenu
            active: visible
            sourceComponent: RippleButton {
                id: backButton
                buttonRadius: Appearance.popup.smallRadius
                horizontalPadding: 10
                implicitWidth: contentItem.implicitWidth + horizontalPadding * 2
                implicitHeight: Appearance.popup.menuRowHeight
                colBackgroundHover: Appearance.colors.colPrimary
                colRipple: Appearance.colors.colPrimaryActive
                readonly property color colContent: hovered ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0

                downAction: () => stackView.pop()

                contentItem: RowLayout {
                    anchors {
                        verticalCenter: parent.verticalCenter
                        left: parent.left
                        right: parent.right
                        leftMargin: backButton.horizontalPadding
                        rightMargin: backButton.horizontalPadding
                    }
                    spacing: 8
                    MaterialSymbol {
                        iconSize: Appearance.popup.menuIconSize
                        text: "chevron_left"
                        color: backButton.colContent
                    }
                    StyledText {
                        Layout.fillWidth: true
                        font.pixelSize: Appearance.popup.textSize
                        color: backButton.colContent
                        text: Translation.tr("Back")
                    }
                }
            }
        }
        RippleButton {
            id: pinEntry
            buttonRadius: Appearance.popup.smallRadius
            horizontalPadding: 10
            implicitWidth: contentItem.implicitWidth + horizontalPadding * 2
            implicitHeight: Appearance.popup.menuRowHeight
            colBackgroundHover: Appearance.colors.colPrimary
            colRipple: Appearance.colors.colPrimaryActive
            readonly property color colContent: hovered ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
            Layout.topMargin: 0
            Layout.bottomMargin: 0
            Layout.fillWidth: true

            visible: root.trayItemId !== undefined && root.trayItemId.length > 0 && stackView.depth === 1
            releaseAction: () => TrayService.togglePin(root.trayItemId);

            contentItem: RowLayout {
                anchors {
                    verticalCenter: parent.verticalCenter
                    left: parent.left
                    right: parent.right
                    leftMargin: pinEntry.horizontalPadding
                    rightMargin: pinEntry.horizontalPadding
                }
                spacing: 8

                MaterialSymbol {
                    iconSize: Appearance.popup.menuIconSize
                    text: "push_pin"
                    color: pinEntry.colContent
                }

                StyledText {
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.popup.textSize
                    color: pinEntry.colContent
                    text: TrayService.isPinned(root.trayItemId) ? Translation.tr("Unpin") : Translation.tr("Pin")
                }
            }
        }

        Item { // Separator, like the menu's own ones
            visible: pinEntry.visible || submenu.isSubMenu
            Layout.fillWidth: true
            implicitHeight: 9
            Rectangle {
                anchors.centerIn: parent
                width: parent.width - 16
                height: 1
                color: Appearance.colors.colOutlineVariant
            }
        }

        Repeater {
            id: menuEntriesRepeater
            property bool iconColumnNeeded: {
                for (let i = 0; i < menuOpener.children.values.length; i++) {
                    if (menuOpener.children.values[i].icon.length > 0)
                        return true;
                }
                return false;
            }
            property bool specialInteractionColumnNeeded: {
                for (let i = 0; i < menuOpener.children.values.length; i++) {
                    if (menuOpener.children.values[i].buttonType !== QsMenuButtonType.None)
                        return true;
                }
                return false;
            }
            model: menuOpener.children
            delegate: SysTrayMenuEntry {
                required property QsMenuEntry modelData
                forceIconColumn: menuEntriesRepeater.iconColumnNeeded
                forceSpecialInteractionColumn: menuEntriesRepeater.specialInteractionColumnNeeded
                menuEntry: modelData

                buttonRadius: Appearance.popup.smallRadius

                onDismiss: root.close()
                onOpenSubmenu: handle => {
                    stackView.push(subMenuComponent.createObject(null, {
                        handle: handle,
                        isSubMenu: true
                    }));
                }
            }
        }
    }

    Component {
        id: subMenuComponent
        SubMenu {}
    }
}
