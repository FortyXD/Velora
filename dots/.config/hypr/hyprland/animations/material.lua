-- Default motion: Material 3 expressive curves. Other profiles in this folder override parts of it.

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
