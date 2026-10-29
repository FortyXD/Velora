pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

/**
 * App library: every app in pages of icons over the blurred desktop, like Launchpad. Opens with four
 * fingers toward you or pinched together (following them, services/TouchpadGestures.qml),
 * Super+Shift+Space, or `qs ipc call appLibrary toggle`. Type to search; Enter opens the first app.
 */
Scope {
    id: root

    // 0 hidden … 1 open. A gesture drives it directly; otherwise it animates to where it should be.
    property real progress: 0
    readonly property bool following: TouchpadGestures.libraryProgress >= 0
    readonly property real target: GlobalStates.appLibraryOpen ? 1 : 0

    onFollowingChanged: if (!following) root.settleTo(root.target)
    onTargetChanged: if (!following) root.settleTo(root.target)
    // Set here: a binding on `to` would still hold the previous target when this runs
    function settleTo(value) {
        settle.stop();
        settle.to = value;
        settle.duration = Appearance.scaledDuration(value > 0 ? 420 : 280);
        settle.easing.bezierCurve = value > 0 ? Appearance.animationCurves.emphasizedDecel : Appearance.animationCurves.emphasizedAccel;
        settle.start();
    }
    Connections {
        target: TouchpadGestures
        function onLibraryProgressChanged() {
            if (root.following) {
                settle.stop();
                root.progress = TouchpadGestures.libraryProgress;
            }
        }
    }
    NumberAnimation {
        id: settle
        target: root
        property: "progress"
        easing.type: Easing.BezierSpline
    }

    function launch(entry) {
        GlobalStates.appLibraryOpen = false;
        entry.execute();
    }

    GlobalShortcut {
        name: "appLibraryToggle"
        description: "Shows all apps"
        onPressed: GlobalStates.appLibraryOpen = !GlobalStates.appLibraryOpen
    }
    IpcHandler {
        target: "appLibrary"
        function toggle(): void {
            GlobalStates.appLibraryOpen = !GlobalStates.appLibraryOpen;
        }
        function open(): void {
            GlobalStates.appLibraryOpen = true;
        }
        function close(): void {
            GlobalStates.appLibraryOpen = false;
        }
    }
    // Only one fullscreen thing at a time
    Connections {
        target: GlobalStates
        function onOverviewOpenChanged() {
            if (GlobalStates.overviewOpen) GlobalStates.appLibraryOpen = false;
        }
        function onAppLibraryOpenChanged() {
            if (GlobalStates.appLibraryOpen) GlobalStates.overviewOpen = false;
        }
    }

    // The sections, by freedesktop.org categories
    readonly property var sections: [
        { "name": Translation.tr("All apps"), "icon": "apps", "categories": [] },
        { "name": Translation.tr("Internet"), "icon": "language", "categories": ["Network", "WebBrowser", "Email", "Chat"] },
        { "name": Translation.tr("Office"), "icon": "description", "categories": ["Office", "TextEditor", "Education"] },
        { "name": Translation.tr("Graphics"), "icon": "brush", "categories": ["Graphics", "Photography"] },
        { "name": Translation.tr("Media"), "icon": "play_circle", "categories": ["AudioVideo", "Audio", "Video", "Music"] },
        { "name": Translation.tr("Development"), "icon": "code", "categories": ["Development", "IDE"] },
        { "name": Translation.tr("Games"), "icon": "sports_esports", "categories": ["Game"] },
        { "name": Translation.tr("System"), "icon": "settings", "categories": ["System", "Settings", "Utility", "Monitor"] },
    ]

    // Out at all: then it's shown on the screen it opened on, and stays there
    readonly property bool showing: root.progress > 0.001 || GlobalStates.appLibraryOpen
    property var screen: null
    onShowingChanged: {
        if (!root.showing) return;
        root.screen = Quickshell.screens.find(screen => screen.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0];
        window.capture();
    }

    // Built once and kept: building seventy icons in the middle of a swipe made it stutter
    PanelWindow {
        id: window
        visible: root.showing
        screen: root.screen ?? Quickshell.screens[0]
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:appLibrary"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: GlobalStates.appLibraryOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        readonly property real p: Math.max(0, root.progress)
        readonly property real shown: Math.min(1, p)
        property int section: 0
        property string query: ""
        readonly property var apps: {
            const list = window.query.length > 0 ? AppSearch.fuzzyQuery(window.query)
                : AppSearch.list.filter(entry => !entry.noDisplay).sort((a, b) => a.name.localeCompare(b.name));
            const categories = root.sections[window.section].categories;
            return categories.length === 0 || window.query.length > 0 ? list
                : list.filter(entry => (entry.categories ?? []).some(category => categories.includes(category)));
        }
        onAppsChanged: pages.currentIndex = 0

        // The desktop as it was, blurred more the further the library is out
        function capture() {
            backdrop.captureFrame();
        }
        ScreencopyView {
            id: backdrop
            anchors.fill: parent
            captureSource: window.screen
            live: false
            visible: false
        }
        MultiEffect {
            anchors.fill: parent
            source: backdrop
            visible: backdrop.hasContent
            blurEnabled: true
            blurMax: 64
            blur: window.shown
            brightness: -0.18 * window.shown
            saturation: -0.15 * window.shown
        }
        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colLayer0
            opacity: 0.38 * window.shown
        }

        // A click on empty space closes it
        MouseArea {
            anchors.fill: parent
            onClicked: GlobalStates.appLibraryOpen = false
            onWheel: wheel => pages.flip(wheel.angleDelta.y < 0 || wheel.angleDelta.x < 0 ? 1 : -1)
        }

        Item {
            id: content
            anchors.fill: parent
            opacity: window.shown
            focus: true
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    if (window.query.length > 0) search.text = "";
                    else GlobalStates.appLibraryOpen = false;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (window.apps.length > 0) root.launch(window.apps[0]);
                } else if (event.key === Qt.Key_PageDown || (event.key === Qt.Key_Right && search.text.length === 0)) {
                    pages.flip(1);
                } else if (event.key === Qt.Key_PageUp || (event.key === Qt.Key_Left && search.text.length === 0)) {
                    pages.flip(-1);
                } else if (event.text.length > 0 && !search.activeFocus) {
                    search.forceActiveFocus();
                    search.text += event.text;
                } else {
                    return;
                }
                event.accepted = true;
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: Math.round(window.height * 0.07)
                anchors.bottomMargin: Math.round(window.height * 0.05)
                spacing: 18

                // Search: slides down a little as it appears
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: -16 * (1 - window.shown)
                    implicitWidth: Math.min(520, window.width * 0.5)
                    implicitHeight: 46
                    radius: height / 2
                    color: Appearance.colors.colLayer1
                    border.width: search.activeFocus ? 2 : 1
                    border.color: search.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 10
                        MaterialSymbol {
                            text: "search"
                            iconSize: Appearance.font.pixelSize.huge
                            color: Appearance.colors.colSubtext
                        }
                        TextInput {
                            id: search
                            Layout.fillWidth: true
                            color: Appearance.colors.colOnLayer1
                            font.family: Appearance.font.family.main
                            font.pixelSize: Appearance.font.pixelSize.normal
                            clip: true
                            onTextChanged: window.query = text
                            Keys.forwardTo: [content]
                            StyledText {
                                visible: search.text.length === 0
                                text: Translation.tr("Search apps")
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.normal
                            }
                        }
                    }
                }

                // Sections
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    visible: window.query.length === 0
                    spacing: 6
                    Repeater {
                        model: root.sections
                        delegate: RippleButton {
                            id: chip
                            required property var modelData
                            required property int index
                            toggled: window.section === chip.index
                            implicitHeight: 34
                            implicitWidth: chipRow.implicitWidth + 24
                            buttonRadius: height / 2
                            colBackground: Appearance.colors.colLayer1
                            colBackgroundToggled: Appearance.colors.colSecondaryContainer
                            colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                            onClicked: window.section = chip.index
                            contentItem: RowLayout {
                                id: chipRow
                                spacing: 6
                                MaterialSymbol {
                                    Layout.leftMargin: 12
                                    text: chip.modelData.icon
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: chip.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                }
                                StyledText {
                                    Layout.rightMargin: 12
                                    text: chip.modelData.name
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: chip.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                                }
                            }
                        }
                    }
                }

                // Pages of icons
                ListView {
                    id: pages
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.leftMargin: window.width * 0.08
                    Layout.rightMargin: window.width * 0.08
                    orientation: ListView.Horizontal
                    snapMode: ListView.SnapOneItem
                    highlightRangeMode: ListView.StrictlyEnforceRange
                    highlightMoveDuration: Appearance.scaledDuration(320)
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    readonly property real cell: 128
                    readonly property int columns: Math.max(1, Math.floor(width / cell))
                    readonly property int rows: Math.max(1, Math.floor(height / (cell + 8)))
                    readonly property int perPage: columns * rows
                    function flip(delta) {
                        pages.currentIndex = Math.max(0, Math.min(pages.count - 1, pages.currentIndex + delta));
                    }
                    model: Math.max(1, Math.ceil(window.apps.length / perPage))

                    delegate: Item {
                        id: page
                        required property int index
                        width: pages.width
                        height: pages.height

                        Grid {
                            anchors.centerIn: parent
                            columns: pages.columns
                            Repeater {
                                model: window.apps.slice(page.index * pages.perPage, (page.index + 1) * pages.perPage)
                                delegate: Item {
                                    id: tile
                                    required property var modelData
                                    required property int index
                                    width: pages.cell
                                    height: pages.cell + 8
                                    // Icons gather from the edges toward the middle, ring by ring
                                    readonly property real ring: {
                                        const column = index % pages.columns, row = Math.floor(index / pages.columns);
                                        const dx = (column - (pages.columns - 1) / 2) / Math.max(1, pages.columns / 2);
                                        const dy = (row - (pages.rows - 1) / 2) / Math.max(1, pages.rows / 2);
                                        return Math.min(1, Math.hypot(dx, dy) / 1.2);
                                    }
                                    readonly property real local: Math.max(0, Math.min(1, (window.p - (1 - tile.ring) * 0.3) / 0.7))

                                    opacity: local
                                    scale: 1.16 - 0.16 * local

                                    RippleButton {
                                        id: tileButton
                                        anchors.fill: parent
                                        anchors.margins: 4
                                        buttonRadius: Appearance.rounding.normal
                                        colBackground: "transparent"
                                        onClicked: root.launch(tile.modelData)
                                        altAction: () => {
                                            const appId = tile.modelData.id;
                                            const point = tileButton.mapToItem(null, tileButton.width / 2, tileButton.height / 2);
                                            tileMenu.openAt(tileButton.QsWindow.window, point.x, point.y, [
                                                { "text": Translation.tr("Open"), "icon": "open_in_new", "action": () => root.launch(tile.modelData) },
                                                { "text": TaskbarApps.isPinned(appId) ? Translation.tr("Unpin from the taskbar") : Translation.tr("Pin to the taskbar"),
                                                  "icon": "keep", "action": () => TaskbarApps.togglePin(appId) },
                                            ]);
                                        }
                                        contentItem: ColumnLayout {
                                            spacing: 8
                                            Image {
                                                Layout.alignment: Qt.AlignHCenter
                                                Layout.topMargin: 10
                                                Layout.preferredWidth: 64
                                                Layout.preferredHeight: 64
                                                source: Quickshell.iconPath(tile.modelData.icon, "application-x-executable")
                                                sourceSize.width: 64 * Screen.devicePixelRatio
                                                sourceSize.height: 64 * Screen.devicePixelRatio
                                                fillMode: Image.PreserveAspectFit
                                                asynchronous: true
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                Layout.leftMargin: 6
                                                Layout.rightMargin: 6
                                                text: tile.modelData.name
                                                horizontalAlignment: Text.AlignHCenter
                                                elide: Text.ElideRight
                                                color: Appearance.colors.colOnLayer0
                                                font.pixelSize: Appearance.font.pixelSize.small
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Which page
                Row {
                    Layout.alignment: Qt.AlignHCenter
                    visible: pages.count > 1
                    spacing: 8
                    Repeater {
                        model: pages.count
                        delegate: Rectangle {
                            required property int index
                            width: index === pages.currentIndex ? 22 : 8
                            height: 8
                            radius: 4
                            color: index === pages.currentIndex ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                            Behavior on width {
                                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: pages.currentIndex = parent.index
                            }
                        }
                    }
                }
            }
        }
        ContextMenuPopup {
            id: tileMenu
        }
    }
}
