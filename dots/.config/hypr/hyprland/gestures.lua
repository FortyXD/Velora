-- Touchpad gestures. Each has an id: Settings → Mouse & touchpad → Gestures turns one off or gives it
-- another action (custom/gesture_overrides.lua, written by the settings app), and reads the list from
-- $XDG_RUNTIME_DIR/velora-gestures.json, as do the cheat sheet and the tour.
--
-- Actions drawn by the shell (the app library, the overview) follow the fingers: their progress goes
-- to Quickshell as `custom>>gesture:<action>:<begin|update|end|cancel>:<progress>` events on socket2.
local actions = require("hyprland.window_actions")
local M = {}

M.manifest_path = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/velora-gestures.json"

-- The defaults: the swipes and pinches with three fingers and four fingers sideways and up were
-- there before; the rest take combinations nothing used.
M.defaults = {
    { id = "move_window", fingers = 3, direction = "swipe", action = "move", description = "Move the window" },
    { id = "float_window", fingers = 3, direction = "pinch", action = "float", description = "Float or tile the window" },
    { id = "workspaces", fingers = 4, direction = "horizontal", action = "workspace", description = "Switch workspaces" },
    { id = "overview", fingers = 4, direction = "up", action = "overview", description = "Overview" },
    { id = "app_library", fingers = 4, direction = "down", action = "library", description = "All apps, or close the overview" },
    { id = "app_library_pinch", fingers = 4, direction = "pinchin", action = "library", description = "All apps" },
    { id = "show_desktop", fingers = 4, direction = "pinchout", action = "desktop", description = "Show the desktop" },
    { id = "switch_windows", fingers = 3, direction = "horizontal", mods = "ALT", action = "switcher", description = "Switch between windows" },
    { id = "close_window", fingers = 3, direction = "down", mods = "ALT", action = "close", description = "Close the window" },
    { id = "resize_window", fingers = 3, direction = "swipe", mods = "SUPER", action = "resize", description = "Resize the window" },
    { id = "volume", fingers = 3, direction = "vertical", mods = "CTRL", action = "volume", description = "Volume" },
    { id = "brightness", fingers = 3, direction = "vertical", mods = "SHIFT", action = "brightness", description = "Screen brightness" },
    { id = "zoom", fingers = 2, direction = "pinch", mods = "SUPER", action = "zoom", description = "Magnify the screen" },
    { id = "window_left", fingers = 4, direction = "left", mods = "SUPER", action = "window_previous_workspace", description = "Move the window to the previous workspace" },
    { id = "window_right", fingers = 4, direction = "right", mods = "SUPER", action = "window_next_workspace", description = "Move the window to the next workspace" },
    { id = "maximize", fingers = 4, direction = "up", mods = "SUPER", action = "maximize", description = "Maximize or restore the window" },
    { id = "minimize", fingers = 4, direction = "down", mods = "SUPER", action = "minimize", description = "Minimize the window" },
}

-- Actions the settings app offers, in its order
M.actions = { "none", "workspace", "overview", "library", "desktop", "switcher", "move", "resize", "float",
    "maximize", "minimize", "close", "fullscreen", "window_previous_workspace", "window_next_workspace",
    "volume", "brightness", "zoom", "scratchpad", "command" }

local function emit(action, phase, progress)
    hl.dispatch(hl.dsp.event(string.format("gesture:%s:%s:%.3f", action, phase, progress or 0)))
end

-- How far along the gesture is, 0 at its start and 1 a comfortable swipe or pinch later
local SWIPE = 320
local function along(direction, event, progress)
    if direction == "pinchin" or direction == "pinchout" or direction == "pinch" then
        local scale = event.scale or 1
        return math.max(0, direction == "pinchout" and (scale - 1) * 1.5 or (1 - scale) * 2)
    end
    local dx, dy = event.delta and event.delta.x or 0, event.delta and event.delta.y or 0
    local step = (direction == "up" and -dy) or (direction == "down" and dy) or (direction == "left" and -dx)
        or (direction == "right" and dx) or (direction == "vertical" and dy) or dx
    return math.max(0, progress + step / SWIPE)
end

-- Drawn by the shell, following the fingers
local function live(action, direction)
    local progress = 0
    return {
        start = function()
            progress = 0
            emit(action, "begin", 0)
        end,
        update = function(event)
            progress = along(direction, event, progress)
            emit(action, "update", progress)
        end,
        finish = function(event)
            emit(action, event.cancelled and "cancel" or "end", progress)
        end,
    }
end

