-- Shell, compositor decorations and key bindings all address the same window.
local M = {}
local MIN, DESK = "special:velora-min-", "special:velora-desktop-"

local function destination(ws)
    if ws.id and ws.id > 0 then return tostring(ws.id) end
    return "name:" .. (ws.addressable_name or ws.name)
end

local function encode(s)
    return (s:gsub(".", function(c) return string.format("%02x", string.byte(c)) end))
end

local function origin(name)
    local encoded = name:match("^special:velora%-min%-(%x+)$") or name:match("^special:velora%-desktop%-(%x+)$")
    if encoded and #encoded % 2 == 0 then
        return (encoded:gsub("%x%x", function(hex) return string.char(tonumber(hex, 16)) end))
    end
end

function M.find(address)
    if not address then return hl.get_active_window() end
    for _, window in ipairs(hl.get_windows()) do
        if window.address == address then return window end
    end
end

local function retile(w)
    if not w.floating or require("hyprland.window_mode").current() ~= "tiling" then return end
    for _, tag in ipairs(w.tags or {}) do
        if tag == "velora-free" or tag == "velora-free*" then
            local target = "address:" .. w.address
            hl.dispatch(hl.dsp.window.float({ action = "unset", window = target }))
            hl.dispatch(hl.dsp.window.tag({ tag = "-velora-free", window = target }))
            return
        end
    end
end

local function move(window, workspace)
    hl.dispatch(hl.dsp.window.move({ workspace = workspace, follow = false, window = "address:" .. window.address }))
    if not workspace:match("^special:") then retile(window) end
end

function M.minimize(address)
    local w = M.find(address)
    if w and w.workspace and not w.workspace.special then
        move(w, MIN .. encode(destination(w.workspace)))
    end
end

function M.restore(address)
    local w = M.find(address)
    if not w or not w.workspace then return end
    local name = w.workspace.addressable_name or w.workspace.name
    local ws = origin(name)
    if ws then move(w, ws)
    elseif name == "special:minimized" or name == "special:desktop" then move(w, destination(hl.get_active_workspace())) end
    local native = hl.plugin and hl.plugin.velora
    if native and native.activate and native.activate(w.address) then return end
    local target = "address:" .. w.address
    if w.floating and hl.dsp.window.alter_zorder then
        hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = target }))
    end
    hl.dispatch(hl.dsp.focus({ window = target }))
end

function M.toggle_maximize(address)
    local w = M.find(address)
    if not w then return end
    hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle", layout_aware = false, window = "address:" .. w.address }))
end

function M.show_desktop()
    local native = hl.plugin and hl.plugin.velora
    if native and native.desktop and native.desktop() then return end
    local ws = hl.get_active_workspace()
    if not ws then return end
    local home = destination(ws)
    local parked = DESK .. encode(home)
    local shown, hidden = {}, {}
    for _, w in ipairs(hl.get_windows()) do
        if w.workspace and w.mapped and not w.pinned then
            local where = w.workspace.addressable_name or w.workspace.name
            if where == parked or where == "special:desktop" then hidden[#hidden + 1] = w
            elseif not w.workspace.special and destination(w.workspace) == home then shown[#shown + 1] = w end
        end
    end
    if #hidden > 0 then
        for _, w in ipairs(hidden) do move(w, home) end
    else
        for _, w in ipairs(shown) do move(w, parked) end
    end
end

function M.setup()
    -- 0.57 introduced this event. Older compositors still support shell actions.
    pcall(hl.on, "window.minimize", function(w, hide)
        if not w or not w.workspace then return end
        if hide then M.minimize(w.address)
        elseif origin(w.workspace.addressable_name or w.workspace.name) or (w.workspace.addressable_name or w.workspace.name) == "special:minimized" then M.restore(w.address) end
    end)
end

return M
