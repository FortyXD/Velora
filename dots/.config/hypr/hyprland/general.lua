-- Internal laptop display.
hl.monitor({
    output = "eDP-1",
    mode = "2880x1800@60",
    position = "0x0",
    scale = 1.5,
})

hl.config({
    gestures = {
        workspace_swipe_distance = 700,
        workspace_swipe_cancel_ratio = 0.2,
        workspace_swipe_min_speed_to_force = 5,
        workspace_swipe_direction_lock = true,
        workspace_swipe_direction_lock_threshold = 10,
        workspace_swipe_create_new = true,
    },
    general = {
        gaps_in = 4,
        gaps_out = 5,
        gaps_workspaces = 50,
        border_size = 1,
        col = {
            active_border = "rgba(0DB7D455)",
            inactive_border = "rgba(31313600)",
        },
        resize_on_border = true,
        no_focus_fallback = true,
        allow_tearing = true,
        snap = {
            enabled = true,
            window_gap = 4,
            monitor_gap = 5,
            respect_gaps = true,
        },
    },
    dwindle = {
        preserve_split = true,
        smart_split = false,
        smart_resizing = false,
    },
    decoration = {
        rounding_power = 2,
        rounding = 18,
        blur = {
            enabled = true,
            xray = true,
            special = false,
            new_optimizations = true,
            size = 10,
            passes = 3,
            brightness = 1,
            noise = 0.05,
            contrast = 0.89,
            vibrancy = 0.5,
            vibrancy_darkness = 0.5,
            popups = false,
            popups_ignorealpha = 0.6,
            input_methods = true,
            input_methods_ignorealpha = 0.8,
        },
        shadow = {
            enabled = true,
            range = 20,
            offset = { 0, 2 },
            render_power = 10,
            color = "rgba(00000020)",
        },
        dim_inactive = true,
        dim_strength = 0.05,
        dim_special = 0.2,
    },
    animations = {
        enabled = true,
    },
    input = {
        kb_layout = "us,ru",
        numlock_by_default = true,
        repeat_delay = 250,
        repeat_rate = 35,
        -- No grp: toggle here: XKB would turn Shift or Alt into a layout switch whenever both
        -- are held, so no Shift+Alt shortcut could work. keybinds.lua switches on a clean
        -- Alt+Shift tap instead.
        kb_options = "",
        follow_mouse = 1,
        off_window_axis_events = 2,
        touchpad = {
            natural_scroll = true,
            disable_while_typing = false,
            -- One-finger clicks in the bottom-right corner and two-finger taps both produce right click.
            clickfinger_behavior = false,
            tap_to_click = true,
            scroll_factor = 2.0,
        },
    },
    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        vrr = 0,
        mouse_move_enables_dpms = true,
        key_press_enables_dpms = true,
        animate_manual_resizes = false,
        animate_mouse_windowdragging = false,
        enable_swallow = false,
        swallow_regex = "(foot|kitty|allacritty|Alacritty)",
        on_focus_under_fullscreen = 2,
        allow_session_lock_restore = true,
        session_lock_xray = true,
        initial_workspace_tracking = false,
        focus_on_activate = true,
    },
    debug = {
        vfr = true,
    },
    binds = {
        scroll_event_delay = 0,
        hide_special_on_workspace_change = true,
    },
    cursor = {
        zoom_factor = 1,
        zoom_rigid = false,
        zoom_disable_aa = true,
        hotspot_padding = 1,
    },
    xwayland = {
        force_zero_scaling = true,
    },
})

-- Window animations; the settings app can load another profile from hyprland/animations/ after this
require("hyprland.animations.material")