-- A step every `size` of movement, e.g. 5% of volume
local function stepper(size, run)
    local carried = 0
    return {
        start = function()
            carried = 0
        end,
        update = function(event)
            carried = carried + (event.delta and event.delta.y or 0)
            while math.abs(carried) >= size do
                local down = carried > 0
                carried = carried - (down and size or -size)
                run(down)
            end
        end,
        finish = function() end,
    }
end

local function window_switcher()
    local carried = 0
    return {
        start = function()
            carried = 0
            hl.dispatch(hl.dsp.global("quickshell:windowSwitcherNext"))
        end,
        update = function(event)
            carried = carried + (event.delta and event.delta.x or 0)
            while math.abs(carried) >= 120 do
                local forward = carried > 0
                carried = carried - (forward and 120 or -120)
                hl.dispatch(hl.dsp.global(forward and "quickshell:windowSwitcherNext" or "quickshell:windowSwitcherPrevious"))
            end
        end,
        finish = function()
            hl.dispatch(hl.dsp.global("quickshell:windowSwitcherCommit"))
        end,
    }
end

-- hl.gesture fields for an action, or nil for "none"
function M.build(gesture)
    local action = gesture.action
    local spec = { fingers = gesture.fingers, direction = gesture.direction, mods = gesture.mods }
    if action == "move" or action == "resize" or action == "float" or action == "close" or action == "fullscreen" or action == "workspace" then
        spec.action = action
    elseif action == "overview" or action == "library" then
        spec.action = live(action, gesture.direction)
    elseif action == "desktop" then
        spec.action = live(action, gesture.direction) -- The shell shows it coming and does it
    elseif action == "maximize" then
        spec.action = function() actions.toggle_maximize() end
    elseif action == "minimize" then
        spec.action = function() actions.minimize() end
    elseif action == "window_previous_workspace" or action == "window_next_workspace" then
        local workspace = action == "window_next_workspace" and "r+1" or "r-1"
        spec.action = function() hl.dispatch(hl.dsp.window.move({ workspace = workspace })) end
    elseif action == "switcher" then
        spec.action = window_switcher()
    elseif action == "volume" then
        spec.action = stepper(40, function(down)
            hl.dispatch(hl.dsp.exec_cmd("wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%" .. (down and "-" or "+")))
        end)
    elseif action == "brightness" then
        spec.action = stepper(40, function(down)
            hl.dispatch(hl.dsp.exec_cmd("brightnessctl -q set 5%" .. (down and "-" or "+")))
        end)
    elseif action == "zoom" then
        spec.action, spec.zoom_level, spec.mode = "cursorZoom", 1, "live"
    elseif action == "scratchpad" then
        spec.action = function() hl.dispatch(hl.dsp.workspace.toggle_special("")) end
    elseif action == "command" and gesture.command and gesture.command ~= "" then
        spec.action = function() hl.dispatch(hl.dsp.exec_cmd(gesture.command)) end
    else
        return nil
    end
    return spec
end

local function json(value)
    local kind = type(value)
    if kind == "string" then
        return '"' .. value:gsub('[%c"\\]', function(char)
            return ({ ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n" })[char] or string.format("\\u%04x", char:byte())
        end) .. '"'
    elseif kind == "number" or kind == "boolean" then
        return tostring(value)
    elseif kind == "table" then
        local parts = {}
        if #value > 0 then
            for _, item in ipairs(value) do parts[#parts + 1] = json(item) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        local names = {}
        for name in pairs(value) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do parts[#parts + 1] = json(name) .. ":" .. json(value[name]) end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
end

-- The defaults with the user's changes: id -> false (off) or { action = "...", command = "..." }
function M.effective()
    package.loaded["custom.gesture_overrides"] = nil
    local ok, overrides = pcall(require, "custom.gesture_overrides")
    overrides = ok and type(overrides) == "table" and overrides or {}
    local list = {}
    for _, default in ipairs(M.defaults) do
        local gesture = {}
        for key, value in pairs(default) do gesture[key] = value end
        gesture.default_action = default.action
        local override = overrides[default.id]
        if override == false then
            gesture.action = "none"
        elseif type(override) == "table" and override.action then
            gesture.action = override.action
            gesture.command = override.command
        end
        list[#list + 1] = gesture
    end
    return list
end

function M.setup()
    local list = M.effective()
    for _, gesture in ipairs(list) do
        local spec = M.build(gesture)
        if spec then
            local ok, error = pcall(hl.gesture, spec)
            if not ok then
                gesture.error = tostring(error)
            end
        end
    end
    local file = io.open(M.manifest_path .. ".tmp", "w")
    if file then
        file:write(json({ gestures = list, actions = M.actions }), "\n")
        file:close()
        os.rename(M.manifest_path .. ".tmp", M.manifest_path)
    end
end

return M
