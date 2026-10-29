-- Window actions that work with free and tiled windows alike, for keybinds, gestures
-- (hyprland/gestures.lua) and the shell (`hyprctl eval 'require("hyprland.window_actions")…'`).
-- A minimized window waits on a special workspace until the taskbar, the dock or Alt+Tab brings it back.
local M = {}

M.MINIMIZED = "special:minimized"
M.DESKTOP = "special:desktop"

local function target(window)
    return "address:" .. window.address
end

function M.find(address)
    for _, window in ipairs(hl.get_windows()) do
        if window.address == address then
            return window
        end
    end
end

function M.minimize(address)
    local window = address and M.find(address) or hl.get_active_window()
    if window then
        hl.dispatch(hl.dsp.window.move({ workspace = M.MINIMIZED, follow = false, window = target(window) }))
    end
end

-- Back onto the workspace in front of you, focused
function M.restore(address)
    local window = M.find(address)
    if not window then
        return
    end
    if window.workspace.special then
        hl.dispatch(hl.dsp.window.move({ workspace = tostring(hl.get_active_workspace().id), follow = false, window = target(window) }))
    end
    hl.dispatch(hl.dsp.focus({ window = target(window) }))
end

function M.toggle_maximize(address)
    local window = address and M.find(address) or hl.get_active_window()
    if window then
        hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle", window = target(window) }))
    end
end

-- Every window of the workspace out of the way, and back again
function M.show_desktop()
    local workspace = hl.get_active_workspace()
    local hidden, shown = {}, {}
    for _, window in ipairs(hl.get_windows()) do
        if window.workspace.name == M.DESKTOP then
            hidden[#hidden + 1] = window
        elseif window.workspace.id == workspace.id then
            shown[#shown + 1] = window
        end
    end
    if #shown > 0 then
        for _, window in ipairs(shown) do
            hl.dispatch(hl.dsp.window.move({ workspace = M.DESKTOP, follow = false, window = target(window) }))
        end
    else
        for _, window in ipairs(hidden) do
            hl.dispatch(hl.dsp.window.move({ workspace = tostring(workspace.id), follow = false, window = target(window) }))
        end
    end
end

return M
