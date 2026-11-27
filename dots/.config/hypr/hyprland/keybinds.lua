local h = require("hyprland.helpers")
local keymap = require("hyprland.keymap")
local exec = h.exec
local screenshot = [=["${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/$qsConfig/scripts/images/screenshot.sh"]=]

-- Binds with an `id` can be remapped from Settings > Keyboard Shortcuts. Binds with a
-- `description` appear in the cheat sheet (Super+/); binds without one stay hidden.
keymap.begin()

hl.define_submap("global", function()
    local function interrupt_search_release()
        keymap.interrupt_modifiers()
    end
    local function super_aware_bind(modifiers, key, dispatcher, options)
        if not require("hyprland.modifier_taps").kind(key) then
            local original_dispatcher = dispatcher
            dispatcher = function(...)
                keymap.interrupt_modifiers()
                if type(original_dispatcher) == "function" then return original_dispatcher(...) end
                return hl.dispatch(original_dispatcher)
            end
        end
        return h.bind(modifiers, key, dispatcher, options)
    end

    local bind = keymap.binder(super_aware_bind)
    local unbind = keymap.unbinder(h.unbind)

    keymap.group("shell", "Shell", "dashboard")
    bind("Ctrl+Alt", "Escape", exec([=[qs -c $qsConfig ipc call assistant stop]=]), {
        id = "assistant.stop", description = "Stop the desktop assistant",
    })
    bind("", "Super", exec([=[qs -c $qsConfig ipc call search toggle || pkill fuzzel || fuzzel]=]), {
        id = "shell.search", description = "Search apps, files and more",
    })
    bind("Alt", "Shift", function()
        if not tostring(hl.get_config("input:kb_options") or ""):find("grp:", 1, true) then
            hl.dispatch(hl.dsp.exec_cmd("hyprctl switchxkblayout current next"))
        end
    end, { id = "keyboard.layout", description = "Switch keyboard layout" })
    -- Alt+Tab's selection is committed when its trigger modifiers are released.
    local switching_windows = false
    local switch_mod = nil
    local modifier_codes = { [37] = "Ctrl", [105] = "Ctrl", [50] = "Shift", [62] = "Shift",
        [64] = "Alt", [108] = "Alt", [133] = "Super", [134] = "Super" }
    hl.on("input.keyboard.key", function(keycode, _, pressed)
        local commit = switch_mod == nil or modifier_codes[keycode] == switch_mod
        if pressed == 0 and commit and switching_windows then
            switching_windows = false
            hl.dispatch(hl.dsp.global("quickshell:windowSwitcherCommit"))
        end
    end)
    for _, key in ipairs({ "mouse:272", "mouse:273", "mouse:274", "mouse:275", "mouse:276", "mouse:277", "mouse_up", "mouse_down" }) do
        h.bind("", key, interrupt_search_release, { ignore_mods = true, transparent = true, non_consuming = true })
    end

    bind("", "Super_L", hl.dsp.global("quickshell:workspaceNumber"), {
        ignore_mods = true,
        transparent = true,
    })
    bind("", "Super_R", hl.dsp.global("quickshell:workspaceNumber"), {
        ignore_mods = true,
        transparent = true,
    })
    bind("", "Super_L", hl.dsp.global("quickshell:workspaceNumber"), {
        ignore_mods = true,
        release = true,
        transparent = true,
    })
    bind("", "Super_R", hl.dsp.global("quickshell:workspaceNumber"), {
        ignore_mods = true,
        release = true,
        transparent = true,
    })
    bind("Super", "Tab", hl.dsp.global("quickshell:overviewWorkspacesToggle"), { id = "shell.overview", description = "Overview of workspaces and windows" })
    bind("Super", "V", hl.dsp.global("quickshell:overviewClipboardToggle"), { id = "shell.clipboard", description = "Clipboard history" })
    bind("Super", "Period", hl.dsp.global("quickshell:overviewEmojiToggle"), { id = "shell.emoji", description = "Emoji picker" })
    bind("Super", "A", hl.dsp.global("quickshell:sidebarLeftToggle"), { id = "shell.sidebar_left", description = "Left sidebar: assistant and translator" })
    bind("Super", "O", hl.dsp.global("quickshell:sidebarLeftToggle"))
    bind("Super", "N", hl.dsp.global("quickshell:sidebarRightToggle"), { id = "shell.sidebar_right", description = "Right sidebar: quick settings and notifications" })
    bind("Super", "Slash", hl.dsp.global("quickshell:cheatsheetToggle"), { id = "shell.cheatsheet", description = "Keyboard shortcuts cheat sheet" })
    bind("Super", "K", hl.dsp.global("quickshell:oskToggle"), { id = "shell.osk", description = "On-screen keyboard" })
    bind("Super", "M", hl.dsp.global("quickshell:mediaControlsToggle"), { id = "shell.media_controls", description = "Media controls" })
    bind("Super", "G", hl.dsp.global("quickshell:overlayToggle"), { id = "shell.overlay", description = "Overlay widgets" })
    bind("Super", "J", hl.dsp.global("quickshell:barToggle"), { id = "shell.bar", description = "Show or hide the bar" })
    bind("Super+Alt", "J", hl.dsp.global("quickshell:barEditToggle"), { id = "shell.bar_edit", description = "Edit the bar layout" })
    bind("Ctrl+Alt", "Delete", hl.dsp.global("quickshell:sessionToggle"), { id = "shell.session", description = "Session menu" })
    bind("Ctrl+Alt", "Delete", exec([=[qs -c $qsConfig ipc call TEST_ALIVE || pkill wlogout || wlogout -p layer-shell]=]), { id = "shell.session" })
    bind("Ctrl+Super", "T", hl.dsp.global("quickshell:wallpaperSelectorToggle"), { id = "shell.wallpaper", description = "Wallpaper selector" })
    bind("Ctrl+Super", "T", exec([=[qs -c $qsConfig ipc call TEST_ALIVE || ~/.config/quickshell/$qsConfig/scripts/colors/switchwall.sh]=]), { id = "shell.wallpaper" })
    bind("Ctrl+Super+Alt", "T", hl.dsp.global("quickshell:wallpaperSelectorRandom"), { id = "shell.wallpaper_random", description = "Random wallpaper" })
    bind("Super", "I", exec("$settingsApp"), { id = "shell.settings", description = "Settings" })
    bind("Super+Shift", "Space", hl.dsp.global("quickshell:appLibraryToggle"), { id = "shell.app_library", description = "All apps" })
    bind("Ctrl+Super", "R", exec([=["${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/ii/scripts/shell-session" --restart "$qsConfig"]=]), { id = "shell.restart", description = "Restart the shell" })
    bind("Ctrl+Super", "P", hl.dsp.global("quickshell:panelFamilyCycle"), { id = "shell.panel_family", description = "Switch panel style" })
    bind("Shift+Super+Alt", "Slash", exec([=[qs -p ~/.config/quickshell/$qsConfig/onboarding.qml]=]), { id = "shell.setup", description = "Setup assistant" })
    -- Always closes the setup assistant, even if it stopped responding
    bind("Super+Shift", "Escape", exec([=[pkill -f 'quickshell/$qsConfig/onboarding.qml']=]), { id = "shell.setup_close" })

    keymap.group("tools", "Screenshots & tools", "screenshot_region")
    bind("Super+Shift", "S", hl.dsp.global("quickshell:regionScreenshot"), { id = "tools.screenshot_region", description = "Screenshot of a region" })
    bind("Super+Shift", "S", exec([=[qs -c $qsConfig ipc call TEST_ALIVE || pidof slurp || ]=] .. screenshot .. [=[ --select-region]=]), { id = "tools.screenshot_region" })
    bind("", "Print", exec(screenshot .. [=[ --clipboard -o "$(hyprctl activeworkspace -j | jq -r '.monitor')"]=]), {
        id = "tools.screenshot",
        locked = true,
        description = "Screenshot of the screen to clipboard",
    })
    bind("Ctrl", "Print", exec([=[mkdir -p "$(xdg-user-dir PICTURES)/Screenshots" && ]=] .. screenshot .. [=[ -o "$(hyprctl activeworkspace -j | jq -r '.monitor')" "$(xdg-user-dir PICTURES)/Screenshots/Screenshot_$(date '+%Y-%m-%d_%H.%M.%S').png"]=]), {
        id = "tools.screenshot_file",
        locked = true,
        non_consuming = true,
        description = "Screenshot of the screen to clipboard and file",
    })
    bind("Ctrl", "Print", exec(screenshot .. [=[ --clipboard -o "$(hyprctl activeworkspace -j | jq -r '.monitor')"]=]), {
        id = "tools.screenshot_file",
        locked = true,
        non_consuming = true,
    })
    bind("Super+Shift", "R", hl.dsp.global("quickshell:regionRecord"), { id = "tools.record_region", locked = true, description = "Record a region" })
    bind("Super+Shift", "R", exec([=[qs -c $qsConfig ipc call TEST_ALIVE || ~/.config/quickshell/$qsConfig/scripts/videos/record.sh --select-region]=]), { id = "tools.record_region", locked = true })
    bind("Super+Alt", "R", hl.dsp.global("quickshell:regionRecord"), { locked = true })
    bind("Super+Alt", "R", exec([=[qs -c $qsConfig ipc call TEST_ALIVE || ~/.config/quickshell/$qsConfig/scripts/videos/record.sh --select-region]=]), { locked = true })
    bind("Ctrl+Alt", "R", exec([=[qs -c $qsConfig ipc call recorder screenSilent || ~/.config/quickshell/$qsConfig/scripts/videos/record.sh --fullscreen --silent]=]), { locked = true })
    bind("Super+Shift+Alt", "R", exec([=[qs -c $qsConfig ipc call recorder screenWithSound || ~/.config/quickshell/$qsConfig/scripts/videos/record.sh --fullscreen --sound]=]), {
        id = "tools.record_screen",
        locked = true,
        description = "Record the screen with sound",
    })
    bind("Ctrl+Super+Alt", "R", exec([=[qs -c $qsConfig ipc call recorder screenWithMic || ~/.config/quickshell/$qsConfig/scripts/videos/record.sh --fullscreen --mic]=]), {
        locked = true,
        description = "Record the screen with system sound and microphone",
    })
    bind("Super+Shift", "A", hl.dsp.global("quickshell:regionSearch"), { id = "tools.lens", description = "Search a region with Google Lens" })
    bind("Super+Shift", "A", exec([=[qs -c $qsConfig ipc call TEST_ALIVE || pidof slurp || ~/.config/hypr/hyprland/scripts/snip_to_search.sh]=]), { id = "tools.lens" })
    bind("Super+Shift", "X", hl.dsp.global("quickshell:regionOcr"), { id = "tools.ocr", description = "Copy text from a region" })
    bind("Super+Shift", "X", exec([=[qs -c $qsConfig ipc call TEST_ALIVE || pidof slurp || ~/.config/hypr/hyprland/scripts/region_ocr.sh]=]), { id = "tools.ocr" })
    bind("Super+Shift", "T", hl.dsp.global("quickshell:screenTranslate"), { id = "tools.translate", description = "Translate text on screen" })
    bind("Super+Shift", "C", exec([=[~/.config/quickshell/$qsConfig/scripts/helper pick-color]=]), { id = "tools.color_picker", description = "Pick a color" })
    bind("Super+Shift", "I", exec([=[~/.config/quickshell/$qsConfig/scripts/helper toolbox-open]=]), { id = "tools.toolbox", description = "Open the toolbox" })
    bind("Super+Shift+Alt", "mouse:273", exec([=[~/.config/hypr/hyprland/scripts/ai/primary-buffer-query.sh]=]), {
        description = "Summarize selected text with AI",
    })
    -- Fallbacks for when the shell isn't running
    bind("Super", "V", exec([=[qs -c $qsConfig ipc call TEST_ALIVE || pkill fuzzel || cliphist list | fuzzel --match-mode fzf --dmenu | cliphist decode | wl-copy]=]), { id = "shell.clipboard" })
    bind("Super", "Period", exec([=[qs -c $qsConfig ipc call TEST_ALIVE || pkill fuzzel || ~/.config/quickshell/$qsConfig/scripts/helper emoji copy]=]), { id = "shell.emoji" })

    keymap.group("windows", "Window management", "select_window")
    -- Free windows (Settings → Desktop → Windows) snap with Super+arrows instead of moving focus
    local mode = require("hyprland.window_mode").current()
    local free = mode ~= "tiling" and require("hyprland.modes.floating") or nil
    if mode == "canvas" then
        local function camera(action)
            return function()
                local plugin = hl.plugin.velora
                if plugin and plugin.camera then plugin.camera(action) end
            end
        end
        bind("Super", "Home", camera("fit"), { id = "canvas.fit", description = "Fit all windows on the canvas" })
        bind("Super", "End", camera("reset"), { id = "canvas.reset", description = "Return canvas zoom to 100%" })
    end
    bind("Super", "Q", hl.dsp.window.close(), { id = "window.close", description = "Close window" })
    bind("Alt", "F4", hl.dsp.window.close())
    bind("Super+Shift+Alt", "Q", exec([=[hyprctl kill]=]), { id = "window.kill", description = "Force quit an app (click its window)" })
    bind("Super+Alt", "Space", mode == "floating" and free.toggle_float or hl.dsp.window.float(), { id = "window.float", description = free and "Tile or free window" or "Float or tile window" })
    bind("Alt", "Tab", function()
        switching_windows = true
        switch_mod = keymap.current_mods("window.switch_next")[1]
        hl.dispatch(hl.dsp.global("quickshell:windowSwitcherNext"))
        if keymap.is_modifier_tap("window.switch_next") then
            switching_windows = false
            hl.dispatch(hl.dsp.global("quickshell:windowSwitcherCommit"))
        end
    end, { id = "window.switch_next", description = "Switch between windows", repeating = true })
    bind("Alt+Shift", "Tab", function()
        switching_windows = true
        switch_mod = keymap.current_mods("window.switch_previous")[1]
        hl.dispatch(hl.dsp.global("quickshell:windowSwitcherPrevious"))
        if keymap.is_modifier_tap("window.switch_previous") then
            switching_windows = false
            hl.dispatch(hl.dsp.global("quickshell:windowSwitcherCommit"))
        end
    end, { id = "window.switch_previous", description = "Switch between windows, backwards", repeating = true })
    -- Alt+Esc while switching: back out; the rest of the time the keys reach the app
    bind("Alt", "Escape", function()
        if switching_windows then
            switching_windows = false
            hl.dispatch(hl.dsp.global("quickshell:windowSwitcherCancel"))
        end
    end, { non_consuming = true })
    if free then
        h.bind("", "mouse:272", free.press, { ignore_mods = true, transparent = true, non_consuming = true })
        h.bind("", "mouse:272", free.release, { ignore_mods = true, transparent = true, non_consuming = true, release = true })
        bind("Super", "Up", free.up, { id = "window.free_up", description = "Maximize, or snap to the top quarter" })
        bind("Super", "Down", free.down, { id = "window.free_down", description = "Restore, snap to the bottom quarter or minimize" })
        bind("Super", "Left", free.left, { id = "window.snap_left", description = "Snap to the left half" })
        bind("Super", "Right", free.right, { id = "window.snap_right", description = "Snap to the right half" })
        bind("Super", "D", free.show_desktop, { id = "window.show_desktop", description = "Show the desktop" })
        bind("Super", "Z", hl.dsp.global("quickshell:snapLayoutsToggle"), { id = "window.snap_layouts", description = "Snap layouts" })
        bind("Alt", "Space", hl.dsp.global("quickshell:windowMenuToggle"), { id = "window.menu", description = "Window menu" })
        bind("Super+Shift", "Left", hl.dsp.window.move({ monitor = "l" }), { id = "window.monitor_left", description = "Move window to the monitor on the left" })
        bind("Super+Shift", "Right", hl.dsp.window.move({ monitor = "r" }), { id = "window.monitor_right", description = "Move window to the monitor on the right" })
    else
        bind("Super", "D", hl.dsp.window.fullscreen({ mode = "maximized" }), { id = "window.maximize", description = "Maximize window" })
    end
    bind("Super", "F", hl.dsp.window.fullscreen({ mode = "fullscreen" }), { id = "window.fullscreen", description = "Fullscreen" })
    bind("Super+Alt", "F", hl.dsp.window.fullscreen_state({ internal = 0, client = 3 }), { id = "window.fullscreen_spoof", description = "Fullscreen inside the window only" })
    bind("Super", "P", hl.dsp.window.pin(), { id = "window.pin", description = "Pin window on all workspaces" })
    bind("Super", "mouse:272", hl.dsp.window.drag(), { mouse = true, id = "window.drag", description = "Drag to move window" })
    bind("Super", "mouse:274", hl.dsp.window.drag(), { mouse = true })
    bind("Super", "mouse:273", hl.dsp.window.resize(), { mouse = true, id = "window.drag_resize", description = "Drag to resize window" })
    if not free then
        bind("Super", "Left", hl.dsp.focus({ direction = "l" }), { id = "window.focus_left", description = "Focus window left" })
        bind("Super", "Right", hl.dsp.focus({ direction = "r" }), { id = "window.focus_right", description = "Focus window right" })
        bind("Super", "Up", hl.dsp.focus({ direction = "u" }), { id = "window.focus_up", description = "Focus window up" })
        bind("Super", "Down", hl.dsp.focus({ direction = "d" }), { id = "window.focus_down", description = "Focus window down" })
    end
    bind("Super", "BracketLeft", hl.dsp.focus({ direction = "l" }))
    bind("Super", "BracketRight", hl.dsp.focus({ direction = "r" }))
    if not free then
        bind("Super+Shift", "Left", hl.dsp.window.move({ direction = "l" }), { id = "window.move_left", description = "Move window left" })
        bind("Super+Shift", "Right", hl.dsp.window.move({ direction = "r" }), { id = "window.move_right", description = "Move window right" })
        bind("Super+Shift", "Up", hl.dsp.window.move({ direction = "u" }), { id = "window.move_up", description = "Move window up" })
        bind("Super+Shift", "Down", hl.dsp.window.move({ direction = "d" }), { id = "window.move_down", description = "Move window down" })
    end
    bind("Super", "Semicolon", hl.dsp.layout("splitratio -0.1"), { repeating = true })
    bind("Super", "Apostrophe", hl.dsp.layout("splitratio +0.1"), { repeating = true })
    bind("Ctrl+Super", "Backslash", hl.dsp.window.resize({ x = 640, y = 480 }))

    keymap.group("workspaces", "Workspace switching", "space_dashboard")

    -- Workspace numbers use raw keycodes so they work in any keyboard layout
    local number_keycodes = { 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }
    local keypad_keycodes = { 87, 88, 89, 83, 84, 85, 79, 80, 81, 90 }
    for workspace, keycode in ipairs(number_keycodes) do
        bind("Super", "code:" .. keycode, exec("~/.config/quickshell/$qsConfig/scripts/helper workspace workspace " .. workspace), { id = "workspace.go_" .. workspace, description = "Go to workspace " .. workspace })
        bind("Super+Alt", "code:" .. keycode, exec("~/.config/quickshell/$qsConfig/scripts/helper workspace movetoworkspacesilent " .. workspace), { id = "workspace.send_" .. workspace, description = "Send window to workspace " .. workspace })
    end
    for workspace, keycode in ipairs(keypad_keycodes) do
        bind("Super", "code:" .. keycode, exec("~/.config/quickshell/$qsConfig/scripts/helper workspace workspace " .. workspace), {
            dont_inhibit = true,
        })
        bind("Super+Alt", "code:" .. keycode, exec("~/.config/quickshell/$qsConfig/scripts/helper workspace movetoworkspacesilent " .. workspace))
    end

    bind("Ctrl+Super", "S", hl.dsp.workspace.toggle_special(""), { id = "workspace.scratchpad", description = "Show or hide the scratchpad" })
    bind("Super+Alt", "S", hl.dsp.window.move({ workspace = "special", follow = false }), { id = "workspace.scratchpad_send", description = "Send window to the scratchpad" })
    bind("Super", "mouse:275", hl.dsp.workspace.toggle_special(""))

    bind("Super+Shift", "mouse_down", hl.dsp.window.move({ workspace = "r-1", follow = true }))
    bind("Super+Shift", "mouse_up", hl.dsp.window.move({ workspace = "r+1", follow = true }))
    bind("Super+Alt", "mouse_down", hl.dsp.window.move({ workspace = "-1", follow = true }))
    bind("Super+Alt", "mouse_up", hl.dsp.window.move({ workspace = "+1", follow = true }))
    bind("Super+Alt", "Page_Down", hl.dsp.window.move({ workspace = "+1", follow = true }))
    bind("Super+Alt", "Page_Up", hl.dsp.window.move({ workspace = "-1", follow = true }))
    bind("Super+Shift", "Page_Down", hl.dsp.window.move({ workspace = "r+1", follow = true }))
    bind("Super+Shift", "Page_Up", hl.dsp.window.move({ workspace = "r-1", follow = true }))
    bind("Ctrl+Super+Shift", "Right", hl.dsp.window.move({ workspace = "r+1", follow = true }))
    bind("Ctrl+Super+Shift", "Left", hl.dsp.window.move({ workspace = "r-1", follow = true }))
    bind("Ctrl+Super", "Right", hl.dsp.focus({ workspace = "r+1" }), { id = "workspace.right", description = "Workspace to the right" })
    bind("Ctrl+Super", "Left", hl.dsp.focus({ workspace = "r-1" }), { id = "workspace.left", description = "Workspace to the left" })
    bind("Ctrl+Super+Alt", "Right", hl.dsp.focus({ workspace = "m+1" }))
    bind("Ctrl+Super+Alt", "Left", hl.dsp.focus({ workspace = "m-1" }))
    bind("Super", "Page_Down", hl.dsp.focus({ workspace = "+1" }))
    bind("Super", "Page_Up", hl.dsp.focus({ workspace = "-1" }))
    bind("Ctrl+Super", "Page_Down", hl.dsp.focus({ workspace = "r+1" }))
    bind("Ctrl+Super", "Page_Up", hl.dsp.focus({ workspace = "r-1" }))
    bind("Super", "mouse_up", hl.dsp.focus({ workspace = "+1" }), { id = "workspace.next", description = "Go to the next workspace" })
    bind("Super", "mouse_down", hl.dsp.focus({ workspace = "-1" }), { id = "workspace.previous", description = "Go to the previous workspace" })
    bind("Ctrl+Super", "mouse_up", hl.dsp.focus({ workspace = "r+1" }))
    bind("Ctrl+Super", "mouse_down", hl.dsp.focus({ workspace = "r-1" }))
    bind("Ctrl+Super", "BracketLeft", hl.dsp.focus({ workspace = "-1" }))
    bind("Ctrl+Super", "BracketRight", hl.dsp.focus({ workspace = "+1" }))
    bind("Ctrl+Super", "Up", hl.dsp.focus({ workspace = "r-5" }))
    bind("Ctrl+Super", "Down", hl.dsp.focus({ workspace = "r+5" }))

    keymap.group("apps", "Apps", "apps")
    -- Default apps are picked in Settings > Default Apps
    local default_app = "~/.config/quickshell/$qsConfig/scripts/helper apps launch "
    bind("Super", "Return", exec(default_app .. "terminal"), { id = "app.terminal", description = "Open a terminal" })
    bind("Super", "B", exec(default_app .. "browser"), { id = "app.browser", description = "Web browser" })
    bind("Super", "E", exec(default_app .. "files"), { id = "app.files", description = "File manager" })
    bind("Super", "C", exec(default_app .. "code"), { id = "app.code", description = "Code editor" })
    bind("Super", "X", exec(default_app .. "text"), { id = "app.text", description = "Text editor" })
    bind("Super", "T", exec([=[Telegram]=]), { id = "app.telegram", description = "Telegram" })
    bind("Super", "H", exec([=[hiddify]=]), { id = "app.vpn", description = "Hiddify VPN" })
    bind("Super+Shift", "W", exec([=[libreoffice]=]), { id = "app.office", description = "LibreOffice" })
    bind("Ctrl+Super", "V", exec("$volumeMixer"), { id = "app.volume_mixer", description = "Volume mixer" })
    bind("Ctrl+Shift", "Escape", exec("$taskManager"), { id = "app.task_manager", description = "Task manager" })
    bind("Super", "Space", hl.dsp.global("kando:example-menu"), { id = "app.kando", description = "Kando quick menu" })

    keymap.group("media", "Media & sound", "music_note")
    local next_track = [=[playerctl next || playerctl position `bc <<< "100 * $(playerctl metadata mpris:length) / 1000000 / 100"`]=]
    bind("Super+Shift", "P", exec([=[playerctl play-pause]=]), { id = "media.play_pause", locked = true, description = "Play or pause" })
    bind("Super+Shift", "N", exec(next_track), { id = "media.next", locked = true, description = "Next track" })
    bind("Super+Shift", "B", exec([=[playerctl previous]=]), { id = "media.previous", locked = true, description = "Previous track" })
    bind("Super+Shift", "M", exec([=[wpctl set-mute @DEFAULT_SINK@ toggle]=]), { id = "media.mute", locked = true, description = "Mute sound" })
    bind("Super+Alt", "M", exec([=[wpctl set-mute @DEFAULT_SOURCE@ toggle]=]), { id = "media.mic", locked = true, description = "Mute microphone" })
    bind("", "XF86AudioPlay", exec([=[playerctl play-pause]=]), { locked = true })
    bind("", "XF86AudioPause", exec([=[playerctl play-pause]=]), { locked = true })
    bind("", "XF86AudioNext", exec(next_track), { locked = true })
    bind("", "XF86AudioPrev", exec([=[playerctl previous]=]), { locked = true })
    bind("Super+Shift+Alt", "mouse:275", exec([=[playerctl previous]=]))
    bind("Super+Shift+Alt", "mouse:276", exec(next_track))
    bind("", "XF86AudioRaiseVolume", exec([=[wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%+ -l 1.5]=]), {
        locked = true,
        repeating = true,
    })
    bind("", "XF86AudioLowerVolume", exec([=[wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-]=]), {
        locked = true,
        repeating = true,
    })
    bind("", "XF86AudioMute", exec([=[wpctl set-mute @DEFAULT_SINK@ toggle]=]), { locked = true })
    bind("Alt", "XF86AudioMute", exec([=[wpctl set-mute @DEFAULT_SOURCE@ toggle]=]), { locked = true })
    bind("", "XF86AudioMicMute", exec([=[wpctl set-mute @DEFAULT_SOURCE@ toggle]=]), { locked = true })
    bind("", "XF86MonBrightnessUp", exec([=[qs -c $qsConfig ipc call brightness increment || brightnessctl s 5%+]=]), {
        locked = true,
        repeating = true,
    })
    bind("", "XF86MonBrightnessDown", exec([=[qs -c $qsConfig ipc call brightness decrement || brightnessctl s 5%-]=]), {
        locked = true,
        repeating = true,
    })

    keymap.group("session", "Screen & session", "power_settings_new")
    bind("Super", "Equal", exec([=[~/.config/quickshell/$qsConfig/scripts/helper zoom increase 0.3]=]), { id = "screen.zoom_in", repeating = true, description = "Zoom in" })
    bind("Super", "Minus", exec([=[~/.config/quickshell/$qsConfig/scripts/helper zoom decrease 0.3]=]), { id = "screen.zoom_out", repeating = true, description = "Zoom out" })
    bind("Super", "code:86", exec([=[qs -c $qsConfig ipc call zoom zoomIn]=]), { repeating = true })
    bind("Super", "code:82", exec([=[qs -c $qsConfig ipc call zoom zoomOut]=]), { repeating = true })
    bind("Super", "code:86", exec([=[qs -c $qsConfig ipc call TEST_ALIVE || ~/.config/quickshell/$qsConfig/scripts/helper zoom increase 0.1]=]), { repeating = true })
    bind("Super", "code:82", exec([=[qs -c $qsConfig ipc call TEST_ALIVE || ~/.config/quickshell/$qsConfig/scripts/helper zoom decrease 0.1]=]), { repeating = true })
    bind("Super", "L", exec([=[loginctl lock-session]=]), { id = "session.lock", description = "Lock the screen" })
    bind("Super+Shift", "L", exec([=[systemctl suspend || loginctl suspend]=]), {
        id = "session.suspend",
        locked = true,
        description = "Sleep",
    })
    bind("Ctrl+Shift+Alt+Super", "Delete", exec([=[systemctl poweroff || loginctl poweroff]=]), {
        id = "session.shutdown",
        description = "Shut down",
    })

    -- Virtual machine passthrough. The emergency exit stays Super+Alt+F1.
    bind("Super+Alt", "F1", exec([=[notify-send 'Entered Virtual Machine submap' 'Keybinds disabled. Hit Super+Alt+F1 to escape' -a 'Hyprland' && hyprctl dispatch 'hl.dsp.submap("virtual-machine")']=]), {
        id = "session.passthrough", description = "Pass all keys to the focused app (VMs, games)",
    })
    hl.define_submap("virtual-machine", function()
        h.bind("Super+Alt", "F1", exec([=[notify-send 'Exited Virtual Machine submap' 'Keybinds re-enabled' -a 'Hyprland' && hyprctl dispatch 'hl.dsp.submap("global")']=]))
    end)

    -- Testing.
    bind("Super+Alt", "f11", exec([=[bash -c 'RANDOM_IMAGE=$(find ~/Pictures -type f | grep -v -i "nipple" | grep -v -i "pussy" | shuf -n 1); ACTION=$(notify-send "Test notification with body image" "This notification should contain your user account <b>image</b> and <a href=\"https://discord.com/app\">Discord</a> <b>icon</b>. Oh and here is a random image in your Pictures folder: <img src=\"$RANDOM_IMAGE\" alt=\"Testing image\"/>" -a "Hyprland keybind" -p -h "string:image-path:/var/lib/AccountsService/icons/$USER" -t 6000 -i "discord" -A "openImage=Profile image" -A "action2=Open the random image" -A "action3=Useless button"); [[ $ACTION == *openImage ]] && xdg-open "/var/lib/AccountsService/icons/$USER"; [[ $ACTION == *action2 ]] && xdg-open \"$RANDOM_IMAGE\"']=]))
    bind("Super+Alt", "f12", exec([=[bash -c 'RANDOM_IMAGE=$(find ~/Pictures -type f | grep -v -i "nipple" | grep -v -i "pussy" | shuf -n 1); ACTION=$(notify-send "Test notification" "This notification should contain a random image in your <b>Pictures</b> folder and <a href=\"https://discord.com/app\">Discord</a> <b>icon</b>.\n<i>Flick right to dismiss!</i>" -a "Discord (fake)" -p -h "string:image-path:$RANDOM_IMAGE" -t 6000 -i "discord" -A "openImage=Profile image" -A "action2=Useless button"); [[ $ACTION == *openImage ]] && xdg-open "/var/lib/AccountsService/icons/$USER"']=]))
    bind("Super+Alt", "Equal", exec([=[notify-send "Urgent notification" "Ah hell no" -u critical -a 'Hyprland keybind']=]))

    -- Custom keybinds are sourced last, matching the legacy config order,
    -- followed by the shortcuts added in the settings app.
    keymap.group("custom", "Your shortcuts", "star")
    require("custom.keybinds").setup({
        bind = bind,
        unbind = unbind,
        exec = exec,
    })
    keymap.bind_custom(bind)
    keymap.write_manifest()
end)

-- Submap the settings app switches to while it records a new shortcut, so the pressed
-- keys reach it instead of running binds. Hyprland only registers a submap that has a
-- bind, so it keeps the passthrough escape key.
hl.define_submap(keymap.capture_submap, function()
    h.bind("Super+Alt", "F1", hl.dsp.submap("global"))
end)

-- If the settings app goes away mid-recording, give the keybinds back after a while.
local capture_generation = 0
hl.on("keybinds.submap", function()
    if hl.get_current_submap() ~= keymap.capture_submap then
        return
    end
    capture_generation = capture_generation + 1
    local generation = capture_generation
    hl.timer(function()
        if generation == capture_generation and hl.get_current_submap() == keymap.capture_submap then
            hl.dispatch(hl.dsp.submap("global"))
        end
    end, { timeout = 15000, type = "oneshot" })
end)

-- A start event replaces the legacy config-time `hyprctl dispatch submap global`.
-- Dispatching during Lua config parsing crashes Hyprland 0.56.1 verify-config.
hl.on("hyprland.start", function()
    hl.dispatch(hl.dsp.submap("global"))
end)
