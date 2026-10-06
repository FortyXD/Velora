import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Qt.labs.synchronizer

Item {
    id: root
    required property var scopeRoot
    property int sidebarPadding: 10
    anchors.fill: parent
    property bool aiChatEnabled: Config.options.policies.ai !== 0
    property bool translatorEnabled: Config.options.sidebar.translator.enable
    property bool animeEnabled: Config.options.policies.weeb !== 0
    property bool animeCloset: Config.options.policies.weeb === 2
    property var tabButtonList: [
        ...(root.aiChatEnabled ? [{"icon": "neurology", "name": Translation.tr("Intelligence")}] : []),
        ...(root.translatorEnabled ? [{"icon": "translate", "name": Translation.tr("Translator")}] : []),
        ...((root.animeEnabled && !root.animeCloset) ? [{"icon": "bookmark_heart", "name": Translation.tr("Anime")}] : [])
    ]
    // Pages in swipe order. Closet anime has no tab button but stays reachable by swiping.
    property var pageList: [
        ...(root.aiChatEnabled ? ["ai"] : []),
        ...(root.translatorEnabled ? ["translator"] : []),
        ...((root.tabButtonList.length === 0 || (!root.aiChatEnabled && !root.translatorEnabled && root.animeCloset)) ? ["placeholder"] : []),
        ...(root.animeEnabled ? ["anime"] : []),
    ]
    property int tabCount: swipeView.count

    function focusActiveItem() {
        swipeView.currentItem?.item?.forceActiveFocus()
    }

    property bool tabRestored: false // Don't overwrite the saved tab before it has been read

    function setTab(index) {
        if (index < 0 || index >= swipeView.count) return;
        if (tabBar.currentIndex !== index) tabBar.setCurrentIndex(index);
        if (swipeView.currentIndex !== index) swipeView.setCurrentIndex(index);
        if (root.tabRestored) Persistent.states.sidebar.leftTab = index;
        if (GlobalStates.sidebarLeftOpen) Qt.callLater(root.focusActiveItem); // Typing goes to the visible tab
    }

    function restoreTab() {
        if (root.tabRestored || !Persistent.ready) return;
        root.setTab(Math.min(Persistent.states.sidebar.leftTab, swipeView.count - 1));
        root.tabRestored = true;
    }

    Component.onCompleted: root.restoreTab()

    Connections {
        target: Persistent
        function onReadyChanged() {
            root.restoreTab();
        }
    }

    // A tab restored while the sidebar was hidden is positioned before the pages have a size,
    // which leaves the view scrolled to an empty gap: snap it to the current page again
    function snapToCurrentPage() {
        swipeView.contentItem.positionViewAtIndex(swipeView.currentIndex, ListView.Beginning);
    }

    Connections {
        target: GlobalStates
        function onSidebarLeftOpenChanged() {
            if (!GlobalStates.sidebarLeftOpen) return;
            root.snapToCurrentPage();
            root.focusActiveItem();
        }
    }

    Keys.onPressed: (event) => {
        if (event.modifiers === Qt.ControlModifier) {
            if (event.key === Qt.Key_PageDown) {
                root.setTab(swipeView.currentIndex + 1)
                event.accepted = true;
            }
            else if (event.key === Qt.Key_PageUp) {
                root.setTab(swipeView.currentIndex - 1)
                event.accepted = true;
            }
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: sidebarPadding
        }
        spacing: sidebarPadding

        Toolbar {
            visible: tabButtonList.length > 0
            Layout.alignment: Qt.AlignHCenter
            enableShadow: false
            ToolbarTabBar {
                id: tabBar
                Layout.alignment: Qt.AlignHCenter
                tabButtonList: root.tabButtonList
                onCurrentIndexChanged: root.setTab(currentIndex)
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            implicitWidth: swipeView.implicitWidth
            implicitHeight: swipeView.implicitHeight
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1

            SwipeView { // Content pages
                id: swipeView
                anchors.fill: parent
                spacing: 10
                onCurrentIndexChanged: root.setTab(currentIndex) // Swiping
                onWidthChanged: Qt.callLater(root.snapToCurrentPage)

                clip: true
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: swipeView.width
                        height: swipeView.height
                        radius: Appearance.rounding.small
                    }
                }

                // Each page is built the first time it's shown, then kept so its state survives tab switches
                Repeater {
                    model: root.pageList
                    delegate: Loader {
                        id: pageLoader
                        required property string modelData
                        // Not built while the sidebar is hidden, even for the remembered tab
                        property bool shown: SwipeView.isCurrentItem && GlobalStates.sidebarLeftOpen
                        property bool visited: false
                        active: visited
                        onShownChanged: if (shown) visited = true
                        Component.onCompleted: if (shown) visited = true
                        sourceComponent: {
                            switch (pageLoader.modelData) {
                                case "ai": return aiChat;
                                case "translator": return translator;
                                case "anime": return anime;
                                default: return placeholder;
                            }
                        }
                        onLoaded: if (SwipeView.isCurrentItem && GlobalStates.sidebarLeftOpen) item.forceActiveFocus()
                    }
                }
            }
        }

        Component {
            id: aiChat
            AiChat {}
        }
        Component {
            id: translator
            Translator {}
        }
        Component {
            id: anime
            Anime {}
        }
        Component {
            id: placeholder
            Item {
                StyledText {
                    anchors.centerIn: parent
                    text: root.animeCloset ? Translation.tr("Nothing") : Translation.tr("Enjoy your empty sidebar...")
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
