-- Internal laptop display.
hl.monitor({
    output = "eDP-1",
    mode = "2880x1800@60",
    position = "0x0",
    scale = 1.5,
})

hl.gesture({ fingers = 3, direction = "swipe", action = "move" })
hl.gesture({ fingers = 3, direction = "pinch", action = "float" })
hl.gesture({ fingers = 4, direction = "horizontal", action = "workspace" })
hl.gesture({
    fingers = 4,
    direction = "up",
    action = function()
        hl.dispatch(hl.dsp.global("quickshell:overviewWorkspacesToggle"))
    end,
})
hl.gesture({
    fingers = 4,
    direction = "down",
    action = function()
        hl.dispatch(hl.dsp.global("quickshell:overviewWorkspacesClose"))
    end,
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
        kb_options = "grp:alt_shift_toggle",
        follow_mouse = 1,
        off_window_axis_events = 2,
        touchpad = {
            natural_scroll = true,
            disable_while_typing = false,
            clickfinger_behavior = true,
            tap_to_click = false,
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

local curves = {
    expressiveFastSpatial = { { 0.42, 1.67 }, { 0.21, 0.90 } },
    expressiveSlowSpatial = { { 0.39, 1.29 }, { 0.35, 0.98 } },
    expressiveDefaultSpatial = { { 0.38, 1.21 }, { 0.22, 1.00 } },
    emphasizedDecel = { { 0.05, 0.7 }, { 0.1, 1 } },
    emphasizedAccel = { { 0.3, 0 }, { 0.8, 0.15 } },
    standardDecel = { { 0, 0 }, { 0, 1 } },
    menu_decel = { { 0.1, 1 }, { 0, 1 } },
    menu_accel = { { 0.52, 0.03 }, { 0.72, 0.08 } },
    stall = { { 1, -0.1 }, { 0.7, 0.85 } },
}

for name, points in pairs(curves) do
    hl.curve(name, { type = "bezier", points = points })
end

local animations = {
    { leaf = "windowsIn", speed = 3, bezier = "emphasizedDecel", style = "popin 80%" },
    { leaf = "fadeIn", speed = 3, bezier = "emphasizedDecel" },
    { leaf = "windowsOut", speed = 2, bezier = "emphasizedDecel", style = "popin 90%" },
    { leaf = "fadeOut", speed = 2, bezier = "emphasizedDecel" },
    { leaf = "windowsMove", speed = 3, bezier = "emphasizedDecel", style = "slide" },
    { leaf = "border", speed = 10, bezier = "emphasizedDecel" },
    { leaf = "layersIn", speed = 2.7, bezier = "emphasizedDecel", style = "popin 93%" },
    { leaf = "layersOut", speed = 2.4, bezier = "menu_accel", style = "popin 94%" },
    { leaf = "fadeLayersIn", speed = 0.5, bezier = "menu_decel" },
    { leaf = "fadeLayersOut", speed = 2.7, bezier = "stall" },
    { leaf = "workspaces", speed = 7, bezier = "menu_decel", style = "slide" },
    { leaf = "specialWorkspaceIn", speed = 2.8, bezier = "emphasizedDecel", style = "slidevert" },
    { leaf = "specialWorkspaceOut", speed = 1.2, bezier = "emphasizedAccel", style = "slidevert" },
    { leaf = "zoomFactor", speed = 3, bezier = "standardDecel" },
}

for _, animation in ipairs(animations) do
    animation.enabled = true
    hl.animation(animation)
end
