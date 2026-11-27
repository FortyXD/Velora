import QtQuick
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentSection {
    id: root
    required property real choiceWidth
    icon: "tune"
    title: Translation.tr("Shell commands")
    description: Translation.tr("Programs started by the shell’s own controls")

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

    // Which preset programs exist, checked once
    property var installedBins: []
    Process {
        running: true
        command: ["sh", "-c", "for c in plasma-systemmonitor gnome-system-monitor missioncenter resources btop htop pavucontrol-qt pavucontrol pwvucontrol kcmshell6 kitty foot alacritty wezterm konsole ghostty kgx pacman yay paru; do command -v $c >/dev/null && echo $c; done"]
        stdout: StdioCollector {
            onStreamFinished: root.installedBins = text.split("\n").filter(line => line.length > 0)
        }
    }

    component AppCommandRow: ConfigComboRow {
        id: commandRow
        required property string appKey
        objectName: "shell-command-" + appKey
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
        maximumWidth: root.choiceWidth
        customLabel: Translation.tr("Custom command…")
        customDescription: Translation.tr("Type any command")
        customPlaceholder: commandRow.value
        customActive: !commandRow.isPreset
        customValue: commandRow.isPreset ? "" : commandRow.value
        customDisplayName: Translation.tr("Custom command")
        onSelected: value => Config.options.apps[commandRow.appKey] = value
        onCustomEntered: text => Config.options.apps[commandRow.appKey] = text
    }

}
