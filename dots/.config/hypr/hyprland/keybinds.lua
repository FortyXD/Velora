local h = require("hyprland.helpers")
local bind = h.bind
local exec = h.exec

hl.define_submap("global", function()
    -- Shell. These must stay at the top for consistent behavior.
    local search_release_armed = {
        Super_L = false,
        Super_R = false,
    }

    local function arm_search_release(key)
        search_release_armed.Super_L = false
        search_release_armed.Super_R = false
        search_release_armed[key] = true
    end

    local function interrupt_search_release()
        search_release_armed.Super_L = false
        search_release_armed.Super_R = false
    end

    local function toggle_search_on_release(key)
        if not search_release_armed[key] then
            return
        end

        interrupt_search_release()
        hl.dispatch(exec([=[qs -c $qsConfig ipc call search toggle || pkill fuzzel || fuzzel]=]))
    end

    -- A catchall bind only runs when no regular bind matches. Wrap every
    -- configured Super shortcut as well, so Super+2/Super+D/etc. disarm the
    -- standalone-Super action before running their original dispatcher.
    local raw_bind = bind
    local function bind(modifiers, key, dispatcher, options)
        local has_super = modifiers:upper():find("SUPER", 1, true) ~= nil
        local is_super_key = key == "Super_L" or key == "Super_R"

        if has_super and not is_super_key then
            local original_dispatcher = dispatcher
            dispatcher = function(...)
                interrupt_search_release()

                if type(original_dispatcher) == "function" then
                    return original_dispatcher(...)
                end

                return hl.dispatch(original_dispatcher)
            end
        end

        return raw_bind(modifiers, key, dispatcher, options)
    end

    bind("Super", "Super_L", function()
        arm_search_release("Super_L")
    end, {
        ignore_mods = true,
        transparent = true,
        description = "Toggle search",
    })
    bind("Super", "Super_R", function()
        arm_search_release("Super_R")
    end, {
        ignore_mods = true,
        transparent = true,
        description = "Toggle search",
    }) -- [hidden]
    bind("Super", "Super_L", function()
        toggle_search_on_release("Super_L")
    end, {
        ignore_mods = true,
        release = true,
        transparent = true,
    }) -- [hidden]
    bind("Super", "Super_R", function()
        toggle_search_on_release("Super_R")
    end, {
        ignore_mods = true,
        release = true,
        transparent = true,
    }) -- [hidden]
    hl.bind("catchall", interrupt_search_release, {
        transparent = true,
        non_consuming = true,
    }) -- [hidden]
    bind("Ctrl", "Super_L", interrupt_search_release) -- [hidden]
    bind("Ctrl", "Super_R", interrupt_search_release) -- [hidden]
    bind("Super", "mouse:272", interrupt_search_release) -- [hidden]
    bind("Super", "mouse:273", interrupt_search_release) -- [hidden]
    bind("Super", "mouse:274", interrupt_search_release) -- [hidden]
    bind("Super", "mouse:275", interrupt_search_release) -- [hidden]
    bind("Super", "mouse:276", interrupt_search_release) -- [hidden]
    bind("Super", "mouse:277", interrupt_search_release) -- [hidden]
    bind("Super", "mouse_up", interrupt_search_release) -- [hidden]
    bind("Super", "mouse_down", interrupt_search_release) -- [hidden]

    bind("", "Super_L", hl.dsp.global("quickshell:workspaceNumber"), {
        ignore_mods = true,
        transparent = true,
    }) -- [hidden]
    bind("", "Super_R", hl.dsp.global("quickshell:workspaceNumber"), {
        ignore_mods = true,
        transparent = true,
    }) -- [hidden]
    bind("", "Super_L", hl.dsp.global("quickshell:workspaceNumber"), {
        ignore_mods = true,
        release = true,
        transparent = true,
    }) -- [hidden]
    bind("", "Super_R", hl.dsp.global("quickshell:workspaceNumber"), {
        ignore_mods = true,
        release = true,
        transparent = true,
    }) -- [hidden]
    bind("Super", "Tab", hl.dsp.global("quickshell:overviewWorkspacesToggle")) -- Toggle overview
    bind("Super", "V", hl.dsp.global("quickshell:overviewClipboardToggle"), {
        description = "Clipboard history >> clipboard",
    })
    bind("Super", "Period", hl.dsp.global("quickshell:overviewEmojiToggle"), {
        description = "Emoji >> clipboard",
    })
    bind("Super", "A", hl.dsp.global("quickshell:sidebarLeftToggle")) -- Toggle left sidebar
    bind("Super", "O", hl.dsp.global("quickshell:sidebarLeftToggle")) -- [hidden]
    bind("Super", "N", hl.dsp.global("quickshell:sidebarRightToggle"), {
        description = "Toggle right sidebar",
    })
    bind("Super", "Slash", hl.dsp.global("quickshell:cheatsheetToggle"), {
        description = "Toggle cheatsheet",
    })
    bind("Super", "K", hl.dsp.global("quickshell:oskToggle"), {
        description = "Toggle on-screen keyboard",
    })
    bind("Super", "M", hl.dsp.global("quickshell:mediaControlsToggle"), {
        description = "Toggle media controls",
    })
    bind("Super", "G", hl.dsp.global("quickshell:overlayToggle")) -- Toggle overlay
    bind("Ctrl+Alt", "Delete", hl.dsp.global("quickshell:sessionToggle"), {
        description = "Toggle session menu",
    })
    bind("Super", "J", hl.dsp.global("quickshell:barToggle"), {
        description = "Toggle bar",
    })
    bind("Ctrl+Alt", "Delete", exec([=[qs -c $qsConfig ipc call TEST_ALIVE || pkill wlogout || wlogout -p layer-shell]=])) -- [hidden]
    bind("Shift+Super+Alt", "Slash", exec([=[qs -p ~/.config/quickshell/$qsConfig/welcome.qml]=])) -- [hidden]

    bind("", "XF86MonBrightnessUp", exec([=[qs -c $qsConfig ipc call brightness increment || brightnessctl s 5%+]=]), {
        locked = true,
        repeating = true,
    }) -- [hidden]
    bind("", "XF86MonBrightnessDown", exec([=[qs -c $qsConfig ipc call brightness decrement || brightnessctl s 5%-]=]), {
        locked = true,
        repeating = true,
    }) -- [hidden]
    bind("", "XF86AudioRaiseVolume", exec([=[wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%+ -l 1.5]=]), {
        locked = true,
        repeating = true,
    }) -- [hidden]
    bind("", "XF86AudioLowerVolume", exec([=[wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-]=]), {
        locked = true,
        repeating = true,
    }) -- [hidden]

    bind("", "XF86AudioMute", exec([=[wpctl set-mute @DEFAULT_SINK@ toggle]=]), { locked = true }) -- [hidden]
    bind("Super+Shift", "M", exec([=[wpctl set-mute @DEFAULT_SINK@ toggle]=]), {
        locked = true,
        description = "Toggle mute",
    }) -- [hidden]
    bind("Alt", "XF86AudioMute", exec([=[wpctl set-mute @DEFAULT_SOURCE@ toggle]=]), { locked = true }) -- [hidden]
    bind("", "XF86AudioMicMute", exec([=[wpctl set-mute @DEFAULT_SOURCE@ toggle]=]), { locked = true }) -- [hidden]
    bind("Super+Alt", "M", exec([=[wpctl set-mute @DEFAULT_SOURCE@ toggle]=]), {
        locked = true,
        description = "Toggle mic",
    }) -- [hidden]
    bind("Ctrl+Super", "T", hl.dsp.global("quickshell:wallpaperSelectorToggle"), {
        description = "Toggle wallpaper selector",
    })
    bind("Ctrl+Super+Alt", "T", hl.dsp.global("quickshell:wallpaperSelectorRandom"), {
        description = "Select random wallpaper",
    })
    bind("Ctrl+Super", "T", exec([=[qs -c $qsConfig ipc call TEST_ALIVE || ~/.config/quickshell/$qsConfig/scripts/colors/switchwall.sh]=]), {
        description = "Change wallpaper",
    }) -- [hidden]
    bind("Ctrl+Super", "R", exec([=[killall ydotool qs quickshell; qs -c $qsConfig &]=])) -- Restart widgets
    bind("Ctrl+Super", "P", hl.dsp.global("quickshell:panelFamilyCycle")) -- Cycle panel family

    -- Utilities: screenshots, recording, OCR, color picker, clipboard and AI.
    bind("Super", "V", exec([=[qs -c $qsConfig ipc call TEST_ALIVE || pkill fuzzel || cliphist list | fuzzel --match-mode fzf --dmenu | cliphist decode | wl-copy]=]), {
        description = "Copy clipboard history entry",
    }) -- [hidden]
    bind("Super", "Period", exec([=[qs -c $qsConfig ipc call TEST_ALIVE || pkill fuzzel || ~/.config/hypr/hyprland/scripts/fuzzel-emoji.sh copy]=]), {
        description = "Copy an emoji",
    }) -- [hidden]
    bind("Super+Shift", "S", hl.dsp.global("quickshell:regionScreenshot")) -- Screen snip
    bind("Super+Shift", "S", exec([=[qs -c $qsConfig ipc call TEST_ALIVE || pidof slurp || hyprshot --freeze --clipboard-only --mode region --silent]=])) -- [hidden]
    bind("Super+Shift", "A", hl.dsp.global("quickshell:regionSearch")) -- Google Lens
    bind("Super+Shift", "A", exec([=[qs -c $qsConfig ipc call TEST_ALIVE || pidof slurp || ~/.config/hypr/hyprland/scripts/snip_to_search.sh]=])) -- [hidden]
    bind("Super+Shift", "X", hl.dsp.global("quickshell:regionOcr")) -- Character recognition >> clipboard
    bind("Super+Shift", "T", hl.dsp.global("quickshell:screenTranslate")) -- Translate screen content
    bind("Super+Shift", "X", exec([=[qs -c $qsConfig ipc call TEST_ALIVE || pidof slurp || grim -g "$(slurp $SLURP_ARGS)" "/tmp/ocr_image.png" && tesseract "/tmp/ocr_image.png" stdout -l $(tesseract --list-langs | awk 'NR>1{print $1}' | tr '\n' '+' | sed 's/\+$/\n/') | wl-copy && rm "/tmp/ocr_image.png"]=])) -- [hidden]
    bind("Super+Shift", "C", exec([=[hyprpicker -a]=]), {
        description = "Color picker",
    }) -- Pick color (Hex) >> clipboard
    bind("Super+Shift", "R", hl.dsp.global("quickshell:regionRecord"), { locked = true }) -- Record region (no sound)
    bind("Super+Shift", "R", exec([=[qs -c $qsConfig ipc call TEST_ALIVE || ~/.config/quickshell/$qsConfig/scripts/videos/record.sh]=]), { locked = true }) -- [hidden]
    bind("Super+Alt", "R", hl.dsp.global("quickshell:regionRecord"), { locked = true }) -- [hidden]
    bind("Super+Alt", "R", exec([=[qs -c $qsConfig ipc call TEST_ALIVE || ~/.config/quickshell/$qsConfig/scripts/videos/record.sh]=]), { locked = true }) -- [hidden]
    bind("Ctrl+Alt", "R", exec([=[~/.config/quickshell/$qsConfig/scripts/videos/record.sh --fullscreen]=]), { locked = true }) -- [hidden]
    bind("Super+Shift+Alt", "R", exec([=[~/.config/quickshell/$qsConfig/scripts/videos/record.sh --fullscreen --sound]=]), { locked = true }) -- Record screen (with sound)
    bind("", "Print", exec([=[grim -o "$(hyprctl activeworkspace -j | jq -r '.monitor')" - | wl-copy]=]), { locked = true }) -- Screenshot >> clipboard
    bind("Ctrl", "Print", exec([=[mkdir -p $(xdg-user-dir PICTURES)/Screenshots && grim -o "$(hyprctl activeworkspace -j | jq -r '.monitor')" $(xdg-user-dir PICTURES)/Screenshots/Screenshot_"$(date '+%Y-%m-%d_%H.%M.%S')".png]=]), {
        locked = true,
        non_consuming = true,
    }) -- Screenshot >> clipboard & file
    bind("Ctrl", "Print", exec([=[grim -o "$(hyprctl activeworkspace -j | jq -r '.monitor')" - | wl-copy]=]), {
        locked = true,
        non_consuming = true,
    }) -- [hidden]
    bind("Super+Shift+Alt", "mouse:273", exec([=[~/.config/hypr/hyprland/scripts/ai/primary-buffer-query.sh]=]), {
        description = "Generate AI summary for selected text",
    }) -- [hidden]

    -- Window focus and movement.
    bind("Super", "mouse:272", hl.dsp.window.drag(), { mouse = true }) -- Move
    bind("Super", "mouse:274", hl.dsp.window.drag(), { mouse = true }) -- [hidden]
    bind("Super", "mouse:273", hl.dsp.window.resize(), { mouse = true }) -- Resize
    bind("Super", "Left", hl.dsp.focus({ direction = "l" })) -- [hidden]
    bind("Super", "Right", hl.dsp.focus({ direction = "r" })) -- [hidden]
    bind("Super", "Up", hl.dsp.focus({ direction = "u" })) -- [hidden]
    bind("Super", "Down", hl.dsp.focus({ direction = "d" })) -- [hidden]
    bind("Super", "BracketLeft", hl.dsp.focus({ direction = "l" })) -- [hidden]
    bind("Super", "BracketRight", hl.dsp.focus({ direction = "r" })) -- [hidden]
    bind("Super+Shift", "Left", hl.dsp.window.move({ direction = "l" })) -- [hidden]
    bind("Super+Shift", "Right", hl.dsp.window.move({ direction = "r" })) -- [hidden]
    bind("Super+Shift", "Up", hl.dsp.window.move({ direction = "u" })) -- [hidden]
    bind("Super+Shift", "Down", hl.dsp.window.move({ direction = "d" })) -- [hidden]
    bind("Alt", "F4", hl.dsp.window.close()) -- [hidden] Close (Windows)
    bind("Super", "Q", hl.dsp.window.close()) -- Close
    bind("Super+Shift+Alt", "Q", exec([=[hyprctl kill]=])) -- Forcefully zap a window

    bind("Super", "Semicolon", hl.dsp.layout("splitratio -0.1"), { repeating = true }) -- [hidden]
    bind("Super", "Apostrophe", hl.dsp.layout("splitratio +0.1"), { repeating = true }) -- [hidden]
    bind("Super+Alt", "Space", hl.dsp.window.float()) -- Float/Tile
    bind("Super", "D", hl.dsp.window.fullscreen({ mode = "maximized" })) -- Maximize
    bind("Super", "F", hl.dsp.window.fullscreen({ mode = "fullscreen" })) -- Fullscreen
    bind("Super+Alt", "F", hl.dsp.window.fullscreen_state({ internal = 0, client = 3 })) -- Fullscreen spoof
    bind("Super", "P", hl.dsp.window.pin()) -- Pin

    -- Move windows to numbered workspaces using raw keycodes.
    local number_keycodes = { 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }
    for workspace, keycode in ipairs(number_keycodes) do
        bind("Super+Alt", "code:" .. keycode, exec("~/.config/hypr/hyprland/scripts/workspace_action.sh movetoworkspacesilent " .. workspace)) -- [hidden]
    end

    local keypad_keycodes = { 87, 88, 89, 83, 84, 85, 79, 80, 81, 90 }
    for workspace, keycode in ipairs(keypad_keycodes) do
        bind("Super+Alt", "code:" .. keycode, exec("~/.config/hypr/hyprland/scripts/workspace_action.sh movetoworkspacesilent " .. workspace)) -- [hidden]
    end

    bind("Super+Shift", "mouse_down", hl.dsp.window.move({ workspace = "r-1", follow = true })) -- [hidden]
    bind("Super+Shift", "mouse_up", hl.dsp.window.move({ workspace = "r+1", follow = true })) -- [hidden]
    bind("Super+Alt", "mouse_down", hl.dsp.window.move({ workspace = "-1", follow = true })) -- [hidden]
    bind("Super+Alt", "mouse_up", hl.dsp.window.move({ workspace = "+1", follow = true })) -- [hidden]
    bind("Super+Alt", "Page_Down", hl.dsp.window.move({ workspace = "+1", follow = true })) -- [hidden]
    bind("Super+Alt", "Page_Up", hl.dsp.window.move({ workspace = "-1", follow = true })) -- [hidden]
    bind("Super+Shift", "Page_Down", hl.dsp.window.move({ workspace = "r+1", follow = true })) -- [hidden]
    bind("Super+Shift", "Page_Up", hl.dsp.window.move({ workspace = "r-1", follow = true })) -- [hidden]
    bind("Ctrl+Super+Shift", "Right", hl.dsp.window.move({ workspace = "r+1", follow = true })) -- [hidden]
    bind("Ctrl+Super+Shift", "Left", hl.dsp.window.move({ workspace = "r-1", follow = true })) -- [hidden]

    bind("Super+Alt", "S", hl.dsp.window.move({ workspace = "special", follow = false })) -- Send to scratchpad
    bind("Ctrl+Super", "S", hl.dsp.workspace.toggle_special("")) -- [hidden]

    -- Workspace switching.
    for workspace, keycode in ipairs(number_keycodes) do
        bind("Super", "code:" .. keycode, exec("~/.config/hypr/hyprland/scripts/workspace_action.sh workspace " .. workspace)) -- [hidden]
    end

    for workspace, keycode in ipairs(keypad_keycodes) do
        bind("Super", "code:" .. keycode, exec("~/.config/hypr/hyprland/scripts/workspace_action.sh workspace " .. workspace), {
            dont_inhibit = true,
        }) -- [hidden]
    end

    bind("Ctrl+Super", "Right", hl.dsp.focus({ workspace = "r+1" })) -- [hidden]
    bind("Ctrl+Super", "Left", hl.dsp.focus({ workspace = "r-1" })) -- [hidden]
    bind("Ctrl+Super+Alt", "Right", hl.dsp.focus({ workspace = "m+1" })) -- [hidden]
    bind("Ctrl+Super+Alt", "Left", hl.dsp.focus({ workspace = "m-1" })) -- [hidden]
    bind("Super", "Page_Down", hl.dsp.focus({ workspace = "+1" })) -- [hidden]
    bind("Super", "Page_Up", hl.dsp.focus({ workspace = "-1" })) -- [hidden]
    bind("Ctrl+Super", "Page_Down", hl.dsp.focus({ workspace = "r+1" })) -- [hidden]
    bind("Ctrl+Super", "Page_Up", hl.dsp.focus({ workspace = "r-1" })) -- [hidden]
    bind("Super", "mouse_up", hl.dsp.focus({ workspace = "+1" })) -- [hidden]
    bind("Super", "mouse_down", hl.dsp.focus({ workspace = "-1" })) -- [hidden]
    bind("Ctrl+Super", "mouse_up", hl.dsp.focus({ workspace = "r+1" })) -- [hidden]
    bind("Ctrl+Super", "mouse_down", hl.dsp.focus({ workspace = "r-1" })) -- [hidden]

    bind("Super", "S", hl.dsp.workspace.toggle_special("")) -- Toggle scratchpad
    bind("Super", "mouse:275", hl.dsp.workspace.toggle_special("")) -- [hidden]
    bind("Ctrl+Super", "BracketLeft", hl.dsp.focus({ workspace = "-1" })) -- [hidden]
    bind("Ctrl+Super", "BracketRight", hl.dsp.focus({ workspace = "+1" })) -- [hidden]
    bind("Ctrl+Super", "Up", hl.dsp.focus({ workspace = "r-5" })) -- [hidden]
    bind("Ctrl+Super", "Down", hl.dsp.focus({ workspace = "r+5" })) -- [hidden]

    -- Virtual machine passthrough submap.
    bind("Super+Alt", "F1", exec([=[notify-send 'Entered Virtual Machine submap' 'Keybinds disabled. Hit Super+Alt+F1 to escape' -a 'Hyprland' && hyprctl dispatch 'hl.dsp.submap("virtual-machine")']=])) -- Disable keybinds
    hl.define_submap("virtual-machine", function()
        bind("Super+Alt", "F1", exec([=[notify-send 'Exited Virtual Machine submap' 'Keybinds re-enabled' -a 'Hyprland' && hyprctl dispatch 'hl.dsp.submap("global")']=])) -- [hidden]
    end)

    -- Testing.
    bind("Super+Alt", "f11", exec([=[bash -c 'RANDOM_IMAGE=$(find ~/Pictures -type f | grep -v -i "nipple" | grep -v -i "pussy" | shuf -n 1); ACTION=$(notify-send "Test notification with body image" "This notification should contain your user account <b>image</b> and <a href=\"https://discord.com/app\">Discord</a> <b>icon</b>. Oh and here is a random image in your Pictures folder: <img src=\"$RANDOM_IMAGE\" alt=\"Testing image\"/>" -a "Hyprland keybind" -p -h "string:image-path:/var/lib/AccountsService/icons/$USER" -t 6000 -i "discord" -A "openImage=Profile image" -A "action2=Open the random image" -A "action3=Useless button"); [[ $ACTION == *openImage ]] && xdg-open "/var/lib/AccountsService/icons/$USER"; [[ $ACTION == *action2 ]] && xdg-open \"$RANDOM_IMAGE\"']=])) -- [hidden]
    bind("Super+Alt", "f12", exec([=[bash -c 'RANDOM_IMAGE=$(find ~/Pictures -type f | grep -v -i "nipple" | grep -v -i "pussy" | shuf -n 1); ACTION=$(notify-send "Test notification" "This notification should contain a random image in your <b>Pictures</b> folder and <a href=\"https://discord.com/app\">Discord</a> <b>icon</b>.\n<i>Flick right to dismiss!</i>" -a "Discord (fake)" -p -h "string:image-path:$RANDOM_IMAGE" -t 6000 -i "discord" -A "openImage=Profile image" -A "action2=Useless button"); [[ $ACTION == *openImage ]] && xdg-open "/var/lib/AccountsService/icons/$USER"']=])) -- [hidden]
    bind("Super+Alt", "Equal", exec([=[notify-send "Urgent notification" "Ah hell no" -u critical -a 'Hyprland keybind']=])) -- [hidden]

    -- Session.
    bind("Super", "L", exec([=[loginctl lock-session]=]), { description = "Lock" })
    bind("Super+Shift", "L", exec([=[systemctl suspend || loginctl suspend]=]), {
        locked = true,
        description = "Suspend system",
    })
    bind("Ctrl+Shift+Alt+Super", "Delete", exec([=[systemctl poweroff || loginctl poweroff]=]), {
        description = "Shutdown",
    }) -- [hidden]

    -- Screen zoom.
    bind("Super", "Minus", exec([=[~/.config/hypr/hyprland/scripts/zoom.sh decrease 0.3]=]), { repeating = true }) -- Zoom out
    bind("Super", "Equal", exec([=[~/.config/hypr/hyprland/scripts/zoom.sh increase 0.3]=]), { repeating = true }) -- Zoom in
    bind("Super", "code:82", exec([=[qs -c $qsConfig ipc call zoom zoomOut]=]), { repeating = true }) -- [hidden]
    bind("Super", "code:86", exec([=[qs -c $qsConfig ipc call zoom zoomIn]=]), { repeating = true }) -- [hidden]
    bind("Super", "code:82", exec([=[qs -c $qsConfig ipc call TEST_ALIVE || ~/.config/hypr/hyprland/scripts/zoom.sh decrease 0.1]=]), { repeating = true }) -- [hidden]
    bind("Super", "code:86", exec([=[qs -c $qsConfig ipc call TEST_ALIVE || ~/.config/hypr/hyprland/scripts/zoom.sh increase 0.1]=]), { repeating = true }) -- [hidden]

    -- Media.
    local next_track = [=[playerctl next || playerctl position `bc <<< "100 * $(playerctl metadata mpris:length) / 1000000 / 100"`]=]
    bind("Super+Shift", "N", exec(next_track), { locked = true }) -- Next track
    bind("", "XF86AudioNext", exec(next_track), { locked = true }) -- [hidden]
    bind("", "XF86AudioPrev", exec([=[playerctl previous]=]), { locked = true }) -- [hidden]
    bind("Super+Shift+Alt", "mouse:275", exec([=[playerctl previous]=])) -- [hidden]
    bind("Super+Shift+Alt", "mouse:276", exec(next_track)) -- [hidden]
    bind("Super+Shift", "B", exec([=[playerctl previous]=]), { locked = true }) -- Previous track
    bind("Super+Shift", "P", exec([=[playerctl play-pause]=]), { locked = true }) -- Play/pause media
    bind("", "XF86AudioPlay", exec([=[playerctl play-pause]=]), { locked = true }) -- [hidden]
    bind("", "XF86AudioPause", exec([=[playerctl play-pause]=]), { locked = true }) -- [hidden]

    -- Applications.
    bind("Super", "I", exec("$settingsApp")) -- Settings app
    bind("Ctrl+Shift", "Escape", exec("$taskManager")) -- Task manager

    bind("SUPER", "RETURN", exec([=[kitty -- zsh -lc 'tmux new-session']=]))
    bind("Super", "E", exec("$fileManager")) -- File manager
    bind("Super", "B", exec([=[brave]=])) -- Launch Brave
    bind("Super+Shift", "B", exec([=[firefox]=])) -- Launch Firefox
    bind("Super", "C", exec([=[HTTP_PROXY="http://127.0.0.1:12334" HTTPS_PROXY="http://127.0.0.1:12334" NO_PROXY="localhost,127.0.0.1" code]=])) -- Launch Code
    bind("Super", "h", exec([=[hiddify]=])) -- VPN
    bind("Super+Shift", "W", exec([=[libreoffice]=])) -- Launch LibreOffice
    bind("Super", "T", exec([=[Telegram]=])) -- Launch Telegram
    bind("Super", "X", exec([=[~/.config/hypr/hyprland/scripts/launch_first_available.sh "kate" "gnome-text-editor" "emacs"]=])) -- Text editor
    bind("Ctrl+Super", "V", exec("$volumeMixer")) -- Volume mixer
    bind("Ctrl+Shift", "Escape", exec([=[~/.config/hypr/hyprland/scripts/launch_first_available.sh "gnome-system-monitor" "plasma-systemmonitor --page-name Processes" "command -v btop && kitty -1 fish -c btop"]=])) -- Task manager
    bind("Super", "I", exec("$settingsApp")) -- Settings app

    bind("Super", "Space", hl.dsp.global("kando:example-menu")) -- Kando fast opener

    -- Cursed stuff: make a window not amogus large.
    bind("Ctrl+Super", "Backslash", hl.dsp.window.resize({ x = 640, y = 480 })) -- [hidden]

    -- Custom keybinds are sourced last, matching the legacy config order.
    require("custom.keybinds").setup({
        bind = bind,
        unbind = h.unbind,
        exec = exec,
    })
    end)

-- A start event replaces the legacy config-time `hyprctl dispatch submap global`.
-- Dispatching during Lua config parsing crashes Hyprland 0.56.1 verify-config.
hl.on("hyprland.start", function()
    hl.dispatch(hl.dsp.submap("global"))
end)
