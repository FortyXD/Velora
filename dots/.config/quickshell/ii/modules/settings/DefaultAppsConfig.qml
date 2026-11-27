pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.apps

SettingsDetailPage {
    id: root
    readonly property Item popupPane: root
    sectionTitles: ({ formats: Translation.tr("File types"), commands: Translation.tr("Desktop tools") })

    readonly property var dailyRoles: ["browser", "mail", "files", "terminal", "text", "code"]
    readonly property var formatRoles: ["images", "video", "music", "pdf", "documents", "spreadsheets", "presentations", "archives"]
    readonly property var roleInfo: ({
        browser: { example: "https://", color: "#79aafd", icon: "link", action: Translation.tr("Open web links"), title: Translation.tr("Default browser"), description: Translation.tr("Opens web links from messages, emails and documents."), shortcut: "app.browser" },
        mail: { example: "mailto:", color: "#da86b3", icon: "mail", action: Translation.tr("Compose email"), title: Translation.tr("Email application"), description: Translation.tr("Composes a message when you open an email link.") },
        files: { example: "~/", color: "#edb971", icon: "folder_open", action: Translation.tr("Browse folders"), title: Translation.tr("File manager"), description: Translation.tr("Opens folders and shows their contents."), shortcut: "app.files" },
        terminal: { example: ">_", color: "#76bfa6", icon: "terminal", action: Translation.tr("Launch a terminal"), title: Translation.tr("Terminal emulator"), description: Translation.tr("Opens a terminal window, including from the file manager."), shortcut: "app.terminal" },
        text: { example: ".txt", color: "#b49aeb", icon: "edit_note", action: Translation.tr("Edit text files"), title: Translation.tr("Text editor"), description: Translation.tr("Opens plain text files such as notes.txt."), shortcut: "app.text" },
        code: { example: "{ }", color: "#7caed0", icon: "code", action: Translation.tr("Launch the code editor"), title: Translation.tr("Code editor"), description: Translation.tr("Opens your programming editor from its launcher shortcut."), shortcut: "app.code" },
        images: { icon: "image", title: Translation.tr("Images"), description: "JPG · PNG · WebP" },
        video: { icon: "movie", title: Translation.tr("Video"), description: "MP4 · MKV · WebM" },
        music: { icon: "music_note", title: Translation.tr("Music"), description: "MP3 · FLAC · OGG" },
        pdf: { icon: "picture_as_pdf", title: Translation.tr("PDF documents"), description: "PDF" },
        documents: { icon: "description", title: Translation.tr("Documents"), description: "ODT · DOCX · DOC · RTF" },
        spreadsheets: { icon: "table_chart", title: Translation.tr("Spreadsheets"), description: "ODS · XLSX · XLS" },
        presentations: { icon: "slideshow", title: Translation.tr("Presentations"), description: "ODP · PPTX · PPT" },
        archives: { icon: "folder_zip", title: Translation.tr("Archives"), description: "ZIP · 7z · RAR · TAR" }
    })
    property var roles: ({})
    property var apps: []
    property var types: []
    property var webmailServices: []
    property bool loaded: false
    property string catalogueError: ""
    property string assignmentError: ""
    property var failedAssignment: null
    readonly property string errorMessage: [assignmentError, catalogueError].filter(Boolean).join("\n")
    readonly property var sharedNames: {
        const counts = {};
        for (const app of apps) counts[app.name] = (counts[app.name] ?? 0) + 1;
        return counts;
    }
    readonly property var currentNames: {
        const names = {};
        for (const id of [...dailyRoles, ...formatRoles]) {
            const current = roles[id]?.current ?? {};
            names[id] = current.app?.name || current.name || current.command || (current.ask ? Translation.tr("Ask every time") : loaded ? Translation.tr("No app selected") : "…");
        }
        return names;
    }

    function roleSearch(id) {
        const info = roleInfo[id], data = roles[id];
        const examples = formatRoles.includes(id) ? info.description.split(" · ").map(s => "." + s.toLowerCase()) : [];
        return [info.title, info.action, info.description, currentNames[id], ...(data?.mimes ?? []),
            ...(data?.patterns ?? []), ...examples].join(" ");
    }
    function typeSearch(type) {
        return [type.description, type.mime, ...type.patterns, type.app.name].join(" ");
    }
    function matches(searchText) {
        const haystack = searchText.toLowerCase();
        return formatSearch.text.trim().toLowerCase().split(/\s+/).every(term => haystack.includes(term));
    }
    function appDetail(app) {
        if (app.symbol) return "";
        const id = app.id.replace(/\.desktop$/, "");
        if (!app.comment) return id;
        return sharedNames[app.name] > 1 ? app.comment + " · " + id : app.comment;
    }

    // Use one process for reads and writes. Only a successful list response publishes selections.
    property var writes: []
    property var activeJob: null
    property bool needsRead: false
    property bool initialized: false
    function refresh() {
        needsRead = true;
        startNext();
    }
    function write(args) {
        assignmentError = "";
        failedAssignment = null;
        writes = [...writes, args];
        refresh();
    }
    function startNext() {
        if (!initialized || activeJob || (!writes.length && !needsRead)) return;
        if (writes.length) {
            activeJob = writes[0];
            writes = writes.slice(1);
        } else {
            activeJob = ["list", Translation.languageCode];
            needsRead = false;
        }
        worker.command = [Quickshell.shellPath("scripts/helper"), "apps", ...activeJob];
        worker.running = true;
    }
    function readCatalogue(json) {
        const data = JSON.parse(json);
        const byRole = {};
        for (const role of data.roles) byRole[role.id] = role;
        if (!Array.isArray(data.apps) || !Array.isArray(data.types) || !Array.isArray(data.webmail)) throw Error("Invalid catalogue");
        roles = byRole;
        apps = data.apps;
        // Keep search results and focused rows alive when returning to an unchanged catalogue.
        if (JSON.stringify(types) !== JSON.stringify(data.types)) types = data.types;
        webmailServices = data.webmail;
        loaded = true;
        catalogueError = "";
        searchContentChanged();
    }
    Process {
        id: worker
        stdout: StdioCollector { id: output }
        stderr: StdioCollector { id: diagnostic }
        onExited: (code, status) => {
            const reading = root.activeJob?.[0] === "list";
            if (code !== 0 || status !== 0) {
                const message = reading ? Translation.tr("Could not read default applications") : Translation.tr("Could not save the assignment");
                const detail = [message, diagnostic.text.trim()].filter(Boolean).join(" · ");
                if (reading) root.catalogueError = detail;
                else {
                    root.assignmentError = detail;
                    root.failedAssignment = root.activeJob;
                }
            } else if (reading) {
                try { root.readCatalogue(output.text); }
                catch (error) { root.catalogueError = Translation.tr("Could not read default applications"); }
            }
            root.activeJob = null;
            Qt.callLater(root.startNext);
        }
    }
    Component.onCompleted: { initialized = true; refresh(); }
    Connections {
        target: Translation
        function onLanguageCodeChanged() { root.refresh(); }
    }
    onPageShownChanged: {
        if (pageShown) refresh();
        else {
            if (picker?.visible) picker.close();
            formatSearch?.clear();
        }
    }

    function showPicker(role, mime, trigger, inspected = null) {
        picker.inspected = inspected;
        picker.role = role;
        picker.mime = mime;
        picker.trigger = trigger;
        picker.open();
    }
    AppPickerPopup {
        id: picker
        objectName: "defaultAppPicker"
        pane: root.popupPane
        property string role: ""
        property string mime: ""
        property Item trigger
        property var inspected: null
        readonly property var remembered: mime ? (inspected?.mime === mime ? inspected : root.types.find(type => type.mime === mime)) : null
        readonly property var data: root.roles[role]
        readonly property var info: root.roleInfo[role]
        readonly property bool forFormat: root.formatRoles.includes(role)
        sorted: false
        title: inspected ? Translation.tr("Default app") : info?.title ?? remembered?.description ?? mime
        fileName: inspected?.name ?? ""
        description: {
            if (remembered) return Translation.tr("Applies to this file type · %1").arg(remembered.patterns.join("  ") || mime);
            if (forFormat && info) return Translation.tr("Group assignment · %1. The app opens the formats it supports.").arg(info.description);
            return info?.description ?? "";
        }
        currentId: remembered?.app?.id ?? data?.current?.app?.id ?? (remembered?.ask || data?.current?.ask ? "ask" : "")
        readonly property var selectedApp: remembered?.app ?? data?.current?.app
        readonly property var candidates: {
            if (data) return data.candidates ?? [];
            const group = mime ? root.formatRoles.find(id => root.roles[id]?.mimes?.includes(mime)) : null;
            return root.roles[group]?.candidates ?? [];
        }
        readonly property var suggestedIds: new Set([selectedApp?.id, "ask", ...candidates.map(app => app.id)])
        groupForEntry: entry => suggestedIds.has(entry?.id) ? Translation.tr("Current and suggested") : Translation.tr("Installed apps")
        entryDetail: root.appDetail
        entries: {
            if (!visible) return [];
            let list = selectedApp ? [selectedApp] : [];
            if (mime || data?.allowsAsk) list.push({id: "ask", name: mime && !inspected ? Translation.tr("Ask again") : Translation.tr("Ask every time"), symbol: mime && !inspected ? "restart_alt" : "help"});
            const seen = new Set(list.map(app => app.id));
            for (const app of [...candidates, ...root.apps]) {
                if (!seen.has(app.id)) { list.push(app); seen.add(app.id); }
            }
            return list;
        }
        onPicked: entry => {
            if (mime) root.write(entry.id === "ask" ? ["unset-mime", mime] : ["set-mime", entry.id, mime]);
            else root.write(["set", role, entry.id]);
        }
        onClosed: if (root.pageShown) (trigger?.visible ? trigger : formatSearch).forceActiveFocus()
    }

    RowLayout {
        visible: !!root.errorMessage
        Layout.fillWidth: true
        MaterialSymbol { text: "error"; iconSize: 20; color: Appearance.colors.colError }
        StyledText {
            Layout.fillWidth: true
            text: root.errorMessage
            textFormat: Text.PlainText
            wrapMode: Text.WrapAnywhere
            maximumLineCount: 3
            elide: Text.ElideRight
            color: Appearance.colors.colError
        }
        RippleButtonWithIcon {
            objectName: "retryDefaultApps"
            enabled: !root.activeJob && !root.needsRead
            materialIcon: "refresh"
            mainText: Translation.tr("Retry")
            Accessible.name: mainText
            onClicked: {
                if (root.failedAssignment) root.write(root.failedAssignment);
                else root.refresh();
            }
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        SettingsBranch {
            key: "overview"
            page: root
            AppRoleAssignments {
                objectName: "dailyRoleAssignments"
                roles: root.dailyRoles
                info: root.roleInfo
                assignments: root.roles
                currentNames: root.currentNames
                webmailServices: root.webmailServices
                loaded: root.loaded
                pageActive: root.pageShown && root.tab === "overview"
                searchForRole: root.roleSearch
                onAssign: (role, appId) => root.write(["set", role, appId])
                onSaveCommand: (role, value) => root.write(["set-command", role, value])
                onSetWebmail: service => root.write(["set-webmail", service])
                onEnsureVisible: card => {
                    const pane = root.scrollerOf(card);
                    if (!pane || pane.moving) return;
                    const top = card.mapToItem(pane.contentItem, 0, 0).y;
                    const bottom = top + card.height + 8;
                    if (top >= pane.contentY && bottom <= pane.contentY + pane.height) return;
                    const offset = top < pane.contentY || card.height >= pane.height ? top - 8 : bottom - pane.height;
                    const target = Math.max(0, Math.min(offset, pane.contentHeight - pane.height));
                    if (Appearance.animationSpeed > 0) pane.scrollTo(target);
                    else pane.contentY = target;
                }
                onChoose: (role, trigger) => root.showPicker(role, "", trigger)
            }
            ContentSection {
                title: ""
                SettingsBranchLink {
                    branch: formats
                    buttonIcon: "file_copy"
                    detail: Translation.tr("Choose apps by file extension")
                    Accessible.name: title
                    Accessible.description: detail
                }
                SettingsBranchLink {
                    branch: commands
                    buttonIcon: "tune"
                    detail: Translation.tr("Task manager, volume mixer and more")
                    searchText: [title, detail, Translation.tr("Shell commands")].join(" ")
                    Accessible.name: title
                    Accessible.description: detail
                }
            }
        }
        SettingsBranch {
            id: formats
            key: "formats"
            page: root
            GridLayout {
                id: formatToolbar
                Layout.fillWidth: true
                columns: width >= fileButton.implicitWidth + 190 ? 2 : 1
                columnSpacing: 8
                rowSpacing: 6
                AppSearchField {
                    id: formatSearch
                    objectName: "formatSearch"
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    placeholderText: formatToolbar.width < 500 ? Translation.tr("Type or extension") : Translation.tr("Find a file type or extension")
                }
                FileTypeButton {
                    id: fileButton
                    objectName: "inspectLocalFile"
                    pageActive: root.pageShown && root.tab === "formats" && root.loaded && !picker.visible
                    onResolved: type => root.showPicker("", type.mime, fileButton, type)
                }
            }
            StyledText {
                objectName: "fileLookupError"
                Layout.fillWidth: true
                visible: fileButton.failed
                text: Translation.tr("Could not check this file")
                color: Appearance.colors.colError
                font.pixelSize: Appearance.font.pixelSize.small
                wrapMode: Text.Wrap
            }
            ContentSection {
                icon: "file_copy"
                title: Translation.tr("File types")
                visible: root.formatRoles.some(id => root.matches(root.roleSearch(id)))
                Repeater {
                    model: root.formatRoles
                    delegate: ConfigNavRow {
                        id: formatRow
                        required property string modelData
                        readonly property var info: root.roleInfo[modelData]
                        objectName: "format-" + modelData
                        visible: root.matches(searchText)
                        title: info.title
                        description: info.description
                        buttonIcon: info.icon
                        valueText: root.currentNames[modelData]
                        searchText: root.roleSearch(modelData)
                        Accessible.name: title
                        Accessible.description: description + " · " + valueText
                        onClicked: root.showPicker(modelData, "", formatRow)
                    }
                }
            }
            ContentSection {
                icon: "history"
                title: Translation.tr("Remembered choices")
                card: root.types.length > 0
                visible: !formatSearch.text.trim() || root.types.some(type => root.matches(root.typeSearch(type)))
                description: root.types.length ? Translation.tr("Apps picked with “Always use this app” when a file was opened")
                    : Translation.tr("When you open a file of a new type and pick an app with “Always use this app”, it shows up here")
                Repeater {
                    model: root.types
                    delegate: ConfigNavRow {
                        id: typeRow
                        required property var modelData
                        objectName: "mime-" + modelData.mime
                        visible: root.matches(searchText)
                        title: modelData.description
                        description: modelData.patterns.slice(0, 3).join("  ") || modelData.mime
                        valueText: modelData.app.name
                        buttonIcon: "draft"
                        searchText: root.typeSearch(modelData)
                        Accessible.name: title
                        Accessible.description: description + " · " + valueText
                        onClicked: root.showPicker("", modelData.mime, typeRow)
                    }
                }
                ConfigNavRow {
                    objectName: "clearRememberedApps"
                    visible: root.types.length > 0 && !formatSearch.text.trim()
                    buttonIcon: "restart_alt"
                    title: Translation.tr("Ask again for all of these")
                    trailingIcon: ""
                    Accessible.name: title
                    onClicked: root.write(["unset-mime", ...root.types.map(type => type.mime)])
                }
            }
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                visible: !!formatSearch.text.trim() && !root.formatRoles.some(id => root.matches(root.roleSearch(id)))
                    && !root.types.some(type => root.matches(root.typeSearch(type)))
                text: Translation.tr("Nothing found")
                color: Appearance.colors.colSubtext
            }
        }
        SettingsBranch {
            id: commands
            key: "commands"
            page: root
            ShellCommands { choiceWidth: root.width < 570 ? 185 : 280 }
        }
    }
}
