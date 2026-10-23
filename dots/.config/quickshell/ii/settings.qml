//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

// Adjust this to make the app smaller or larger
//@ pragma Env QT_SCALE_FACTOR=1

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions as CF
import qs.modules.settings

ApplicationWindow {
    id: root
    property real contentPadding: 8

    // Pages in sidebar order. `group` only separates them visually, so related pages read as one block.
    // Shell and Hyprland options are mixed freely: a page is about a topic, not about who implements it.
    // `hero: false` leaves out the big title card, for pages that start with their own picture or status.
    property var pages: [
        {
            key: "wifi", group: "connections", color: "#0A84FF", icon: "wifi", hero: false,
            name: Translation.tr("Wi-Fi"),
            description: Translation.tr("Networks nearby, saved networks and your connection"),
            component: "modules/settings/WifiConfig.qml"
        },
        {
            key: "bluetooth", group: "connections", color: "#0A84FF", icon: "bluetooth", hero: false,
            name: Translation.tr("Bluetooth"),
            description: Translation.tr("Headphones, mice and other devices: pair, connect and forget"),
            component: "modules/settings/BluetoothConfig.qml"
        },
        {
            key: "general", group: "basics", color: "#8E8E93", icon: "settings",
            name: Translation.tr("General"),
            description: Translation.tr("Language, date and time"),
            component: "modules/settings/GeneralConfig.qml"
        },
        {
            key: "apps", group: "basics", color: "#34C759", icon: "apps",
            name: Translation.tr("Default Apps"),
            description: Translation.tr("Browser, terminal, file manager and the apps that open your files"),
            component: "modules/settings/DefaultAppsConfig.qml"
        },
        {
            key: "appearance", group: "basics", color: "#5856D6", icon: "palette", hero: false,
            name: Translation.tr("Appearance"),
            description: Translation.tr("Colors, transparency, window style, motion and fonts"),
            component: "modules/settings/AppearanceConfig.qml"
        },
        {
            key: "presets", group: "basics", color: "#FF9F0A", icon: "auto_awesome_mosaic",
            name: Translation.tr("Presets"),
            description: Translation.tr("Ready-made looks for the bar, theme, dock and motion, and your own"),
            component: "modules/settings/PresetsConfig.qml"
        },
        {
            key: "wallpaper", group: "basics", color: "#32ADE6", icon: "wallpaper",
            name: Translation.tr("Wallpaper"),
            description: Translation.tr("Your wallpaper, the colors made from it and how it moves"),
            component: "modules/settings/WallpaperConfig.qml"
        },
        {
            key: "widgets", group: "basics", color: "#AF52DE", icon: "widgets", hero: false,
            name: Translation.tr("Widgets"),
            description: Translation.tr("Clock, weather, media and other widgets on your desktop"),
            component: "modules/settings/WidgetsConfig.qml"
        },
        {
            key: "desktop", group: "desktop", color: "#0A84FF", icon: "dock_to_bottom", hero: false,
            name: Translation.tr("Desktop & Dock"),
            description: Translation.tr("Window layout and gaps, the dock, overview and hot corners"),
            component: "modules/settings/DesktopConfig.qml"
        },
        {
            key: "bar", group: "desktop", color: "#007AFF", icon: "toast", iconRotation: 180, hero: false,
            name: Translation.tr("Bar"),
            description: Translation.tr("Arrange the bar's widgets right on it, its look and behavior"),
            component: "modules/settings/BarConfig.qml"
        },
        {
            key: "sidebars", group: "desktop", color: "#30B0C7", icon: "side_navigation",
            name: Translation.tr("Sidebars"),
            description: Translation.tr("Quick settings on the right, assistant and translator on the left"),
            component: "modules/settings/SidebarsConfig.qml"
        },
        {
            key: "notifications", group: "desktop", color: "#FF3B30", icon: "notifications",
            name: Translation.tr("Notifications"),
            description: Translation.tr("Do not disturb, what each app may show, and popups"),
            component: "modules/settings/NotificationsConfig.qml"
        },
        {
            key: "lock", group: "desktop", color: "#636366", icon: "lock",
            name: Translation.tr("Lock Screen"),
            description: Translation.tr("How the lock screen looks and what it protects"),
            component: "modules/settings/LockConfig.qml"
        },
        {
            key: "displays", group: "devices", color: "#0A84FF", icon: "desktop_windows",
            name: Translation.tr("Displays"),
            description: Translation.tr("Resolution, scale, arrangement, brightness and night light"),
            component: "modules/settings/DisplaysConfig.qml"
        },
        {
            key: "keyboard", group: "devices", color: "#8E8E93", icon: "keyboard",
            name: Translation.tr("Keyboard"),
            description: Translation.tr("Layouts on a live keyboard, what keys do, and key repeat"),
            component: "modules/settings/KeyboardConfig.qml"
        },
        {
            key: "shortcuts", group: "devices", color: "#5E5CE6", icon: "keyboard_command_key",
            name: Translation.tr("Keyboard Shortcuts"),
            description: Translation.tr("See, change and add shortcuts, and style the cheat sheet"),
            component: "modules/settings/ShortcutsConfig.qml"
        },
        {
            key: "mouse", group: "devices", color: "#8E8E93", icon: "mouse",
            name: Translation.tr("Mouse & Touchpad"),
            description: Translation.tr("Pointer speed, scrolling, gestures and focus"),
            component: "modules/settings/MouseConfig.qml"
        },
        {
            key: "sound", group: "devices", color: "#FF2D55", icon: "volume_up",
            name: Translation.tr("Sound"),
            description: Translation.tr("Speakers, microphones, each app's volume and system sounds"),
            component: "modules/settings/SoundConfig.qml"
        },
        {
            key: "battery", group: "devices", color: "#34C759", icon: "battery_android_full",
            name: Translation.tr("Battery & energy"),
            description: Translation.tr("Energy saving, warnings and automatic suspend"),
            component: "modules/settings/BatteryConfig.qml"
        },
        {
            key: "search", group: "system", color: "#FF9500", icon: "search",
            name: Translation.tr("Search & AI"),
            description: Translation.tr("App search, the assistant and music recognition"),
            component: "modules/settings/SearchConfig.qml"
        },
        {
            key: "tools", group: "system", color: "#FFB800", icon: "screenshot_region",
            name: Translation.tr("Screenshots & Tools"),
            description: Translation.tr("Region selection, save folders and the overlay"),
            component: "modules/settings/ToolsConfig.qml"
        },
        {
            key: "advanced", group: "system", color: "#8E8E93", icon: "code",
            name: Translation.tr("Advanced"),
            description: Translation.tr("Config files, work safety, translation and polling"),
            component: "modules/settings/AdvancedConfig.qml"
        },
        {
            key: "about", group: "system", color: "#8E8E93", icon: "info", hidden: true,
            name: Translation.tr("About"),
            description: Translation.tr("Your system and the Folis dotfiles"),
            component: "modules/settings/About.qml"
        }
    ]
    property int currentPage: Math.max(0, root.pageIndex(pageStateFile.text().trim())) // Last opened page
    property int pageDirection: 1
    property bool loadAllPages: false // Search needs every page built
    // Pages are built one after another in the background once the first one is up, so a click shows a
    // finished page instead of building it on the spot (that took up to 0.7 s for the heavier pages).
    // All at once froze the window for seconds, long enough for Hyprland to call it not responding.
    property bool backgroundPreload: false
    property int preloadedPages: 0
    readonly property bool preloading: (root.loadAllPages || root.backgroundPreload) && root.preloadedPages < root.pages.length
    readonly property bool searching: sidebar.searchText.trim().length > 0
    readonly property var currentPageData: root.pages[root.currentPage]

    // Back / forward history
    property var history: [root.currentPage]
    property int historyIndex: 0
    readonly property bool canGoBack: root.historyIndex > 0
    readonly property bool canGoForward: root.historyIndex < root.history.length - 1

    // Keys of pages that were merged into others still lead somewhere
    readonly property var pageAliases: ({ "barLayout": "bar" })

    function pageIndex(key) {
        const wanted = root.pageAliases[key] ?? key;
        return root.pages.findIndex(page => page.key === wanted);
    }

    function showPage(index) {
        if (sidebar.searchText.length > 0) sidebar.searchText = "";
        if (index === root.currentPage) return;
        root.pageDirection = index > root.currentPage ? 1 : -1;
        root.currentPage = index;
        pageStateFile.setText(root.pages[index].key);
    }

    function setPage(index) {
        if (index < 0 || index >= root.pages.length) return;
        if (index !== root.currentPage) {
            root.history = [...root.history.slice(0, root.historyIndex + 1), index];
            root.historyIndex = root.history.length - 1;
        }
        root.showPage(index);
    }

    function goBack() {
        if (!root.canGoBack) return;
        root.historyIndex--;
        root.showPage(root.history[root.historyIndex]);
    }

    function goForward() {
        if (!root.canGoForward) return;
        root.historyIndex++;
        root.showPage(root.history[root.historyIndex]);
    }

    // Opens a page by key and, if `sectionTitle` is given, scrolls to that section
    function openPage(key, sectionTitle) {
        const index = root.pageIndex(key);
        if (index < 0) return;
        root.setPage(index);
        if (sectionTitle && sectionTitle.length > 0) {
            revealTimer.pageIndex = index;
            revealTimer.target = null;
            revealTimer.sectionTitle = sectionTitle;
            revealTimer.restart();
        }
    }

    function pageItemAt(index) {
        return pageRepeater.itemAt(index)?.item ?? null;
    }

    // A section, or a titled group inside one, with this title
    function findSection(node, title) {
        if (!node) return null;
        if ((node.settingsSection || node.settingsSearchable) && node.title === title) return node;
        const kids = node.children ?? [];
        for (let i = 0; i < kids.length; i++) {
            const found = root.findSection(kids[i], title);
            if (found) return found;
        }
        return null;
    }

    Timer { // Waits for the page to be laid out before scrolling to something on it
        id: revealTimer
        property int pageIndex: -1
        property var target: null
        property string sectionTitle: ""
        interval: 160
        onTriggered: {
            const page = root.pageItemAt(pageIndex);
            if (!page?.revealItem) return;
            const item = target ?? root.findSection(page, sectionTitle);
            if (!item) return;
            page.revealItem(item);
            revealCheckTimer.page = page;
            revealCheckTimer.item = item;
            revealCheckTimer.restart();
        }
    }
    Timer {
        interval: 30
        repeat: true
        running: root.preloading
        onTriggered: {
            // One page at a time: the next starts when the previous one has finished building
            if (root.preloadedPages > 0 && pageRepeater.itemAt(root.preloadedPages - 1)?.status === Loader.Loading) return;
            while (root.preloadedPages < root.pages.length && pageRepeater.itemAt(root.preloadedPages)?.status === Loader.Ready)
                root.preloadedPages++;
            root.preloadedPages = Math.min(root.preloadedPages + 1, root.pages.length);
            if (!root.preloading && root.loadAllPages) searchView.refresh();
        }
    }
    Timer { // Starts the background building once the window has settled
        interval: 600
        running: Config.ready && pageRepeater.itemAt(root.currentPage)?.status === Loader.Ready
        onTriggered: root.backgroundPreload = true
    }
    Timer { // Corrects the position if the page was still settling
        id: revealCheckTimer
        property var page: null
        property var item: null
        interval: 500
        onTriggered: page?.revealItem(item, false)
    }
    Connections { // Scrolling by hand cancels the correction
        target: revealCheckTimer.page
        ignoreUnknownSignals: true
        function onRevealCancelled() { revealCheckTimer.stop() }
    }

    visible: true
    onClosing: Qt.quit()
    title: "illogical-impulse Settings" // Matched by a Hyprland window rule

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme()
        Config.readWriteDelay = 0 // Settings app always only sets one var at a time so delay isn't needed
        // Deep links: QS_SETTINGS_PAGE=<page key> and QS_SETTINGS_SEARCH=<query>
        const startPage = root.pageIndex(Quickshell.env("QS_SETTINGS_PAGE") ?? "");
        if (startPage >= 0) root.setPage(startPage);
        const startSearch = Quickshell.env("QS_SETTINGS_SEARCH") ?? "";
        if (startSearch.length > 0) {
            sidebar.searchText = startSearch;
            sidebar.focusSearch();
        }
    }

    minimumWidth: 760
    minimumHeight: 500
    width: 1100
    height: 760
    color: Appearance.m3colors.m3background

    // Remember the last opened page
    FileView {
        id: pageStateFile
        path: CF.FileUtils.trimFileProtocol(`${Directories.state}/user/settings_page.txt`)
        blockLoading: true
    }

    Shortcut {
        sequences: ["Ctrl+PgDown", "Ctrl+Tab"]
        onActivated: root.setPage((root.currentPage + 1) % root.pages.length)
    }
    Shortcut {
        sequences: ["Ctrl+PgUp", "Ctrl+Shift+Tab", "Ctrl+Backtab"]
        onActivated: root.setPage((root.currentPage - 1 + root.pages.length) % root.pages.length)
    }
    Shortcut {
        sequences: [StandardKey.Back, "Alt+Left", "Ctrl+["]
        onActivated: root.goBack()
    }
    Shortcut {
        sequences: [StandardKey.Forward, "Alt+Right", "Ctrl+]"]
        onActivated: root.goForward()
    }
    Shortcut {
        sequences: [StandardKey.Find]
        onActivated: {
            if (!sidebar.expanded) sidebar.expandOverride = true;
            sidebar.focusSearch();
        }
    }
    Shortcut {
        sequence: "Escape"
        onActivated: {
            const focusItem = root.activeFocusItem;
            if (sidebar.searchText.length > 0) sidebar.searchText = "";
            else if (focusItem && focusItem.cursorPosition !== undefined) contentPane.forceActiveFocus(); // Leave the text field first
            else root.close();
        }
    }

    // Mouse back / forward buttons
    MouseArea {
        anchors.fill: parent
        z: -1
        acceptedButtons: Qt.BackButton | Qt.ForwardButton
        onPressed: event => {
            if (event.button === Qt.BackButton) root.goBack();
            else root.goForward();
        }
    }

    component ToolbarIconButton: RippleButton {
        id: toolbarButton
        property string buttonIcon
        implicitWidth: 36
        implicitHeight: 36
        buttonRadius: Appearance.rounding.full
        colBackgroundHover: Appearance.colors.colLayer1Hover
        colRipple: Appearance.colors.colLayer1Active
        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            text: toolbarButton.buttonIcon
            iconSize: 22
            color: Appearance.colors.colOnLayer1
        }
    }

    RowLayout {
        anchors {
            fill: parent
            margins: root.contentPadding
        }
        spacing: root.contentPadding

        SettingsSidebar {
            id: sidebar
            property var expandOverride: undefined
            readonly property bool autoExpanded: root.width >= 920
            onAutoExpandedChanged: expandOverride = undefined
            Layout.fillHeight: true
            pages: root.pages
            currentPage: root.currentPage
            searching: root.searching
            expanded: expandOverride === undefined ? autoExpanded : expandOverride
            onPageSelected: index => root.setPage(index)
            onSearchAccepted: searchView.acceptFirst()
            onSearchTextChanged: {
                if (searchText.trim().length > 0) root.loadAllPages = true;
                searchView.query = searchText;
            }
        }

        Rectangle { // Content pane
            id: contentPane
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Appearance.colors.colLayer1
            radius: Appearance.rounding.windowRounding - root.contentPadding
            clip: true

            // Entrance animation
            opacity: 0
            transform: Translate {
                id: contentEntranceTranslate
                y: 24
            }
            Component.onCompleted: contentEntranceAnim.start()
            ParallelAnimation {
                id: contentEntranceAnim
                NumberAnimation { target: contentPane; property: "opacity"; to: 1; duration: 400; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel }
                NumberAnimation { target: contentEntranceTranslate; property: "y"; to: 0; duration: 550; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel }
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // Toolbar: sidebar toggle, history, page title
                Item {
                    id: toolbar
                    Layout.fillWidth: true
                    implicitHeight: 54
                    readonly property string titleText: root.searching ? Translation.tr("Search") : root.currentPageData.name

                    // Title crossfades with a small slide whenever the page changes
                    property string shownTitle: titleText
                    onTitleTextChanged: titleAnim.restart()
                    SequentialAnimation {
                        id: titleAnim
                        ParallelAnimation {
                            NumberAnimation { target: titleLabel; property: "opacity"; to: 0; duration: 100; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedAccel }
                            NumberAnimation { target: titleTranslate; property: "x"; to: -8 * root.pageDirection; duration: 100; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedAccel }
                        }
                        ScriptAction {
                            script: {
                                toolbar.shownTitle = toolbar.titleText;
                                titleTranslate.x = 12 * root.pageDirection;
                            }
                        }
                        ParallelAnimation {
                            NumberAnimation { target: titleLabel; property: "opacity"; to: 1; duration: 240; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel }
                            NumberAnimation { target: titleTranslate; property: "x"; to: 0; duration: 340; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel }
                        }
                    }

                    RowLayout {
                        anchors {
                            fill: parent
                            leftMargin: 10
                            rightMargin: 10
                        }
                        spacing: 2

                        ToolbarIconButton {
                            buttonIcon: sidebar.expanded ? "left_panel_close" : "left_panel_open"
                            onClicked: sidebar.expandOverride = !sidebar.expanded
                            StyledToolTip {
                                text: sidebar.expanded ? Translation.tr("Hide sidebar") : Translation.tr("Show sidebar")
                            }
                        }
                        ToolbarIconButton {
                            Layout.leftMargin: 6
                            buttonIcon: "chevron_left"
                            enabled: root.canGoBack
                            onClicked: root.goBack()
                            StyledToolTip {
                                text: Translation.tr("Back") + " (Alt+←)"
                            }
                        }
                        ToolbarIconButton {
                            buttonIcon: "chevron_right"
                            enabled: root.canGoForward
                            onClicked: root.goForward()
                            StyledToolTip {
                                text: Translation.tr("Forward") + " (Alt+→)"
                            }
                        }
                        StyledText {
                            id: titleLabel
                            Layout.fillWidth: true
                            Layout.leftMargin: 10
                            transform: Translate {
                                id: titleTranslate
                            }
                            text: toolbar.shownTitle
                            elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.large
                            font.variableAxes: ({ "wght": 650, "wdth": 100 })
                            color: Appearance.colors.colOnLayer1
                        }
                        Item { // Hyprland is being reloaded with new options
                            implicitWidth: 28
                            implicitHeight: 28
                            opacity: HyprlandSettings.applying ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                            MaterialLoadingIndicator {
                                anchors.centerIn: parent
                                implicitSize: 24
                                loading: HyprlandSettings.applying
                            }
                            StyledToolTip {
                                extraVisibleCondition: false
                                alternativeVisibleCondition: applyingHover.containsMouse
                                text: Translation.tr("Applying")
                            }
                            MouseArea {
                                id: applyingHover
                                anchors.fill: parent
                                hoverEnabled: true
                            }
                        }
                        ToolbarIconButton {
                            visible: Config.options?.windows.showTitlebar ?? true
                            buttonIcon: "close"
                            onClicked: root.close()
                            StyledToolTip {
                                text: Translation.tr("Close") + " (Esc)"
                            }
                        }
                    }
                }

                // Pages. Each one is built the first time it's opened and then kept,
                // so its state and scroll position survive switching.
                Item {
                    id: pageStack
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Repeater {
                        id: pageRepeater
                        model: root.pages
                        delegate: Loader {
                            id: pageLoader
                            required property int index
                            required property var modelData
                            readonly property bool isCurrent: index === root.currentPage && !root.searching
                            property bool visited: false
                            property real slide: 0

                            anchors.fill: parent
                            active: Config.ready && (visited || index < root.preloadedPages)
                            source: modelData.component
                            // Built in the background without stalling the window; the page being opened is
                            // finished at once (switching `asynchronous` off completes a running load)
                            asynchronous: !isCurrent && !root.loadAllPages
                            // Kept visible (but transparent) so search can tell which options are hidden.
                            // Not disabled either: that restyled every control on both pages at each switch.
                            opacity: 0
                            z: isCurrent ? 1 : 0
                            transform: Translate { y: pageLoader.slide }

                            onLoaded: {
                                item.heroIcon = modelData.icon;
                                item.heroIconRotation = modelData.iconRotation ?? 0;
                                if (modelData.hero !== false) item.heroTitle = modelData.name;
                                item.heroDescription = modelData.description;
                                item.heroColor = Qt.binding(() => CF.ColorUtils.mix(modelData.color, Appearance.colors.colPrimary, 0.82));
                                if (item.pageShown !== undefined) item.pageShown = Qt.binding(() => pageLoader.isCurrent);
                            }
                            onIsCurrentChanged: {
                                if (isCurrent) {
                                    visited = true;
                                    exitAnim.stop();
                                    enterAnim.restart();
                                } else {
                                    enterAnim.stop();
                                    exitAnim.restart();
                                }
                            }
                            Component.onCompleted: {
                                if (!isCurrent) return;
                                visited = true;
                                enterAnim.restart();
                            }

                            MouseArea { // Pages behind the current one take no clicks, hover or wheel
                                anchors.fill: parent
                                z: 1000
                                visible: !pageLoader.isCurrent
                                hoverEnabled: true
                                acceptedButtons: Qt.AllButtons
                                onWheel: wheel => wheel.accepted = true
                            }

                            ParallelAnimation {
                                id: enterAnim
                                NumberAnimation { target: pageLoader; property: "opacity"; from: 0; to: 1; duration: 320; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel }
                                NumberAnimation { target: pageLoader; property: "slide"; from: 36 * root.pageDirection; to: 0; duration: 480; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel }
                            }
                            ParallelAnimation {
                                id: exitAnim
                                NumberAnimation { target: pageLoader; property: "opacity"; to: 0; duration: 140; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedAccel }
                                NumberAnimation { target: pageLoader; property: "slide"; to: -20 * root.pageDirection; duration: 140; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedAccel }
                            }
                        }
                    }

                    SettingsSearch {
                        id: searchView
                        anchors.fill: parent
                        pages: root.pages
                        pageItemAt: index => root.pageItemAt(index)
                        loading: root.preloading
                        enabled: root.searching
                        visible: opacity > 0
                        opacity: root.searching ? 1 : 0
                        z: 2
                        Behavior on opacity {
                            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                        }
                        onResultChosen: (pageIndex, item) => {
                            root.setPage(pageIndex);
                            if (item) {
                                revealTimer.pageIndex = pageIndex;
                                revealTimer.target = item;
                                revealTimer.restart();
                            }
                        }
                    }
                }
            }
        }
    }
}
