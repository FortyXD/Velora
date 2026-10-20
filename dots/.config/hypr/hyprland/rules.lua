local function window(match, effects)
    effects.match = match
    hl.window_rule(effects)
end

local function layer(namespace, effects)
    effects.match = { namespace = namespace }
    hl.layer_rule(effects)
end

-- Window rules

-- Disable blur for XWayland context menus, then for every window.
window({ class = [=[^()$]=], title = [=[^()$]=] }, { no_blur = true })
window({ class = [=[.*]=] }, { no_blur = true })

-- Floating dialogs.
window({ title = [=[^(Open File)(.*)$]=] }, { center = true })
window({ title = [=[^(Open File)(.*)$]=] }, { float = true })
window({ title = [=[^(Select a File)(.*)$]=] }, { center = true })
window({ title = [=[^(Select a File)(.*)$]=] }, { float = true })
window({ title = [=[^(Choose wallpaper)(.*)$]=] }, { center = true })
window({ title = [=[^(Choose wallpaper)(.*)$]=] }, { float = true })
window({ title = [=[^(Choose wallpaper)(.*)$]=] }, { size = { "monitor_w*.60", "monitor_h*.65" } })
window({ title = [=[^(Open Folder)(.*)$]=] }, { center = true })
window({ title = [=[^(Open Folder)(.*)$]=] }, { float = true })
window({ title = [=[^(Save As)(.*)$]=] }, { center = true })
window({ title = [=[^(Save As)(.*)$]=] }, { float = true })
window({ title = [=[^(Library)(.*)$]=] }, { center = true })
window({ title = [=[^(Library)(.*)$]=] }, { float = true })
window({ title = [=[^(File Upload)(.*)$]=] }, { center = true })
window({ title = [=[^(File Upload)(.*)$]=] }, { float = true })
window({ title = [=[^(.*)(wants to save)$]=] }, { center = true })
window({ title = [=[^(.*)(wants to save)$]=] }, { float = true })
window({ title = [=[^(.*)(wants to open)$]=] }, { center = true })
window({ title = [=[^(.*)(wants to open)$]=] }, { float = true })
window({ class = [=[^(blueberry\.py)$]=] }, { float = true })
window({ class = [=[^(guifetch)$]=] }, { float = true })
window({ class = [=[^(pavucontrol)$]=] }, { float = true })
window({ class = [=[^(pavucontrol)$]=] }, { size = { "monitor_w*.45", "monitor_h*.45" } })
window({ class = [=[^(pavucontrol)$]=] }, { center = true })
window({ class = [=[^(org.pulseaudio.pavucontrol)$]=] }, { float = true })
window({ class = [=[^(org.pulseaudio.pavucontrol)$]=] }, { size = { "monitor_w*.45", "monitor_h*.45" } })
window({ class = [=[^(org.pulseaudio.pavucontrol)$]=] }, { center = true })
window({ class = [=[^(nm-connection-editor)$]=] }, { float = true })
window({ class = [=[^(nm-connection-editor)$]=] }, { size = { "monitor_w*.45", "monitor_h*.45" } })
window({ class = [=[^(nm-connection-editor)$]=] }, { center = true })
window({ class = [=[.*plasmawindowed.*]=] }, { float = true })
window({ class = [=[kcm_.*]=] }, { float = true })
window({ class = [=[.*bluedevilwizard]=] }, { float = true })
window({ title = [=[.*Welcome]=] }, { float = true })
window({ title = [=[^(illogical-impulse Settings)$]=] }, { float = true })
window({ title = [=[^(Folis Toolbox)$]=] }, { float = true, center = true, size = { "monitor_w*.55", "monitor_h*.65" } })
window({ title = [=[.*Shell conflicts.*]=] }, { float = true })
window({ class = [=[org.freedesktop.impl.portal.desktop.kde]=] }, { float = true })
window({ class = [=[org.freedesktop.impl.portal.desktop.kde]=] }, { size = { "monitor_w*.60", "monitor_h*.65" } })
window({ class = [=[^(Zotero)$]=] }, { float = true })
window({ class = [=[^(Zotero)$]=] }, { size = { "monitor_w*.45", "monitor_h*.45" } })

-- Move rules.
window({ class = [=[^(plasma-changeicons)$]=] }, { float = true })
window({ class = [=[^(plasma-changeicons)$]=] }, { no_initial_focus = true })
window({ class = [=[^(plasma-changeicons)$]=] }, { move = { 999999, 999999 } })
window({ title = [=[^(Copying — Dolphin)$]=] }, { move = { 40, 80 } })

-- Tiling.
window({ class = [=[^dev\.warp\.Warp$]=] }, { tile = true })

-- Picture-in-Picture.
local pip = { title = [=[^([Pp]icture[-\s]?[Ii]n[-\s]?[Pp]icture)(.*)$]=] }
window(pip, { float = true })
window(pip, { keep_aspect_ratio = true })
window(pip, { move = { "monitor_w*.73", "monitor_h*.72" } })
window(pip, { size = { "monitor_w*.25", "monitor_h*.25" } })
window(pip, { float = true })
window(pip, { pin = true })

-- Screen sharing.
local sharing = { title = [=[.*is sharing (a window|your screen).*]=] }
window(sharing, { float = true })
window(sharing, { pin = true })
window(sharing, { move = { "monitor_w*.5-window_w*.5", "monitor_h-window_h-12" } })

-- Tearing.
window({ title = [=[.*\.exe]=] }, { immediate = true })
window({ title = [=[.*minecraft.*]=] }, { immediate = true })
window({ class = [=[^(steam_app).*]=] }, { immediate = true })

