-- Minimal: quick fades instead of movement.

local animations = {
    { leaf = "windowsIn", speed = 1.5, bezier = "standardDecel", style = "popin 98%" },
    { leaf = "fadeIn", speed = 1.5, bezier = "standardDecel" },
    { leaf = "windowsOut", speed = 1.2, bezier = "standardDecel", style = "popin 98%" },
    { leaf = "fadeOut", speed = 1.2, bezier = "standardDecel" },
    { leaf = "windowsMove", speed = 1.5, bezier = "standardDecel", style = "slide" },
    { leaf = "border", speed = 3, bezier = "standardDecel" },
    { leaf = "layersIn", speed = 1.2, bezier = "standardDecel", style = "fade" },
    { leaf = "layersOut", speed = 1, bezier = "standardDecel", style = "fade" },
    { leaf = "fadeLayersIn", speed = 1.2, bezier = "standardDecel" },
    { leaf = "fadeLayersOut", speed = 1, bezier = "standardDecel" },
    { leaf = "workspaces", speed = 2, bezier = "standardDecel", style = "fade" },
    { leaf = "specialWorkspaceIn", speed = 1.5, bezier = "standardDecel", style = "fade" },
    { leaf = "specialWorkspaceOut", speed = 1.2, bezier = "standardDecel", style = "fade" },
    { leaf = "zoomFactor", speed = 1.5, bezier = "standardDecel" },
}

for _, animation in ipairs(animations) do
    animation.enabled = true
    hl.animation(animation)
end
