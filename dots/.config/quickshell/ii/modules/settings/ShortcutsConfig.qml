pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.apps
import qs.modules.settings.keyboard

SettingsBranch {
    id: root
    objectName: "shortcutCatalog"
    key: "shortcuts"
    required property KeyboardLayoutMap sourceMap
    required property string capsLabel
    property string filter: ""
    property string groupFilter: ""
    property string selectedCombo: ""
    property string selectedUid: ""
    property string hoveredUid: ""
    readonly property var displayedBind: {
        if (!root.shown || !root.page.pageShown) return null;
        for (const uid of [HyprlandKeybinds.activeRecorder ? "" : hoveredUid, selectedUid]) {
            if (uid && root.matches(uid)) return HyprlandKeybinds.bindMap[uid];
        }
        return HyprlandKeybinds.binds.find(bind => root.matches(HyprlandKeybinds.uid(bind))) ?? null;
    }
    readonly property string displayedUid: displayedBind ? HyprlandKeybinds.uid(displayedBind) : ""
    readonly property var terms: root.normalize(root.filter).split(/[\s+]+/).filter(Boolean)

    function clearFilters() {
        root.hoveredUid = "";
        root.selectedUid = "";
        root.selectedCombo = "";
        root.groupFilter = "";
        root.filter = "";
    }
    function showCombo(bind) {
        root.groupFilter = "";
        root.selectedCombo = KeyUtils.comboKey(bind.mods, bind.key);
        root.filter = KeyUtils.comboText(bind.mods, bind.key);
        root.selectRow(HyprlandKeybinds.uid(bind));
    }
    function selectRow(uid) {
        root.hoveredUid = "";
        root.selectedUid = uid;
    }
    function scrollToStart() {
        const pane = root.page.scrollerOf(editorSection);
        if (pane) {
            pane.stopScroll();
            pane.contentY = pane.originY;
        }
    }
    onFilterChanged: { hoveredUid = ""; scrollToStart(); }
    onGroupFilterChanged: { hoveredUid = ""; scrollToStart(); }
    onShownChanged: if (!shown) hoveredUid = ""

    Connections {
        target: root.ApplicationWindow.window
        ignoreUnknownSignals: true
        function onSearchingChanged() {
            if (root.ApplicationWindow.window.searching) root.clearFilters();
        }
    }
    Connections {
        target: root.page
        function onPageShownChanged() {
            if (!root.page.pageShown && root.shown) {
                root.hoveredUid = "";
                HyprlandKeybinds.activeRecorder?.stop();
            }
        }
    }
    // Repeaters get plain id lists that only change when the set of binds does, so a
    // config reload after each change doesn't rebuild (and re-animate) the whole page
    property var groupIds: []
    property var groupUids: ({})
    function refreshModels() {
        if (root.selectedCombo && root.selectedUid) {
            const selected = HyprlandKeybinds.binds.find(bind => HyprlandKeybinds.uid(bind) === root.selectedUid);
            if (selected && KeyUtils.comboKey(selected.mods, selected.key) !== root.selectedCombo) root.showCombo(selected);
        }
        const ids = HyprlandKeybinds.groups.map(group => group.id);
        if (root.groupFilter && !ids.includes(root.groupFilter)) root.groupFilter = "";
        if (JSON.stringify(ids) !== JSON.stringify(root.groupIds)) root.groupIds = ids;
        let uids = {};
        for (const id of ids) uids[id] = HyprlandKeybinds.bindsInGroup(id).map(bind => HyprlandKeybinds.uid(bind));
        if (JSON.stringify(uids) !== JSON.stringify(root.groupUids)) root.groupUids = uids;
    }
    Connections {
        target: HyprlandKeybinds
        function onBindsChanged() {
            root.refreshModels();
        }
    }
    Component.onCompleted: root.refreshModels()

    // Populate a few rows per frame, including during search. One budget shared by all
    // groups prevents several independent group timers from building hundreds together.
    property int rowBudget: 0
    readonly property int rowCount: root.groupIds.reduce((count, id) => count + (root.groupUids[id]?.length ?? 0), 0)
    function rowOffset(id) {
        let offset = 0;
        for (const group of root.groupIds) {
            if (group === id) break;
            offset += root.groupUids[group]?.length ?? 0;
        }
        return offset;
    }
    Timer {
        interval: 16
        repeat: true
        running: root.rowBudget < root.rowCount && (root.ApplicationWindow.window?.windowUsable ?? root.visible)
        onTriggered: {
            root.rowBudget = Math.min(root.rowBudget + 4, root.rowCount);
            root.page.searchContentChanged();
        }
    }


    function normalize(text) {
        return (text ?? "").toString().toLowerCase().replace(/ё/g, "е");
    }

    function matches(uid) {
        const bind = HyprlandKeybinds.bindMap[uid];
        if (!bind || (root.groupFilter && bind.group !== root.groupFilter)) return false;
        if (root.selectedCombo) return KeyUtils.comboKey(bind.mods, bind.key) === root.selectedCombo;
        if (!root.terms.length) return true;
        const haystack = root.normalize([Translation.tr(bind.description), bind.description, bind.key,
            KeyUtils.comboText(bind.mods, bind.key), KeyUtils.comboLabels(bind.mods, bind.key).join(" ")].join(" "));
        return root.terms.every(term => haystack.includes(term));
    }

    function groupInfo(id) {
        return HyprlandKeybinds.groups.find(group => group.id === id) ?? { id: id, name: id, icon: "keyboard" };
    }

    header: ColumnLayout {
        spacing: 8
        GridLayout {
            Layout.fillWidth: true
            columns: width >= 430 ? 2 : 1
            columnSpacing: 8
            rowSpacing: 6
            AppSearchField {
                id: searchField
                objectName: "shortcutSearch"
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                placeholderText: Translation.tr("Find a shortcut by name or keys")
                text: root.filter
                rightPadding: clear.visible ? 40 : 12
                onTextEdited: {
                    root.selectedCombo = "";
                    root.filter = text;
                }
                SettingsAction {
                    id: clear
                    anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                    width: 32; height: 32
                    visible: root.filter.length > 0
                    text: Translation.tr("Clear search")
                    buttonRadius: height / 2
                    contentItem: MaterialSymbol { text: "close"; iconSize: 18; horizontalAlignment: Text.AlignHCenter }
                    onClicked: {
                        root.selectedCombo = "";
                        root.filter = "";
                        searchField.forceActiveFocus();
                    }
                }
            }
            ChoiceDropdown {
                objectName: "shortcutGroupFilter"
                Layout.maximumWidth: 220
                displayIcon: "filter_list"
                options: [{ displayName: Translation.tr("All groups"), value: "" },
                    ...HyprlandKeybinds.groups.map(group => ({ displayName: Translation.tr(group.name), value: group.id, icon: group.icon }))]
                currentValue: root.groupFilter
                Accessible.name: displayText
                onSelected: value => root.groupFilter = value
            }
        }
        Loader {
            Layout.fillWidth: true
            active: root.shown && root.page.pageShown && !!root.displayedBind && !editor.expanded
            visible: active
            sourceComponent: ShortcutMapPreview {
                bind: root.displayedBind
                keys: root.sourceMap.keys
                capsLabel: root.capsLabel
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8
        Flow {
            Layout.fillWidth: true
            spacing: 6
            SettingsToolButton {
                materialIcon: "add"
                mainText: Translation.tr("Add shortcut")
                readonly property bool settingsSearchable: true
                readonly property string title: mainText
                readonly property string searchText: title + " " + Translation.tr("Launch an app or run a command")
                enabled: !editor.expanded
                onClicked: {
                    root.clearFilters();
                    editor.expanded = true;
                    root.scrollToStart();
                }
            }
            SettingsToolButton {
                materialIcon: "visibility"
                mainText: Translation.tr("Cheat sheet")
                onClicked: Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "cheatsheet", "open"])
            }
            SettingsToolButton {
                objectName: "resetShortcutsButton"
                enabled: HyprlandKeybinds.changedCount > 0
                materialIcon: "restart_alt"
                mainText: Translation.tr("Reset to defaults")
                onClicked: HyprlandKeybinds.resetAll()
                StyledToolTip { text: Translation.tr("Restore the shortcuts shipped with this build. Shortcuts added here will be removed.") }
            }
        }
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
            text: HyprlandKeybinds.applying ? Translation.tr("Applying…") : Translation.tr("Hover over an action to see its keys. Click the action and press a new shortcut.")
        }
    }
    ContentSection {
        id: editorSection
        visible: editor.expanded
        CustomShortcutEditor { id: editor }
    }
    StyledText {
        Layout.fillWidth: true
        visible: !HyprlandKeybinds.binds.some(bind => root.matches(HyprlandKeybinds.uid(bind)))
        text: HyprlandKeybinds.ready ? Translation.tr("No shortcuts match") : Translation.tr("Reading keybinds…")
        horizontalAlignment: Text.AlignHCenter
        color: Appearance.colors.colSubtext
    }

    Repeater {
        model: root.groupIds
        delegate: ContentSection {
            id: groupSection
            required property string modelData
            readonly property var info: root.groupInfo(modelData)
            readonly property var uids: root.groupUids[modelData] ?? []
            readonly property int shownRows: Math.max(0, Math.min(uids.length, root.rowBudget - root.rowOffset(modelData)))
            function appendRows() {
                while (shortcutRows.count < shownRows) shortcutRows.append({shortcutUid: uids[shortcutRows.count]});
            }
            onUidsChanged: {
                shortcutRows.clear();
                appendRows();
            }
            onShownRowsChanged: appendRows()
            Component.onCompleted: appendRows()
            ListModel { id: shortcutRows }
            readonly property bool anyMatch: uids.some(uid => root.matches(uid))
            readonly property bool isCustom: modelData === "custom"

            visible: anyMatch
            icon: info.icon
            title: Translation.tr(info.name)
            description: isCustom ? Translation.tr("Shortcuts you added. Ones defined in custom/keybinds.lua show up here too.") : ""

            Repeater {
                model: shortcutRows
                delegate: ShortcutRow {
                    required property string shortcutUid
                    uid: shortcutUid
                    visible: root.matches(shortcutUid)
                    highlighted: root.displayedUid === uid
                    onPreviewRequested: root.selectRow(uid)
                    onPreviewHovered: over => {
                        if (over && root.shown && !HyprlandKeybinds.activeRecorder) root.hoveredUid = uid;
                        else if (root.hoveredUid === uid) root.hoveredUid = "";
                    }
                }
            }
        }
    }
}