-- JetBrains focus/rerender workaround.
window({ class = [=[^jetbrains-.*$]=], float = true, title = [=[^$|^\s$|^win\d+$]=] }, { no_initial_focus = true })

-- No shadow for tiled windows.
window({ float = false }, { no_shadow = true })

-- Workspace rules.
hl.workspace_rule({
    workspace = "special:special",
    gaps_out = 30,
})

-- Layer rules.
layer([=[.*]=], { xray = true })
layer([=[walker]=], { no_anim = true })
layer([=[selection]=], { no_anim = true })
layer([=[overview]=], { no_anim = true })
layer([=[anyrun]=], { no_anim = true })
layer([=[indicator.*]=], { no_anim = true })
layer([=[osk]=], { no_anim = true })
layer([=[hyprpicker]=], { no_anim = true })

layer([=[noanim]=], { no_anim = true })
layer([=[gtk-layer-shell]=], { blur = true })
layer([=[gtk-layer-shell]=], { ignore_alpha = 0 })
layer([=[launcher]=], { blur = true })
layer([=[launcher]=], { ignore_alpha = 0.5 })
layer([=[notifications]=], { blur = true })
layer([=[notifications]=], { ignore_alpha = 0.69 })

-- AGS.
layer([=[sideleft.*]=], { animation = "slide left" })
layer([=[sideright.*]=], { animation = "slide right" })
layer([=[session[0-9]*]=], { blur = true })
layer([=[bar[0-9]*]=], { blur = true })
layer([=[bar[0-9]*]=], { ignore_alpha = 0.6 })
layer([=[barcorner.*]=], { blur = true })
layer([=[barcorner.*]=], { ignore_alpha = 0.6 })
layer([=[dock[0-9]*]=], { blur = true })
layer([=[dock[0-9]*]=], { ignore_alpha = 0.6 })
layer([=[indicator.*]=], { blur = true })
layer([=[indicator.*]=], { ignore_alpha = 0.6 })
layer([=[overview[0-9]*]=], { blur = true })
layer([=[overview[0-9]*]=], { ignore_alpha = 0.6 })
layer([=[cheatsheet[0-9]*]=], { blur = true })
layer([=[cheatsheet[0-9]*]=], { ignore_alpha = 0.6 })
layer([=[sideright[0-9]*]=], { blur = true })
layer([=[sideright[0-9]*]=], { ignore_alpha = 0.6 })
layer([=[sideleft[0-9]*]=], { blur = true })
layer([=[sideleft[0-9]*]=], { ignore_alpha = 0.6 })
layer([=[indicator.*]=], { blur = true })
layer([=[indicator.*]=], { ignore_alpha = 0.6 })
layer([=[osk[0-9]*]=], { blur = true })
layer([=[osk[0-9]*]=], { ignore_alpha = 0.6 })

-- Quickshell: illogical-impulse.
layer([=[quickshell:.*]=], { blur_popups = true })
layer([=[quickshell:.*]=], { blur = true })
layer([=[quickshell:.*]=], { ignore_alpha = 0.79 })
layer([=[quickshell:bar]=], { animation = "slide" })
-- Glass bar (Bar → Style): blur even under a mostly see-through background
layer([=[quickshell:barGlass]=], { animation = "slide" })
layer([=[quickshell:barGlass]=], { blur = true })
layer([=[quickshell:barGlass]=], { ignore_alpha = 0.05 })
layer([=[quickshell:actionCenter]=], { no_anim = true })
layer([=[quickshell:cheatsheet]=], { animation = "slide bottom" })
layer([=[quickshell:dock]=], { animation = "slide bottom" })
layer([=[quickshell:screenCorners]=], { animation = "popin 120%" })
layer([=[quickshell:lockWindowPusher]=], { no_anim = true })
layer([=[quickshell:notificationPopup]=], { animation = "fade" })
layer([=[quickshell:overlay]=], { no_anim = true })
layer([=[quickshell:overlay]=], { ignore_alpha = 1 })
layer([=[quickshell:overview]=], { no_anim = true })
layer([=[quickshell:osk]=], { animation = "slide bottom" })
layer([=[quickshell:polkit]=], { no_anim = true })
layer([=[quickshell:openWith]=], { no_anim = true })
layer([=[quickshell:popup]=], { no_anim = true }) -- Bar popups animate themselves
layer([=[quickshell:popup]=], { xray = false })
layer([=[quickshell:popup]=], { ignore_alpha = 1 })
layer([=[quickshell:mediaControls]=], { ignore_alpha = 1 })
layer([=[quickshell:reloadPopup]=], { animation = "slide" })
layer([=[quickshell:regionSelector]=], { no_anim = true })
layer([=[quickshell:screenshot]=], { no_anim = true })
layer([=[quickshell:session]=], { blur = true })
layer([=[quickshell:session]=], { no_anim = true })
layer([=[quickshell:session]=], { ignore_alpha = 0 })
layer([=[quickshell:sidebarRight]=], { animation = "slide right" })
layer([=[quickshell:sidebarLeft]=], { animation = "slide left" })
layer([=[quickshell:verticalBar]=], { animation = "slide" })
layer([=[quickshell:osk]=], { order = -1 })

-- Quickshell: waffles.
layer([=[quickshell:wallpaperSelector]=], { animation = "slide top" })
layer([=[quickshell:wNotificationCenter]=], { no_anim = true })
layer([=[quickshell:wOnScreenDisplay]=], { no_anim = true })
layer([=[quickshell:wStartMenu]=], { no_anim = true })
layer([=[quickshell:wTaskView]=], { ignore_alpha = 0 })
layer([=[quickshell:wTaskView]=], { no_anim = true })

-- Launchers need to be fast.
layer([=[gtk4-layer-shell]=], { no_anim = true })
