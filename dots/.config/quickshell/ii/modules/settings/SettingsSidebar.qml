import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Navigation of the settings window: search, profile card and the pages in groups,
 * each with a colored icon. Collapses to an icon rail when `expanded` is false.
 */
Item {
    id: root

    required property var pages
    property int currentPage: 0
    property bool expanded: true
    property bool searching: false
    property alias searchText: searchInput.text
    property string profilePageKey: "about"
    // A subpage (one with a `parentKey`, opened from inside another page) keeps that page highlighted
    readonly property int highlightedPage: {
        const parentKey = root.pages[root.currentPage]?.parentKey ?? "";
        const parentIndex = parentKey.length > 0 ? root.pages.findIndex(page => page.key === parentKey) : -1;
        return parentIndex >= 0 ? parentIndex : root.currentPage;
    }

    readonly property real collapsedWidth: 64
    readonly property real expandedWidth: 260
    readonly property real sidePadding: 10
    readonly property real itemHeight: 38
    readonly property real railContentWidth: root.collapsedWidth - root.sidePadding * 2

    signal pageSelected(int index)
    signal searchAccepted()

    function focusSearch() {
        searchInput.forceActiveFocus();
        searchInput.selectAll();
    }

    // Icon colors are nudged towards the accent so they sit well with any wallpaper
    function iconColor(hex) {
        return ColorUtils.mix(hex, Appearance.colors.colPrimary, 0.82);
    }

    implicitWidth: root.expanded ? root.expandedWidth : root.collapsedWidth
    Behavior on implicitWidth {
        NumberAnimation {
            duration: Appearance.animation.elementMove.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
        }
    }
    clip: true

    // Entrance animation
    opacity: 0
    transform: Translate {
        id: entranceTranslate
        x: -18
    }
    Component.onCompleted: entranceAnim.start()
    ParallelAnimation {
        id: entranceAnim
        NumberAnimation { target: root; property: "opacity"; to: 1; duration: 350; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel }
        NumberAnimation { target: entranceTranslate; property: "x"; to: 0; duration: 500; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel }
    }

    component PageIcon: Rectangle {
        id: pageIcon
        property string icon
        property real iconRotation: 0
        property color tint: "#888888"
        implicitWidth: 26
        implicitHeight: 26
        radius: 8
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.lighter(pageIcon.tint, 1.12) }
            GradientStop { position: 1; color: pageIcon.tint }
        }
        MaterialSymbol {
            anchors.centerIn: parent
            text: pageIcon.icon
            rotation: pageIcon.iconRotation
            iconSize: 17
            fill: 1
            color: "white"
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            leftMargin: root.sidePadding
            rightMargin: root.sidePadding
            topMargin: 6
            bottomMargin: 10
        }
        spacing: 10

        // Search
        Item {
            Layout.fillWidth: true
            implicitHeight: 38

            Rectangle {
                anchors.fill: parent
                radius: Appearance.rounding.full
                color: searchInput.activeFocus ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
                border.width: searchInput.activeFocus ? 2 : 0
                border.color: Appearance.colors.colPrimary
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.IBeamCursor
                    onClicked: searchInput.forceActiveFocus()
                }

                MaterialSymbol {
                    id: searchIcon
                    x: (root.railContentWidth - width) / 2
                    anchors.verticalCenter: parent.verticalCenter
                    text: "search"
                    iconSize: 20
                    color: searchInput.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                }

                StyledTextInput {
                    id: searchInput
                    anchors {
                        left: searchIcon.right
                        leftMargin: 8
                        right: clearButton.left
                        rightMargin: 4
                        verticalCenter: parent.verticalCenter
                    }
                    opacity: root.expanded ? 1 : 0
                    enabled: root.expanded
                    clip: true
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.small
                    Keys.onReturnPressed: root.searchAccepted()
                    Keys.onEnterPressed: root.searchAccepted()

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: searchInput.text.length === 0
                        text: Translation.tr("Search")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }

                RippleButton {
                    id: clearButton
                    anchors {
                        right: parent.right
                        rightMargin: 4
                        verticalCenter: parent.verticalCenter
                    }
                    visible: root.expanded && searchInput.text.length > 0
                    implicitWidth: 30
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.full
                    onClicked: {
                        searchInput.text = "";
                        searchInput.forceActiveFocus();
                    }
                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        text: "close"
                        iconSize: 18
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }
        }

        // Profile
        RippleButton {
            id: profileButton
            readonly property int pageIndex: root.pages.findIndex(page => page.key === root.profilePageKey)
            readonly property bool current: root.currentPage === pageIndex && !root.searching
            Layout.fillWidth: true
            implicitHeight: 58
            buttonRadius: Appearance.rounding.normal
            colBackground: current ? Appearance.colors.colPrimary : "transparent"
            colBackgroundHover: current ? Appearance.colors.colPrimaryHover : Appearance.colors.colLayer0Hover
            colRipple: current ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer0Active
            onClicked: root.pageSelected(pageIndex)

            contentItem: Item {
                Rectangle {
                    id: avatar
                    x: (root.railContentWidth - width) / 2
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 40
                    implicitHeight: 40
                    radius: width / 2
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.lighter(Appearance.colors.colPrimary, 1.15) }
                        GradientStop { position: 1; color: Appearance.colors.colTertiary }
                    }
                    StyledText {
                        anchors.centerIn: parent
                        text: (SystemInfo.username || "?").charAt(0).toUpperCase()
                        font.pixelSize: 19
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnPrimary
                    }
                }
                ColumnLayout {
                    anchors {
                        left: avatar.right
                        leftMargin: 12
                        right: parent.right
                        rightMargin: 10
                        verticalCenter: parent.verticalCenter
                    }
                    opacity: root.expanded ? 1 : 0
                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: SystemInfo.username
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Medium
                        color: profileButton.current ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: `Velora · ${SystemInfo.distroName}`
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: profileButton.current ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
                    }
                }
            }
            StyledToolTip {
                extraVisibleCondition: !root.expanded
                text: SystemInfo.username
            }
        }

        // Pages
        StyledFlickable {
            id: navFlickable
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: navColumn.implicitHeight
            clip: true
            ScrollBar.vertical: null

            Rectangle { // Selected page, slides between items
                id: activeIndicator
                readonly property Item target: navRepeater.count > root.highlightedPage ? navRepeater.itemAt(root.highlightedPage) : null
                visible: target !== null && target.visible
                width: navColumn.width
                height: root.itemHeight
                y: target ? target.y + target.buttonY : 0
                radius: Appearance.rounding.small
                color: root.searching ? Appearance.colors.colLayer1 : Appearance.colors.colPrimary
                Behavior on y {
                    NumberAnimation {
                        duration: Appearance.animationCurves.expressiveFastSpatialDuration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
                    }
                }
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }

            ColumnLayout {
                id: navColumn
                width: navFlickable.width
                spacing: 1

                Repeater {
                    id: navRepeater
                    model: root.pages
                    delegate: ColumnLayout {
                        id: navDelegate
                        required property int index
                        required property var modelData
                        readonly property bool current: index === root.highlightedPage && !root.searching
                        readonly property bool groupStart: index > 0 && root.pages[index - 1].group !== modelData.group
                        readonly property real buttonY: navButton.y
                        visible: !modelData.hidden
                        Layout.fillWidth: true
                        spacing: 0

                        Item { // Gap between groups, a short line when collapsed
                            visible: navDelegate.groupStart
                            Layout.fillWidth: true
                            implicitHeight: 13
                            Rectangle {
                                opacity: root.expanded ? 0 : 1
                                Behavior on opacity {
                                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                }
                                x: (root.railContentWidth - width) / 2
                                anchors.verticalCenter: parent.verticalCenter
                                width: 20
                                height: 1
                                color: Appearance.colors.colOutlineVariant
                            }
                        }

                        RippleButton {
                            id: navButton
                            Layout.fillWidth: true
                            implicitHeight: root.itemHeight
                            buttonRadius: Appearance.rounding.small
                            colBackgroundHover: navDelegate.current ? "transparent" : Appearance.colors.colLayer0Hover
                            colRipple: navDelegate.current ? Appearance.colors.colPrimaryActive : Appearance.colors.colLayer0Active
                            onClicked: root.pageSelected(navDelegate.index)

                            contentItem: Item {
                                PageIcon {
                                    id: navIcon
                                    x: (root.railContentWidth - width) / 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    icon: navDelegate.modelData.icon
                                    iconRotation: navDelegate.modelData.iconRotation ?? 0
                                    tint: root.iconColor(navDelegate.modelData.color)
                                    scale: navButton.down ? 0.9 : 1
                                    Behavior on scale {
                                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                    }
                                }
                                StyledText {
                                    anchors {
                                        left: navIcon.right
                                        leftMargin: 12
                                        right: parent.right
                                        rightMargin: 10
                                        verticalCenter: parent.verticalCenter
                                    }
                                    opacity: root.expanded ? 1 : 0
                                    Behavior on opacity {
                                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                    }
                                    text: navDelegate.modelData.name
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: navDelegate.current ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer0
                                    Behavior on color {
                                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                    }
                                }
                            }

                            StyledToolTip {
                                extraVisibleCondition: !root.expanded
                                text: navDelegate.modelData.name
                            }
                        }
                    }
                }
            }
        }
    }
}
