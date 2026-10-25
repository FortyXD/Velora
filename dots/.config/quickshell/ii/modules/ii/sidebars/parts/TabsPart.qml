pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.ii.sidebars
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.sidebarRight.calendar

/**
 * Several parts in one place, one shown at a time (options: style "bar" | "rail", collapsible, start).
 * Bar: a tab bar above pages you can also swipe between; pages marked swipeOnly have no tab and come last.
 * Rail: a navigation rail beside the page, and it can fold into one line.
 * Pages are built the first time they're shown, then kept; the shown one is remembered (SidebarLayout.tabState).
 */
Item {
    id: root
    property Item host: null
    readonly property var part: root.host?.part ?? null
    readonly property string uid: root.part?.uid ?? ""
    readonly property var options: root.host?.options ?? {}
    readonly property string style: root.options.style === "rail" ? "rail" : "bar"
    readonly property var pages: (root.part?.tabs ?? []).filter(tab => SidebarLayout.shown(tab))
    // Pages with a tab first, then the ones reached only by swiping
    readonly property var order: root.style === "bar" ? [...root.pages.filter(page => !page.swipeOnly), ...root.pages.filter(page => page.swipeOnly)] : root.pages
    readonly property var tabPages: root.style === "bar" ? root.pages.filter(page => !page.swipeOnly) : root.pages
    property string currentUid: ""
    readonly property string shownUid: root.order.some(page => page.uid === root.currentUid) ? root.currentUid : (root.order[0]?.uid ?? "")
    readonly property int currentIndex: Math.max(0, root.order.findIndex(page => page.uid === root.shownUid))
    readonly property bool collapsible: root.style === "rail" && (root.options.collapsible ?? false)
    property bool collapsedState: false
    readonly property bool collapsed: root.collapsible && root.collapsedState
    readonly property bool partVisible: root.pages.length > 0

    implicitHeight: root.collapsed ? collapsedRow.implicitHeight : 300

    property bool restored: false
    function restore() {
        if (root.restored || !root.part || !Persistent.ready || root.order.length === 0) return;
        const state = SidebarLayout.tabState(root.uid);
        const start = root.options.start ?? "last";
        let uid = start !== "last" ? (root.order.find(page => page.type === start)?.uid ?? "") : "";
        if (!uid && state.tab) uid = root.order.find(page => page.uid === state.tab)?.uid ?? "";
        if (!uid && state.index !== undefined) uid = root.order[Math.max(0, Math.min(state.index, root.order.length - 1))]?.uid ?? "";
        root.currentUid = uid || root.order[0].uid;
        root.collapsedState = !!state.collapsed;
        root.restored = true;
    }
    onPartChanged: root.restore()
    onOrderChanged: root.restore()
    Component.onCompleted: root.restore()
    Connections {
        target: Persistent
        function onReadyChanged() { root.restore() }
    }

    function setCurrent(uid) {
        if (!uid || uid === root.shownUid) return;
        root.currentUid = uid;
        if (root.restored) SidebarLayout.setTabState(root.uid, { "tab": uid });
        if (root.host?.open) Qt.callLater(root.focusCurrent);
    }
    function cycle(step) {
        const index = Math.max(0, Math.min(root.order.length - 1, root.currentIndex + step));
        root.setCurrent(root.order[index]?.uid ?? "");
    }
    function setCollapsed(collapsed) {
        root.collapsedState = collapsed;
        SidebarLayout.setTabState(root.uid, { "collapsed": collapsed });
    }
    function currentHost() {
        const list = root.style === "bar" ? barPages : railPages;
        for (let i = 0; i < list.count; i++) {
            const host = list.itemAt(i);
            if (host?.uid === root.shownUid) return host;
        }
        return null;
    }
    function focusCurrent() {
        root.currentHost()?.focusPart();
    }
    // A page restored while the sidebar was hidden is placed before the pages have a size, which leaves the
    // view scrolled to an empty gap: snap it to the current page again
    function snap() {
        if (root.style === "bar") swipeView.contentItem.positionViewAtIndex(swipeView.currentIndex, ListView.Beginning);
    }

    // ---- Bar ----

    ColumnLayout {
        anchors.fill: parent
        visible: root.style === "bar"
        spacing: 10

        Toolbar {
            visible: root.tabPages.length > 1
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: root.width
            enableShadow: false
            ToolbarTabBar {
                id: tabBar
                // Names only while they fit; with many tabs they're icons
                readonly property bool compact: root.tabPages.length * 116 > root.width
                Layout.alignment: Qt.AlignHCenter
                tabButtonList: root.tabPages.map(page => {
                    const meta = SidebarCatalog.part(page.type);
                    return { "icon": meta?.icon ?? "tab", "name": tabBar.compact ? "" : (meta?.name ?? page.type) };
                })
                onCurrentIndexChanged: root.setCurrent(root.tabPages[currentIndex]?.uid ?? "")
                Binding on currentIndex {
                    value: root.currentIndex
                    when: root.currentIndex < root.tabPages.length // A page without a tab leaves the tab bar as it was
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1

            SwipeView {
                id: swipeView
                anchors.fill: parent
                spacing: 10
                onCurrentIndexChanged: root.setCurrent(root.order[currentIndex]?.uid ?? "") // Swiping
                Component.onCompleted: swipeView.setCurrentIndex(root.currentIndex)
                Connections {
                    target: root
                    function onCurrentIndexChanged() {
                        if (swipeView.currentIndex !== root.currentIndex) swipeView.setCurrentIndex(root.currentIndex);
                    }
                }
                onWidthChanged: Qt.callLater(root.snap)
                interactive: root.order.length > 1

                clip: true
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: swipeView.width
                        height: swipeView.height
                        radius: Appearance.rounding.small
                    }
                }

                Repeater {
                    id: barPages
                    model: root.style === "bar" ? root.order : []
                    delegate: SidebarPartHost {
                        required property var modelData
                        part: modelData
                        column: root.host?.column ?? null
                        page: true
                        current: modelData.uid === root.shownUid
                    }
                }
            }
        }
    }

    // ---- Rail ----

    RowLayout {
        id: collapsedRow
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        visible: root.style === "rail" && root.collapsed
        spacing: 15

        CalendarHeaderButton {
            Layout.margins: 10
            Layout.rightMargin: 0
            forceCircle: true
            downAction: () => root.setCollapsed(false)
            contentItem: MaterialSymbol {
                text: "keyboard_arrow_up"
                iconSize: Appearance.font.pixelSize.larger
                horizontalAlignment: Text.AlignHCenter
                color: Appearance.colors.colOnLayer1
            }
        }
        StyledText {
            readonly property bool aboutDays: root.pages.some(page => page.type === "calendar" || page.type === "todo")
            readonly property int remainingTasks: Todo.list.filter(task => !task.done).length
            Layout.fillWidth: true
            Layout.margins: 10
            Layout.leftMargin: 0
            elide: Text.ElideRight
            text: aboutDays ? Translation.tr("%1   •   %2 tasks").arg(DateTime.collapsedCalendarFormat).arg(remainingTasks)
                : (SidebarCatalog.part(root.order[root.currentIndex]?.type)?.name ?? "")
            font.pixelSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colOnLayer1
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.style === "rail" && !root.collapsed
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1
        clip: true

        RowLayout {
            anchors.fill: parent
            spacing: 20

            Item {
                visible: root.pages.length > 1 || root.collapsible
                Layout.fillHeight: true
                Layout.leftMargin: 10
                Layout.topMargin: 10
                implicitWidth: rail.implicitWidth
                NavigationRailTabArray {
                    id: rail
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 5
                    currentIndex: root.currentIndex
                    expanded: false
                    Repeater {
                        model: root.pages.length > 1 ? root.order : []
                        NavigationRailButton {
                            required property int index
                            required property var modelData
                            showToggledHighlight: false
                            toggled: root.currentIndex === index
                            buttonText: SidebarCatalog.part(modelData.type)?.name ?? ""
                            buttonIcon: SidebarCatalog.part(modelData.type)?.icon ?? "tab"
                            onPressed: root.setCurrent(modelData.uid)
                        }
                    }
                }
                CalendarHeaderButton {
                    visible: root.collapsible
                    anchors.left: parent.left
                    anchors.top: parent.top
                    forceCircle: true
                    downAction: () => root.setCollapsed(true)
                    contentItem: MaterialSymbol {
                        text: "keyboard_arrow_down"
                        iconSize: Appearance.font.pixelSize.larger
                        horizontalAlignment: Text.AlignHCenter
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Repeater {
                    id: railPages
                    model: root.style === "rail" ? root.order : []
                    delegate: SidebarPartHost {
                        id: railPage
                        required property var modelData
                        part: modelData
                        column: root.host?.column ?? null
                        page: true
                        current: modelData.uid === root.shownUid
                        anchors.fill: parent
                        opacity: railPage.current ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                    }
                }
            }
        }
    }
}
