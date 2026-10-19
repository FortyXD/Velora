-- Smooth: slower and springier, with a little overshoot.

hl.curve("smoothSpring", { type = "bezier", points = { { 0.34, 1.36 }, { 0.36, 1 } } })
hl.curve("smoothOut", { type = "bezier", points = { { 0.4, 0 }, { 0.2, 1 } } })

local animations = {
    { leaf = "windowsIn", speed = 4.5, bezier = "smoothSpring", style = "popin 75%" },
    { leaf = "fadeIn", speed = 4, bezier = "smoothOut" },
    { leaf = "windowsOut", speed = 3, bezier = "smoothOut", style = "popin 85%" },
    { leaf = "fadeOut", speed = 3, bezier = "smoothOut" },
    { leaf = "windowsMove", speed = 4.5, bezier = "smoothSpring", style = "slide" },
    { leaf = "border", speed = 12, bezier = "smoothOut" },
    { leaf = "layersIn", speed = 3.8, bezier = "smoothSpring", style = "popin 90%" },
    { leaf = "layersOut", speed = 3, bezier = "smoothOut", style = "popin 92%" },
    { leaf = "fadeLayersIn", speed = 2, bezier = "smoothOut" },
    { leaf = "fadeLayersOut", speed = 3, bezier = "smoothOut" },
    { leaf = "workspaces", speed = 8, bezier = "smoothSpring", style = "slidefade 15%" },
    { leaf = "specialWorkspaceIn", speed = 4, bezier = "smoothSpring", style = "slidevert" },
    { leaf = "specialWorkspaceOut", speed = 2.5, bezier = "smoothOut", style = "slidevert" },
    { leaf = "zoomFactor", speed = 4, bezier = "smoothOut" },
}

for _, animation in ipairs(animations) do
    animation.enabled = true
    hl.animation(animation)
end
