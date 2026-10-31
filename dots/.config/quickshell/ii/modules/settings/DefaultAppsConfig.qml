pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

ContentPage {
    id: root

    readonly property string helper: Quickshell.shellPath("scripts/helper")
    property var roles: ({}) // role id -> { current: { app } | { command, name } | { ask }, candidates, allowsCommand, allowsAsk }
    property var apps: []    // Every app, for "Other apps"
    property var webmailServices: []
    property var types: []   // File types the chooser remembered an app for
    property bool loaded: false

    readonly property var roleInfo: ({
        "browser": { icon: "language", name: Translation.tr("Web browser"), description: Translation.tr("Opens links and web pages"), shortcut: "app.browser" },
        "mail": { icon: "mail", name: Translation.tr("Email"), description: Translation.tr("Opens email links. A browser uses the web mail below.") },
        "files": { icon: "folder", name: Translation.tr("File manager"), description: Translation.tr("Opens folders"), shortcut: "app.files" },
        "terminal": { icon: "terminal", name: Translation.tr("Terminal emulator"), description: Translation.tr("Also used by Dolphin's Open Terminal"), shortcut: "app.terminal" },
        "text": { icon: "edit_note", name: Translation.tr("Text editor"), description: Translation.tr("Opens plain text files"), shortcut: "app.text" },
        "code": { icon: "code", name: Translation.tr("Code editor"), description: Translation.tr("For programming"), shortcut: "app.code" },
        "images": { icon: "image", name: Translation.tr("Images"), description: Translation.tr("PNG, JPEG, WebP and other pictures") },
        "video": { icon: "movie", name: Translation.tr("Video"), description: Translation.tr("MP4, MKV, WebM and other videos") },
        "music": { icon: "music_note", name: Translation.tr("Music"), description: Translation.tr("MP3, FLAC, OGG and other audio") },
        "pdf": { icon: "picture_as_pdf", name: Translation.tr("PDF documents"), description: Translation.tr("Opens PDF files") },
        "documents": { icon: "description", name: Translation.tr("Documents"), description: Translation.tr("ODT, DOCX, DOC and RTF") },
        "spreadsheets": { icon: "table_chart", name: Translation.tr("Spreadsheets"), description: Translation.tr("ODS, XLSX and XLS") },
        "presentations": { icon: "slideshow", name: Translation.tr("Presentations"), description: Translation.tr("ODP, PPTX and PPT") },
        "archives": { icon: "folder_zip", name: Translation.tr("Archives"), description: Translation.tr("ZIP, 7z and TAR open as folders in Dolphin") }
    })

    readonly property string askValue: "__ask__"

    function iconSource(icon) {
        if (!icon) return Quickshell.iconPath("application-x-executable");
        return icon.startsWith("/") ? `file://${icon}` : Quickshell.iconPath(icon, "application-x-executable");
    }

    // Names that more than one app uses ("Files", "Text Editor") also show the desktop id
    readonly property var sharedNames: {
        let counts = {};
        for (const app of root.apps) counts[app.name] = (counts[app.name] ?? 0) + 1;
        return counts;
    }
    function appDescription(app) {
        const id = app.id.replace(/\.desktop$/, "");
        if ((root.sharedNames[app.name] ?? 0) > 1 || !app.comment) return app.comment ? `${app.comment} · ${id}` : id;
        return app.comment;
    }
    function appOption(app, extra) {
        return Object.assign({ displayName: app.name, value: app.id, iconSource: root.iconSource(app.icon),
            description: root.appDescription(app), keywords: app.id }, extra ?? {});
    }

    // Changes run one after another, then the list is read again
    property var queue: []
    function run(args) {
        root.queue = [...root.queue, args];
        if (!actionProc.running) root.runNext();
    }
    function runNext() {
        if (root.queue.length === 0) {
            listProc.running = true;
            return;
        }
        actionProc.command = [root.helper, "apps", ...root.queue[0]];
        root.queue = root.queue.slice(1);
        actionProc.running = true;
    }

    function chooseApp(role, appId) {
        let newRoles = Object.assign({}, root.roles);
        const app = root.apps.find(a => a.id === appId) ?? newRoles[role]?.candidates.find(a => a.id === appId);
        newRoles[role] = Object.assign({}, newRoles[role], { current: appId === "ask" ? { ask: true } : { app: app } });
        root.roles = newRoles;
        root.run(["set", role, appId]);
    }

    function setCommand(role, command) {
        let newRoles = Object.assign({}, root.roles);
        newRoles[role] = Object.assign({}, newRoles[role], { current: { command: command } });
        root.roles = newRoles;
        root.run(["set-command", role, command]);
    }

    Process {
        id: actionProc
        onExited: root.runNext()
    }

    Process {
        id: listProc
        running: true
        command: [root.helper, "apps", "list", Translation.languageCode]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    let roles = {};
                    for (const role of data.roles) roles[role.id] = role;
                    root.roles = roles;
                    root.apps = data.apps;
                    root.webmailServices = data.webmail;
                    root.types = data.types;
                    root.loaded = true;
                } catch (e) {
                    console.warn("[DefaultApps] Couldn't read default apps:", e);
                }
            }
        }
    }

    ContentSection {
        title: Translation.tr("Internet")
        DefaultAppRow { role: "browser" }
        DefaultAppRow { role: "mail" }
        ConfigComboRow {
            readonly property var mail: root.roles["mail"]?.current ?? {}
            visible: !!mail.webmail
            Layout.leftMargin: 38
            icon: "alternate_email"
            text: Translation.tr("Web mail")
            description: Translation.tr("Where email links open in %1").arg(mail.app?.name ?? "")
            currentValue: mail.webmail
            options: root.webmailServices.map(service => ({ displayName: service.name, value: service.id }))
            onSelected: value => {
                let newRoles = Object.assign({}, root.roles);
                newRoles["mail"] = Object.assign({}, newRoles["mail"], { current: Object.assign({}, mail, { webmail: value }) });
                root.roles = newRoles;
                root.run(["set-webmail", value]);
            }
        }
    }

    ContentSection {
        title: Translation.tr("Work")
        description: Translation.tr("The keys next to an app open it. Change them in Keyboard Shortcuts.")
        DefaultAppRow { role: "files" }
        DefaultAppRow { role: "terminal" }
        DefaultAppRow { role: "text" }
        DefaultAppRow { role: "code" }
    }

    ContentSection {
        title: Translation.tr("File types")
        description: Translation.tr("Every app that opens files follows these. Other types ask which app to use the first time.")
        DefaultAppRow { role: "images" }
        DefaultAppRow { role: "video" }
        DefaultAppRow { role: "music" }
        DefaultAppRow { role: "pdf" }
        DefaultAppRow { role: "documents" }
        DefaultAppRow { role: "spreadsheets" }
        DefaultAppRow { role: "presentations" }
        DefaultAppRow { role: "archives" }
    }

    ContentSection {
        title: Translation.tr("Remembered choices")
        description: root.types.length > 0
            ? Translation.tr("Apps picked with “Always use this app” when a file was opened")
            : Translation.tr("When you open a file of a new type and pick an app with “Always use this app”, it shows up here")

        Repeater {
            model: root.types
            delegate: TypeRow {}
        }

        ConfigNavRow {
            visible: root.types.length > 0
            buttonIcon: "restart_alt"
            title: Translation.tr("Ask again for all of these")
            trailingIcon: ""
            onClicked: {
                const mimes = root.types.map(type => type.mime);
                root.types = [];
                root.run(["unset-mime", ...mimes]);
            }
        }
    }

    ContentSection {
        title: Translation.tr("Shell commands")
        description: Translation.tr("What the shell starts from its own buttons, like the volume mixer link or network settings")

        AppCommandRow {
            appKey: "taskManager"
            icon: "monitor_heart"
            text: Translation.tr("Task manager")
            presets: [
                { bin: "plasma-systemmonitor", name: Translation.tr("System Monitor (KDE)"), command: "plasma-systemmonitor --page-name Processes" },
                { bin: "gnome-system-monitor", name: Translation.tr("System Monitor (GNOME)"), command: "gnome-system-monitor" },
                { bin: "missioncenter", name: "Mission Center", command: "missioncenter" },
                { bin: "resources", name: "Resources", command: "resources" },
                { bin: "btop", name: Translation.tr("btop in a terminal"), command: `${terminalRow.runPrefix} btop` },
                { bin: "htop", name: Translation.tr("htop in a terminal"), command: `${terminalRow.runPrefix} htop` }
            ]
        }
        AppCommandRow {
            appKey: "volumeMixer"
            icon: "tune"
            text: Translation.tr("Volume mixer")
            presets: [
                { name: Translation.tr("The first one installed"), command: `~/.config/hypr/hyprland/scripts/launch_first_available.sh "pavucontrol-qt" "pavucontrol"` },
                { bin: "pavucontrol-qt", name: "PulseAudio Volume Control (Qt)", command: "pavucontrol-qt" },
                { bin: "pavucontrol", name: "PulseAudio Volume Control", command: "pavucontrol" },
                { bin: "pwvucontrol", name: "pwvucontrol", command: "pwvucontrol" },
                { bin: "kcmshell6", name: Translation.tr("KDE sound settings"), command: "kcmshell6 kcm_pulseaudio" }
            ]
        }
        AppCommandRow {
            id: terminalRow
            appKey: "terminal"
            icon: "terminal"
            text: Translation.tr("Terminal for shell actions")
            description: Translation.tr("Runs commands from the launcher and terminal apps")
            // `command` is what the shell stores; `run` is put in front of a command to run it in a window
            presets: [
                { bin: "kitty", name: "Kitty", command: "kitty -1", run: "kitty -1 --hold=yes" },
                { bin: "foot", name: "Foot", command: "foot", run: "foot --hold" },
                { bin: "alacritty", name: "Alacritty", command: "alacritty", run: "alacritty --hold -e" },
                { bin: "wezterm", name: "WezTerm", command: "wezterm start", run: "wezterm start --" },
                { bin: "konsole", name: "Konsole", command: "konsole", run: "konsole --hold -e" },
                { bin: "ghostty", name: "Ghostty", command: "ghostty", run: "ghostty -e" },
                { bin: "kgx", name: Translation.tr("Console (GNOME)"), command: "kgx", run: "kgx -e" }
            ]
            readonly property string runPrefix: (terminalRow.presets.find(p => p.command === Config.options.apps.terminal)?.run) ?? `${Config.options.apps.terminal} -e`
        }
        AppCommandRow {
            appKey: "update"
            icon: "system_update_alt"
            text: Translation.tr("System update")
            presets: [
                { bin: "pacman", name: Translation.tr("pacman (official packages)"), command: `${terminalRow.runPrefix} fish -i -c 'pkexec pacman -Syu'` },
                { bin: "yay", name: Translation.tr("yay (packages and AUR)"), command: `${terminalRow.runPrefix} fish -i -c 'yay -Syu'` },
                { bin: "paru", name: Translation.tr("paru (packages and AUR)"), command: `${terminalRow.runPrefix} fish -i -c 'paru -Syu'` }
            ]
        }
    }

    // Which preset programs exist, checked once
    property var installedBins: []
    Process {
        running: true
        command: ["bash", "-c", "for c in plasma-systemmonitor gnome-system-monitor missioncenter resources btop htop pavucontrol-qt pavucontrol pwvucontrol kcmshell6 nm-connection-editor gnome-control-center blueman-manager overskride kitty foot alacritty wezterm konsole ghostty kgx pacman yay paru; do command -v $c >/dev/null && echo $c; done"]
        stdout: StdioCollector {
            onStreamFinished: root.installedBins = text.split("\n").filter(line => line.length > 0)
        }
    }

    component AppCommandRow: ConfigComboRow {
        id: commandRow
        required property string appKey
        property var presets: []
        readonly property string value: Config.options.apps[commandRow.appKey]
        // Installed ones, and the current one even if its program is gone, so it's clear why it does nothing
        readonly property var available: commandRow.presets.filter(preset => !preset.bin || root.installedBins.includes(preset.bin) || preset.command === commandRow.value)
        readonly property bool isPreset: commandRow.presets.some(preset => preset.command === commandRow.value)
        options: commandRow.available.map(preset => ({
            displayName: preset.name,
            value: preset.command,
            icon: !preset.bin || root.installedBins.includes(preset.bin) ? "" : "error",
            description: !preset.bin || root.installedBins.includes(preset.bin) ? preset.command : Translation.tr("Not installed · %1").arg(preset.command)
        }))
        currentValue: commandRow.value
        maximumWidth: 280
        customLabel: Translation.tr("Custom command…")
        customDescription: Translation.tr("Type any command")
        customPlaceholder: commandRow.value
        customActive: !commandRow.isPreset
        customValue: commandRow.isPreset ? "" : commandRow.value
        customDisplayName: Translation.tr("Custom command")
        onSelected: value => Config.options.apps[commandRow.appKey] = value
        onCustomEntered: text => Config.options.apps[commandRow.appKey] = text
    }

    component TypeRow: RowLayout {
        id: typeRow
        required property var modelData
        readonly property bool settingsSearchable: true
        property string searchText: `${typeRow.modelData.description} ${typeRow.modelData.patterns.join(" ")} ${typeRow.modelData.app.name}`
        Layout.fillWidth: true
        Layout.leftMargin: 12
        Layout.rightMargin: 6
        Layout.topMargin: 3
        Layout.bottomMargin: 3
        spacing: 12

        ConfigIconTile {
            icon: "draft"
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            StyledText {
                Layout.fillWidth: true
                text: typeRow.modelData.description
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer2
            }
            StyledText {
                Layout.fillWidth: true
                text: typeRow.modelData.patterns.length > 0 ? typeRow.modelData.patterns.join("  ") : typeRow.modelData.mime
                elide: Text.ElideRight
                font.family: Appearance.font.family.monospace
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
        ChoiceDropdown {
            maximumWidth: 240
            currentValue: typeRow.modelData.app.id
            searchable: true
            options: root.apps.map(app => root.appOption(app))
            displayText: typeRow.modelData.app.name
            displayIconSource: root.iconSource(typeRow.modelData.app.icon)
            onSelected: value => root.run(["set-mime", value, typeRow.modelData.mime])
        }
        RippleButton {
            implicitWidth: 36
            implicitHeight: 36
            buttonRadius: Appearance.rounding.full
            colBackgroundHover: Appearance.colors.colLayer2Hover
            colRipple: Appearance.colors.colLayer2Active
            onClicked: {
                root.types = root.types.filter(type => type.mime !== typeRow.modelData.mime);
                root.run(["unset-mime", typeRow.modelData.mime]);
            }
            contentItem: MaterialSymbol {
                horizontalAlignment: Text.AlignHCenter
                text: "close"
                iconSize: 20
                color: Appearance.colors.colSubtext
            }
            StyledToolTip {
                text: Translation.tr("Ask again")
            }
        }
    }

    component DefaultAppRow: ColumnLayout {
        id: appRow
        required property string role
        readonly property var info: root.roleInfo[appRow.role]
        readonly property var roleData: root.roles[appRow.role] ?? null
        readonly property var current: appRow.roleData?.current ?? {}
        readonly property var shortcut: appRow.info.shortcut ? HyprlandKeybinds.bindMap[appRow.info.shortcut] ?? null : null
        readonly property string currentName: appRow.current.app?.name ?? appRow.current.name
            ?? (appRow.current.command ? Translation.tr("Custom command")
                : appRow.current.ask ? Translation.tr("Ask every time")
                : (root.loaded ? Translation.tr("Not set") : "…"))
        property bool editingCommand: false

        readonly property var options: {
            const candidates = appRow.roleData?.candidates ?? [];
            const ids = candidates.map(app => app.id);
            const others = root.apps.filter(app => !ids.includes(app.id));
            return [
                ...candidates.map(app => root.appOption(app, { section: others.length > 0 ? Translation.tr("Suggested") : "" })),
                ...(appRow.roleData?.allowsAsk ? [{ displayName: Translation.tr("Ask every time"), value: root.askValue, icon: "help",
                    description: Translation.tr("Pick an app each time"), section: Translation.tr("Suggested") }] : []),
                ...others.map(app => root.appOption(app, { more: true, section: Translation.tr("Other apps") }))
            ];
        }

        // Settings search
        readonly property bool settingsSearchable: true
        readonly property string text: appRow.info.name
        readonly property string description: appRow.info.description
        property string searchText: `${appRow.info.name} ${appRow.info.description} ${appRow.currentName}`

        Layout.fillWidth: true
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 6
            Layout.topMargin: 5
            Layout.bottomMargin: 5
            spacing: 12

            ConfigIconTile {
                icon: appRow.info.icon
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1
                StyledText {
                    Layout.fillWidth: true
                    text: appRow.info.name
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    Layout.fillWidth: true
                    text: appRow.current.command ? appRow.current.command : appRow.info.description
                    elide: Text.ElideRight
                    font.family: appRow.current.command ? Appearance.font.family.monospace : Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
            KeyCombo {
                visible: !!appRow.shortcut && !appRow.shortcut.disabled
                mods: appRow.shortcut?.mods ?? []
                key: appRow.shortcut?.key ?? ""
                opacity: 0.75
            }

            ChoiceDropdown {
                maximumWidth: 240
                searchable: true
                options: appRow.options
                moreLabel: Translation.tr("Other apps…")
                currentValue: appRow.current.ask ? root.askValue : appRow.current.app?.id
                customSelected: !!appRow.current.command
                customLabel: appRow.roleData?.allowsCommand ? Translation.tr("Custom command…") : ""
                customDescription: Translation.tr("Run your own launcher")
                displayText: appRow.currentName
                displayIcon: appRow.current.app ? "" : (appRow.current.command ? "terminal" : "help")
                displayIconSource: appRow.current.app ? root.iconSource(appRow.current.app.icon) : ""
                onSelected: value => {
                    appRow.editingCommand = false;
                    root.chooseApp(appRow.role, value === root.askValue ? "ask" : value);
                }
                onCustomRequested: appRow.editingCommand = true
            }
        }

        ConfigTextRow { // Own launcher command, for the terminal and code editor
            visible: appRow.editingCommand
            Layout.leftMargin: 50
            icon: ""
            label: Translation.tr("Command")
            description: Translation.tr("Press Enter to save")
            inline: true
            inlineFieldWidth: 320
            monospace: true
            wrapMode: TextEdit.NoWrap
            placeholderText: "kitty -1"
            value: appRow.current.command ?? ""
            onEditingFinished: {
                if (value.trim().length === 0) return;
                root.setCommand(appRow.role, value.trim());
                appRow.editingCommand = false;
            }
        }
    }
}
