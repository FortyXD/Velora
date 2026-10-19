-- Fast: the default motion at roughly half the duration.

local animations = {
    { leaf = "windowsIn", speed = 1.6, bezier = "emphasizedDecel", style = "popin 85%" },
    { leaf = "fadeIn", speed = 1.6, bezier = "emphasizedDecel" },
    { leaf = "windowsOut", speed = 1.2, bezier = "emphasizedDecel", style = "popin 92%" },
    { leaf = "fadeOut", speed = 1.2, bezier = "emphasizedDecel" },
    { leaf = "windowsMove", speed = 1.8, bezier = "emphasizedDecel", style = "slide" },
    { leaf = "border", speed = 5, bezier = "emphasizedDecel" },
    { leaf = "layersIn", speed = 1.5, bezier = "emphasizedDecel", style = "popin 95%" },
    { leaf = "layersOut", speed = 1.3, bezier = "menu_accel", style = "popin 96%" },
    { leaf = "fadeLayersIn", speed = 0.4, bezier = "menu_decel" },
    { leaf = "fadeLayersOut", speed = 1.5, bezier = "stall" },
    { leaf = "workspaces", speed = 3.5, bezier = "menu_decel", style = "slide" },
    { leaf = "specialWorkspaceIn", speed = 1.6, bezier = "emphasizedDecel", style = "slidevert" },
    { leaf = "specialWorkspaceOut", speed = 0.8, bezier = "emphasizedAccel", style = "slidevert" },
    { leaf = "zoomFactor", speed = 1.6, bezier = "standardDecel" },
}

for _, animation in ipairs(animations) do
    animation.enabled = true
    hl.animation(animation)
end
