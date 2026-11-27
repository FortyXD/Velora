//@ pragma UseQApplication
// Its own app id, so the dock, the launcher and the window switcher show it with its own icon and name
//@ pragma AppId org.velora.Settings
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_FFMPEG_DECODING_HW_DEVICE_TYPES=vaapi
//@ pragma Env QT_FFMPEG_ENCODING_HW_DEVICE_TYPES=vaapi
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
    readonly property alias settingsPageViewport: pageStack

    TransformWatcher { id: popupMapping; a: root.Overlay.overlay; b: root.currentPageItem?.popupPane ?? null }
    function popupBoundsFor(item) {
        const pane = popupMapping.b;
        if (!pane || !item || !popupMapping.a) return null;
        popupMapping.transform;
        const x = item.width / 2, y = item.height / 2;
        if (!pageStack.contains(pageStack.mapFromItem(item, x, y))) return null;
        const target = pane.contains(pane.mapFromItem(item, x, y)) ? pane : pageStack;
        const rect = target.mapToItem(popupMapping.a, 0, 0, target.width, target.height);
        return {
            width: rect.width, height: rect.height, left: rect.x, top: rect.y,
            right: popupMapping.a.width - rect.x - rect.width,
            bottom: popupMapping.a.height - rect.y - rect.height
        };
    }

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
            key: "bluetooth-device", group: "connections", parentKey: "bluetooth", color: "#0A84FF", icon: "bluetooth", hidden: true, hero: false,
            name: Translation.tr("Bluetooth device"),
            description: Translation.tr("Everything about one device"),
            component: "modules/settings/BluetoothDeviceConfig.qml"
        },
        {
            key: "bluetooth-options", group: "connections", parentKey: "bluetooth", color: "#0A84FF", icon: "settings_bluetooth", hidden: true, hero: false,
            name: Translation.tr("Bluetooth settings"),
            description: Translation.tr("This computer's name and visibility, what happens at login, and receiving files"),
            component: "modules/settings/BluetoothOptionsConfig.qml"
        },
        {
            key: "connections", group: "connections", color: "#0A84FF", icon: "lan", hero: false,
            name: Translation.tr("Network & VPN"),
            description: Translation.tr("VPN, cable and every other saved connection"),
            component: "modules/settings/ConnectionsConfig.qml"
        },
        {
            key: "connection-editor", group: "connections", parentKey: "connections", color: "#0A84FF", icon: "edit", hidden: true, hero: false,
            name: Translation.tr("Edit connection"),
            description: Translation.tr("Addresses, security, VPN and everything else about one connection"),
            component: "modules/settings/ConnectionEditorConfig.qml"
        },
        {
            key: "general", group: "basics", color: "#8E8E93", icon: "settings", hero: false,
            name: Translation.tr("General"),
            description: Translation.tr("Updates, storage, language, date and time, and other things about your computer"),
            component: "modules/settings/GeneralConfig.qml"
        },
        {
            key: "apps", group: "basics", color: "#34C759", icon: "apps", hero: false,
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
            key: "presets", group: "basics", color: "#FF9F0A", icon: "auto_awesome_mosaic", hero: false,
            name: Translation.tr("Presets"),
            description: Translation.tr("Ready-made looks for the bar, theme, dock and motion, and your own"),
            component: "modules/settings/PresetsConfig.qml"
        },
        {
            key: "wallpaper", group: "basics", color: "#32ADE6", icon: "wallpaper", hero: false,
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
            key: "sidebars", group: "desktop", color: "#30B0C7", icon: "side_navigation", hero: false,
            name: Translation.tr("Sidebars"),
            description: Translation.tr("Two sidebars made of parts you choose: quick settings, media, weather, assistant, clipboard and more"),
            component: "modules/settings/SidebarsConfig.qml"
        },
        {
            key: "notifications", group: "desktop", color: "#FF3B30", icon: "notifications", hero: false,
            name: Translation.tr("Notifications"),
            description: Translation.tr("Do not disturb, what each app may show, and popups"),
            component: "modules/settings/NotificationsConfig.qml"
        },
        {
            key: "lock", group: "desktop", color: "#636366", icon: "lock", hero: false,
            name: Translation.tr("Lock Screen"),
            description: Translation.tr("How the lock screen looks and what it protects"),
            component: "modules/settings/LockConfig.qml"
        },
        {
            key: "displays", group: "devices", color: "#0A84FF", icon: "desktop_windows", hero: false,
            name: Translation.tr("Displays"),
            description: Translation.tr("Resolution, scale, arrangement, brightness and night light"),
            component: "modules/settings/DisplaysConfig.qml"
        },
        {
            key: "keyboard", group: "devices", color: "#5E5CE6", icon: "keyboard", hero: false,
            name: Translation.tr("Keyboard"),
            description: Translation.tr("Layouts, keyboard shortcuts and key repeat"),
            component: "modules/settings/KeyboardConfig.qml"
        },
        {
            key: "mouse", group: "devices", color: "#8E8E93", icon: "mouse", hero: false,
            name: Translation.tr("Mouse & Touchpad"),
            description: Translation.tr("Pointer speed, scrolling, gestures and focus"),
            component: "modules/settings/MouseConfig.qml"
        },
        {
            key: "sound", group: "devices", color: "#FF2D55", icon: "volume_up", hero: false,
            name: Translation.tr("Sound"),
            description: Translation.tr("Speakers, microphones, each app's volume and system sounds"),
            component: "modules/settings/SoundConfig.qml"
        },
        {
            key: "battery", group: "devices", color: "#34C759", icon: "battery_android_full", hero: false,
            name: Translation.tr("Battery & energy"),
            description: Translation.tr("Energy saving, warnings and automatic suspend"),
            component: "modules/settings/BatteryConfig.qml"
        },
        {
            key: "search", group: "system", color: "#FF9500", icon: "search", hero: false,
            name: Translation.tr("Search"),
            description: Translation.tr("App search, files, web search and music recognition"),
            component: "modules/settings/SearchConfig.qml"
        },
        {
            key: "ai", group: "system", color: "#AF52DE", icon: "neurology", hero: false,
            name: Translation.tr("AI"),
            description: Translation.tr("Models, API connections, chat and desktop assistant"),
            component: "modules/settings/AiConfig.qml"
        },
        {
            key: "tools", group: "system", color: "#FFB800", icon: "screenshot_region", hero: false,
            name: Translation.tr("Screenshots & Tools"),
            description: Translation.tr("Screenshots, screen recording, selection and overlay widgets"),
            component: "modules/settings/ToolsConfig.qml"
        },
        {
            key: "advanced", group: "system", color: "#8E8E93", icon: "code", hero: false,
            name: Translation.tr("Advanced"),
            description: Translation.tr("Config files, work safety, translation and polling"),
            component: "modules/settings/AdvancedConfig.qml"
        },
        {
            key: "about", group: "system", parentKey: "general", color: "#8E8E93", icon: "info", hidden: true, hero: false,
            name: Translation.tr("About"),
            description: Translation.tr("Velora, this computer and project resources"),
            component: "modules/settings/About.qml"
        },
        // Opened from General (`parentKey`), which stays highlighted in the sidebar meanwhile
        {
            key: "updates", group: "system", parentKey: "general", color: "#8E8E93", icon: "system_update", hidden: true, hero: false,
            name: Translation.tr("Software Update"),
            description: Translation.tr("New Velora versions from GitHub"),
            component: "modules/settings/UpdatesConfig.qml"
        },
        {
            key: "storage", group: "system", parentKey: "general", color: "#8E8E93", icon: "hard_drive", hidden: true, hero: false,
            name: Translation.tr("Storage"),
            description: Translation.tr("How full your disks are"),
            component: "modules/settings/StorageConfig.qml"
        },
        {
            key: "datetime", group: "system", parentKey: "general", color: "#0A84FF", icon: "schedule", hidden: true, hero: false,
            name: Translation.tr("Date & Time"),
            description: Translation.tr("How the clock and dates look, the time zone and setting the time automatically"),
            component: "modules/settings/DateTimeConfig.qml"
        },
        {
            key: "language", group: "system", parentKey: "general", color: "#0A84FF", icon: "language", hidden: true, hero: false,
            name: Translation.tr("Language & Region"),
            description: Translation.tr("The language of the shell"),
            component: "modules/settings/LanguageConfig.qml"
        }
    ]
    property int currentPage: Math.max(0, root.pageIndex(pageStateFile.text().trim())) // Last opened page
    property int pageDirection: 1
    property bool initialized: false
    readonly property bool windowUsable: root.visible && root.visibility !== Window.Minimized
    // A finite, event-driven warmup. Only one unfinished page owns the construction slot;
    // navigation can take it back, but never forces synchronous incubation.
    property bool backgroundPreload: false
    property int settledPages: 0
    property Item loadingPage: null
    readonly property bool preloading: root.settledPages < root.pages.length
    readonly property bool searching: sidebar.searchText.trim().length > 0
    readonly property var currentPageData: root.pages[root.currentPage]
    // A page may be built after the initial navigation bindings have evaluated.
    property Item currentPageLoader: null
    readonly property Item currentPageItem: root.currentPageLoader?.item ?? null
    onCurrentPageChanged: {
        root.cancelNavigation();
        currentPageLoader = pageRepeater.itemAt(root.currentPage);
        loadingIndicator.restartDelay();
        Qt.callLater(root.loadNextPage);
    }
    onWindowUsableChanged: {
        // Cancel incubation before the next frame can finish a hidden page.
        if (!root.windowUsable) root.loadNextPage();
        else Qt.callLater(root.loadNextPage);
    }
    onSearchingChanged: {
        root.cancelNavigation();
        if (root.searching) searchView.scheduleRefresh();
    }

    function loadNextPage() {
        if (!root.initialized) return;
        nextPageTimer.stop();
        if (!Config.ready || !root.windowUsable) {
            warmupDelay.stop();
            if (root.loadingPage) {
                const unfinished = root.loadingPage;
                root.loadingPage = null;
                unfinished.active = false;
            }
            return;
        }
        const selected = root.currentPageLoader;
        if (!selected) return;
        if (selected.status === Loader.Null) {
            if (root.loadingPage && root.loadingPage !== selected) {
                const unfinished = root.loadingPage;
                root.loadingPage = null;
                unfinished.active = false;
            }
            root.loadingPage = selected;
            selected.load();
            return;
        }
        if (root.loadingPage) return;
        if (!root.backgroundPreload) {
            if (!warmupDelay.running) warmupDelay.start();
            return;
        }
        // Visible sidebar entries first; nested editors are useful to search but less urgent.
        for (const hidden of [false, true]) {
            for (let i = 0; i < root.pages.length; i++) {
                const loader = pageRepeater.itemAt(i);
                if (!!root.pages[i].hidden !== hidden || !loader || loader.status !== Loader.Null) continue;
                root.loadingPage = loader;
                loader.load();
                return;
            }
        }
    }

    function pageFinished(loader) {
        if (root.loadingPage === loader) root.loadingPage = null;
        let settled = 0;
        for (let i = 0; i < root.pages.length; i++) {
            const status = pageRepeater.itemAt(i)?.status;
            if (status === Loader.Ready || status === Loader.Error) settled++;
        }
        root.settledPages = settled;
        if (loader === root.currentPageLoader) {
            if (loader.status === Loader.Ready) {
                Qt.callLater(root.applyPendingNavigation);
                if (revealTimer.pageIndex === root.currentPage) revealTimer.restart();
            } else root.cancelNavigation();
        }
        if (root.searching) searchView.scheduleRefresh();
        if (root.windowUsable && root.preloading) nextPageTimer.restart();
    }

    Connections {
        target: Config
        function onReadyChanged() { Qt.callLater(root.loadNextPage); }
    }

    property var pendingNavigation: null
    function cancelNavigation() {
        root.pendingNavigation = null;
        revealTimer.stop();
        revealTimer.pageIndex = -1;
        revealTimer.target = null;
        revealCheckTimer.stop();
        root.currentPageItem?.cancelReveal();
    }
    function applyPendingNavigation() {
        const request = root.pendingNavigation;
        if (!request || request.pageIndex !== root.currentPage || !root.currentPageItem) return;
        root.pendingNavigation = null;
        root.currentPageItem.navigateToSection?.(request.sectionKey);
    }

    readonly property var breadcrumbs: {
        if (root.searching) return [{title: Translation.tr("Search"), pageIndex: -1}];
        const path = [];
        let current = root.currentPageData;
        while (current && !path.some(entry => entry.pageIndex === root.pageIndex(current.key))) {
            path.unshift({title: current.name, pageIndex: root.pageIndex(current.key)});
            current = current.parentKey ? root.pages[root.pageIndex(current.parentKey)] : null;
        }
        const page = root.currentPageItem;
        for (const section of page?.navigationTrail ?? [])
            path.push({title: section.title, pageIndex: root.currentPage, sectionKey: section.key});
        return path;
    }

    function followBreadcrumb(entry) {
        if (entry.pageIndex < 0) return;
        root.setPage(entry.pageIndex);
        root.pendingNavigation = {pageIndex: entry.pageIndex, sectionKey: entry.sectionKey ?? ""};
        root.applyPendingNavigation();
    }

    // Back / forward history
    property var history: [root.currentPage]
    property int historyIndex: 0
    readonly property bool canGoBack: !!root.currentPageItem?.canNavigateBack || root.historyIndex > 0 || !!root.currentPageData?.parentKey
    readonly property bool canGoForward: root.historyIndex < root.history.length - 1

    // Keys of pages that were merged into others still lead somewhere
    readonly property var pageAliases: ({ "barLayout": "bar", "shortcuts": "keyboard" })

    function pageIndex(key) {
        const wanted = root.pageAliases[key] ?? key;
        return root.pages.findIndex(page => page.key === wanted);
    }

    function showPage(index) {
        root.cancelNavigation();
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
        root.cancelNavigation();
        const page = root.currentPageItem;
        if (page?.canNavigateBack) { page.navigateBack(); return; }
        if (root.historyIndex <= 0) {
            const parentIndex = root.pageIndex(root.currentPageData?.parentKey);
            if (parentIndex >= 0) {
                root.history = [parentIndex, ...root.history];
                root.showPage(parentIndex);
            }
            return;
        }
        root.historyIndex--;
        root.showPage(root.history[root.historyIndex]);
    }

    function goForward() {
        if (!root.canGoForward) return;
        root.historyIndex++;
        root.showPage(root.history[root.historyIndex]);
    }

    Connections {
        target: Network
        function onOpenEditor() {
            root.openPage("connection-editor");
        }
    }
    Connections {
        target: BluetoothManager
        function onOpenDevicePage() {
            root.openPage("bluetooth-device");
        }
    }

    // Opens a page and reveals a section by stable objectName or its displayed title.
    function openPage(key, sectionTitle) {
        if (key === "wallpaper" && sectionTitle) {
            const moved = ["Wallpaper sources", "Choosing wallpapers", "Wallpaper of the day", "Online sources"]
                .find(title => title === sectionTitle || Translation.tr(title) === sectionTitle);
            if (sectionTitle === "sources" || moved) {
                key = "advanced";
                sectionTitle = moved && moved !== "Wallpaper sources" ? Translation.tr(moved) : "sources";
            } else if (["Live wallpaper", "Animated wallpaper"].some(title => title === sectionTitle || Translation.tr(title) === sectionTitle))
                sectionTitle = "live";
        }
        const index = root.pageIndex(key);
        if (index < 0) return;
        root.setPage(index);
        if (key === "shortcuts") {
            root.currentPageItem?.clearShortcutFilters();
            root.pendingNavigation = {pageIndex: index, sectionKey: "shortcuts"};
            root.applyPendingNavigation();
        }
        if (sectionTitle && sectionTitle.length > 0) {
            revealTimer.pageIndex = index;
            revealTimer.target = null;
            revealTimer.sectionTitle = sectionTitle;
            revealTimer.attemptsRemaining = 25;
            revealTimer.restart();
        }
    }

    function pageItemAt(index) {
        return pageRepeater.itemAt(index)?.item ?? null;
    }

    // A section, or a titled group inside one, with this title
    function findSection(node, title) {
        if (!node) return null;
        if ((node.settingsSection || node.settingsSearchable) && (node.objectName === title || node.title === title)) return node;
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
        property int attemptsRemaining: 25
        interval: 160
        onTriggered: {
            if (pageIndex !== root.currentPage || root.searching) return;
            const page = root.pageItemAt(pageIndex);
            // Loading time is not a reveal retry: pageFinished wakes this when incubation ends.
            if (!page) return;
            const item = target ?? (page ? root.findSection(page, sectionTitle) : null);
            if (!page?.revealItem || !item || item.height <= 0) {
                // Config/page construction can finish after the initial timer.
                if (--attemptsRemaining > 0) restart();
                return;
            }
            page.revealItem(item);
            revealCheckTimer.page = page;
            revealCheckTimer.item = item;
            revealCheckTimer.restart();
        }
    }
    Timer {
        id: nextPageTimer
        interval: 32
        onTriggered: root.loadNextPage()
    }
    Timer { // Starts the background building once the window has settled
        id: warmupDelay
        interval: 600
        onTriggered: {
            root.backgroundPreload = true;
            root.loadNextPage();
        }
    }
    Timer { // Corrects the position if the page was still settling
        id: revealCheckTimer
        property var page: null
        property var item: null
        interval: 500
        onTriggered: {
            if (!root.searching && page === root.currentPageItem) page?.revealItem(item, false);
        }
    }
    Connections { // Scrolling by hand cancels the correction
        target: revealCheckTimer.page
        ignoreUnknownSignals: true
        function onRevealCancelled() { revealCheckTimer.stop() }
    }

    visible: true
    onClosing: Qt.quit()
    title: Translation.tr("Velora Settings")

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme()
        Config.readWriteDelay = 0 // Settings app always only sets one var at a time so delay isn't needed
        // Deep links: page key, optional stable section ID, or a search query.
        const startKey = Quickshell.env("QS_SETTINGS_PAGE") || pageStateFile.text().trim();
        if (root.pageIndex(startKey) >= 0)
            root.openPage(startKey, Quickshell.env("QS_SETTINGS_SECTION") ?? "");
        const startSearch = Quickshell.env("QS_SETTINGS_SEARCH") ?? "";
        if (startSearch.length > 0) {
            sidebar.searchText = startSearch;
            sidebar.focusSearch();
        }
        root.initialized = true;
        Qt.callLater(root.loadNextPage);
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
        onActivated: sidebar.focusSearch()
    }
    Shortcut {
        sequence: "Escape"
        onActivated: {
            const focusItem = root.activeFocusItem;
            if (sidebar.searchText.length > 0) sidebar.searchText = "";
            else if (focusItem && focusItem.cursorPosition !== undefined) contentPane.forceActiveFocus(); // Leave the text field first
            else if (root.currentPageItem?.dismissPreview?.()) return;
            else if (root.currentPageItem?.canNavigateBack) root.currentPageItem.navigateBack();
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
            onExpandRequested: expandOverride = true
            onPageSelected: index => root.setPage(index)
            onSearchAccepted: searchView.acceptFirst()
            onSearchTextChanged: {
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
                    objectName: "settingsTitleBar"
                    Layout.fillWidth: true
                    implicitHeight: 54

                    DragHandler {
                        target: null
                        acceptedButtons: Qt.LeftButton
                        onActiveChanged: if (active) root.startSystemMove()
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
                            objectName: "settingsBackButton"
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
                        SettingsBreadcrumbs {
                            id: titleLabel
                            objectName: "settingsBreadcrumbs"
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            Layout.leftMargin: 6
                            entries: root.breadcrumbs
                            onActivated: entry => root.followBreadcrumb(entry)
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
                    clip: true // Translated pages and their input shields must stay below the toolbar.

                    Repeater {
                        id: pageRepeater
                        model: root.pages
                        onItemAdded: (index, item) => {
                            if (index === root.currentPage) root.currentPageLoader = item;
                            Qt.callLater(root.loadNextPage);
                        }
                        onItemRemoved: (index, item) => {
                            if (root.currentPageLoader === item) root.currentPageLoader = null;
                        }
                        delegate: Loader {
                            id: pageLoader
                            required property int index
                            required property var modelData
                            readonly property bool isCurrent: index === root.currentPage && !root.searching
                            readonly property bool showingContent: isCurrent && status === Loader.Ready
                            readonly property bool pageActive: showingContent && root.windowUsable
                            property real slide: 0

                            anchors.fill: parent
                            active: false
                            asynchronous: true
                            // Kept visible (but transparent) so search can tell which options are hidden.
                            // Not disabled either: that restyled every control on both pages at each switch.
                            opacity: 0
                            z: isCurrent ? 1 : 0
                            transform: Translate { x: pageLoader.slide }

                            function load() {
                                if (source.toString().length === 0) {
                                    // Initial properties precede Component.onCompleted, so warming a page
                                    // cannot briefly start Wi-Fi/Bluetooth scans or an AI catalogue refresh.
                                    setSource(modelData.component, {
                                        pageShown: Qt.binding(() => pageLoader.pageActive),
                                        heroIcon: modelData.icon,
                                        heroIconRotation: modelData.iconRotation ?? 0,
                                        heroTitle: modelData.hero === false ? "" : modelData.name,
                                        heroDescription: modelData.description,
                                        heroColor: Qt.binding(() => CF.ColorUtils.mix(modelData.color, Appearance.colors.colPrimary, 0.82))
                                    });
                                }
                                active = true;
                            }
                            function retry() {
                                active = false;
                                source = "";
                                root.settledPages = Math.max(0, root.settledPages - 1);
                                Qt.callLater(root.loadNextPage);
                            }
                            onStatusChanged: {
                                if (status === Loader.Ready || status === Loader.Error) root.pageFinished(pageLoader);
                            }
                            Connections {
                                target: pageLoader.item
                                function onSearchContentChanged() {
                                    if (root.searching) searchView.scheduleRefresh();
                                }
                            }
                            onShowingContentChanged: {
                                if (showingContent) {
                                    exitAnim.stop();
                                    enterAnim.restart();
                                } else {
                                    enterAnim.stop();
                                    if (opacity > 0) exitAnim.restart();
                                    else {
                                        exitAnim.stop();
                                        slide = 0;
                                    }
                                }
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
                                NumberAnimation { target: pageLoader; property: "opacity"; from: 0; to: 1; duration: Appearance.scaledDuration(240); easing.type: Easing.OutCubic }
                                NumberAnimation { target: pageLoader; property: "slide"; from: Math.min(64, pageLoader.width * 0.10) * root.pageDirection; to: 0; duration: Appearance.scaledDuration(360); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel }
                            }
                            ParallelAnimation {
                                id: exitAnim
                                NumberAnimation { target: pageLoader; property: "opacity"; to: 0; duration: Appearance.scaledDuration(150); easing.type: Easing.InCubic }
                                NumberAnimation { target: pageLoader; property: "slide"; to: -28 * root.pageDirection; duration: Appearance.scaledDuration(150); easing.type: Easing.InCubic }
                            }
                        }
                    }

                    MaterialLoadingIndicator {
                        id: loadingIndicator
                        objectName: "settingsPageLoading"
                        anchors.centerIn: parent
                        implicitSize: 32
                        property bool delayElapsed: false
                        readonly property bool waiting: root.windowUsable && !root.searching
                            && root.currentPageLoader?.status !== Loader.Ready && root.currentPageLoader?.status !== Loader.Error
                        visible: waiting && delayElapsed
                        loading: visible
                        function restartDelay() {
                            delayElapsed = false;
                            if (waiting) indicatorDelay.restart();
                            else indicatorDelay.stop();
                        }
                        onWaitingChanged: restartDelay()
                        Timer {
                            id: indicatorDelay
                            interval: 120
                            onTriggered: loadingIndicator.delayElapsed = true
                        }
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        visible: !root.searching && root.currentPageLoader?.status === Loader.Error
                        spacing: 12
                        StyledText { text: Translation.tr("Couldn't load this page") }
                        DialogButton {
                            Layout.alignment: Qt.AlignHCenter
                            buttonText: Translation.tr("Retry")
                            onClicked: root.currentPageLoader.retry()
                        }
                    }

                    SettingsSearch {
                        id: searchView
                        anchors.fill: parent
                        pages: root.pages
                        pageItemAt: index => root.pageItemAt(index)
                        loading: root.preloading
                        enabled: root.searching && root.windowUsable
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
                                revealTimer.sectionTitle = "";
                                revealTimer.attemptsRemaining = 25;
                                revealTimer.restart();
                            }
                        }
                    }
                }
            }
        }
    }
}
