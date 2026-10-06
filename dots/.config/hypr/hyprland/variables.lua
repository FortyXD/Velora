local variables = {
    terminal = [=[~/.config/hypr/hyprland/scripts/launch_first_available.sh "kitty -1" "foot" "alacritty" "wezterm" "konsole" "kgx" "uxterm" "xterm"]=],
    fileManager = "dolphin",
    browser = [=[~/.config/hypr/hyprland/scripts/launch_first_available.sh "google-chrome-stable" "zen-browser" "firefox" "brave" "chromium" "microsoft-edge-stable" "opera" "librewolf"]=],
    codeEditor = [=[~/.config/hypr/hyprland/scripts/launch_first_available.sh "antigravity" "code" "codium" "cursor" "zed" "zedit" "zeditor" "kate" "gnome-text-editor" "emacs" "command -v nvim && kitty -1 nvim" "command -v micro && kitty -1 micro"]=],
    officeSoftware = [=[~/.config/hypr/hyprland/scripts/launch_first_available.sh "wps" "onlyoffice-desktopeditors" "libreoffice"]=],
    textEditor = [=[~/.config/hypr/hyprland/scripts/launch_first_available.sh "kate" "gnome-text-editor" "emacs"]=],
    volumeMixer = [=[~/.config/hypr/hyprland/scripts/launch_first_available.sh "pavucontrol-qt" "pavucontrol"]=],
    taskManager = [=[~/.config/hypr/hyprland/scripts/launch_first_available.sh "gnome-system-monitor" "plasma-systemmonitor --page-name Processes" "command -v btop && kitty -1 fish -c btop"]=],

    qsConfig = "ii",

    dont_load_default_execs = false,
    dont_load_default_general = false,
    dont_load_default_rules = false,
    dont_load_default_colors = false,
    dont_load_default_keybinds = false,
}

variables.settingsApp = [=[XDG_CURRENT_DESKTOP=gnome ~/.config/hypr/hyprland/scripts/launch_first_available.sh "qs -p ~/.config/quickshell/]=]
    .. variables.qsConfig
    .. [=[/settings.qml" "systemsettings" "gnome-control-center" "better-control"]=]

return variables
