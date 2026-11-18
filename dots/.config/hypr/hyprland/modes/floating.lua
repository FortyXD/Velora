-- Free windows, as on Windows and macOS (Settings → Desktop → Windows → Free): every window floats
-- where you put it and opens where its app was last closed, or centered, stepping aside from a
-- window already there. Super+arrows snap a window to halves and quarters of the screen, Super+Down
-- minimizes it, Super+D shows the desktop.
--
-- hyprland.lua loads this before the default rules, so a rule that tiles a particular app still
-- wins; keybinds.lua binds the actions it returns. The shell calls the same actions through
-- `hyprctl eval 'require("hyprland.modes.floating").snap("left")'` (snap layouts, the window menu).
local actions = require("hyprland.window_actions")
local M = {}

-- Shared with tiled windows (gestures, the taskbar)
M.minimize = actions.minimize
M.restore = actions.restore
M.show_desktop = actions.show_desktop

local TAG = "velora-free" -- Floated by this mode, so tiling can take them back

hl.window_rule({ match = { class = ".*" }, float = true })

-- Last size and place of each app, as a Lua table file
local state_dir = (os.getenv("XDG_STATE_HOME") or ((os.getenv("HOME") or "") .. "/.local/state")) .. "/velora"
local state_path = state_dir .. "/window-geometry.lua"
local remembered = {}
do
    local chunk = loadfile(state_path, "t", {})
    local ok, value = pcall(chunk or function() return {} end)
    if ok and type(value) == "table" then
        remembered = value
    end
end

local function save()
    os.execute("mkdir -p -- '" .. state_dir:gsub("'", "'\\''") .. "'")
    local file = io.open(state_path .. ".tmp", "w")
    if not file then
        return
    end
    local classes = {}
    for class in pairs(remembered) do
        classes[#classes + 1] = class
    end
    table.sort(classes)
    file:write("-- Written by hyprland/modes/floating.lua: where each app's window was last closed\nreturn {\n")
    for _, class in ipairs(classes) do
        file:write(string.format("    [%q] = {", class))
        for index, g in ipairs(remembered[class]) do
            if g.w then
                file:write(string.format("[%d]={x=%d,y=%d,w=%d,h=%d,monitor=%q},", index, g.x, g.y, g.w, g.h, g.monitor or ""))
            else
                file:write(string.format("[%d]={},", index))
            end
        end
        file:write("},\n")
    end
    file:write("}\n")
    file:close()
    os.rename(state_path .. ".tmp", state_path)
end

local function gap()
    local gaps = hl.get_config("general:gaps_out")
    if type(gaps) == "table" then
        return gaps.top or 0
    end
    return tonumber(gaps) or 0
end

-- The part of a monitor windows may use, in layout coordinates: without bars, docks and outer gaps
local function work_area(monitor)
    local scale = (monitor.scale or 1) > 0 and monitor.scale or 1
    local reserved = monitor.reserved or {}
    local g = gap()
    local left, top = reserved.left or 0, reserved.top or 0
    local width, height = monitor.width, monitor.height
    if (monitor.transform or 0) % 2 == 1 then width, height = height, width end
    return {
        x = monitor.x + left + g,
        y = monitor.y + top + g,
        w = width / scale - left - (reserved.right or 0) - g * 2,
        h = height / scale - top - (reserved.bottom or 0) - g * 2,
    }
end

local function target(window)
    return "address:" .. window.address
end

local find = actions.find

-- Tells the shell (the tour) what just happened: `custom>>velora:<what>`
local function announce(what)
    pcall(function() hl.dispatch(hl.dsp.event("velora:" .. what)) end)
end

local function place(window, x, y, w, h, world)
    local native = hl.plugin and hl.plugin.velora
    if native and native.place and native.place(window.address, x, y, w, h, world == true) then return end
    hl.dispatch(hl.dsp.window.resize({ x = math.floor(w), y = math.floor(h), window = target(window) }))
    hl.dispatch(hl.dsp.window.move({ x = math.floor(x), y = math.floor(y), window = target(window) }))
end

local function geometry(window)
    local native = hl.plugin and hl.plugin.velora
    if native and native.geometry then
        local world = native.geometry(window.address)
        if world then return world end
    end
    return { x = window.at.x, y = window.at.y, w = window.size.x, h = window.size.y }
end

-- Small windows are dialogs, popups and tool windows: the rules and the app place those
local function is_main_window(window)
    return window.class ~= "" and window.size.x >= 320 and window.size.y >= 200 and not window.pinned
end

-- Migrate the single-window records written by earlier releases.
for class, entry in pairs(remembered) do
    if type(entry) ~= "table" then remembered[class] = nil
    elseif entry.w then remembered[class] = { entry } end
end
local slots = {}
local function slot_for(w)
    if slots[w.address] then return slots[w.address] end
    local occupied = {}
    for _, other in ipairs(hl.get_windows()) do
        if other.address ~= w.address and other.class == w.class and slots[other.address] then
            occupied[slots[other.address]] = true
        end
    end
    local index = 1
    while occupied[index] do index = index + 1 end
    slots[w.address] = index
    return index
end

local function on_canvas()
    local native = hl.plugin and hl.plugin.velora
    return native and native.active and native.active()
end

hl.on("window.open", function(window)
    if not window or not window.monitor or not window.workspace or window.workspace.special or not window.floating or (window.fullscreen or 0) ~= 0 or not is_main_window(window) then
        return
    end
    local native = hl.plugin and hl.plugin.velora
    if not native or not native.regular or native.regular(window.address) then
        pcall(function() hl.dispatch(hl.dsp.window.tag({ tag = "+" .. TAG, window = target(window) })) end)
    end
    if on_canvas() then return end
    local area = work_area(window.monitor)
    local saved = (remembered[window.class] or {})[slot_for(window)]
    -- The first window of an app opens where it was; more of them open stepped aside
    if saved and saved.w and saved.monitor == window.monitor.name then
        local w, h = math.min(saved.w, area.w), math.min(saved.h, area.h)
        local x = math.max(area.x, math.min(saved.x, area.x + area.w - w))
        local y = math.max(area.y, math.min(saved.y, area.y + area.h - h))
        place(window, x, y, w, h)
        return
    end
    local w, h = window.size.x, window.size.y
    if w > area.w or h > area.h then
        w, h = area.w * 0.8, area.h * 0.8
    end
    local x, y = area.x + (area.w - w) / 2, area.y + (area.h - h) / 2
    -- Cascade over windows already in that spot
    local step = 32
    for _ = 1, 8 do
        local taken = false
        for _, other in ipairs(hl.get_windows()) do
            if other.address ~= window.address and other.workspace and other.workspace.id == window.workspace.id
                and math.abs(other.at.x - x) < step / 2 and math.abs(other.at.y - y) < step / 2 then
                taken = true
                break
            end
        end
        if not taken or x + w + step > area.x + area.w or y + h + step > area.y + area.h then
            break
        end
        x, y = x + step, y + step
    end
    place(window, x, y, w, h)
end)

-- Snapped windows remember where they were, so the opposite key puts them back
local snapped = {}

hl.on("window.close", function(window)
    if not window then
        return
    end
    local address = window.address
    local was_snapped = snapped[address]
    snapped[address] = nil
    local index = slots[address]
    slots[address] = nil
    if on_canvas() or not window.monitor or not window.workspace or window.workspace.special or not window.floating or (window.fullscreen or 0) ~= 0 or not is_main_window(window) then
        return
    end
    local g = was_snapped and was_snapped.restore or geometry(window)
    local entries = remembered[window.class] or {}
    index = index or 1
    for i = #entries + 1, index - 1 do entries[i] = {} end
    remembered[window.class] = entries
    entries[index] = { x = g.x, y = g.y, w = g.w, h = g.h, monitor = window.monitor.name }
    save()
end)

local function active()
    local window = hl.get_active_window()
    if window and not window.floating then
        hl.dispatch(hl.dsp.window.float({ action = "set", window = target(window) }))
        window = hl.get_active_window()
    end
    return window
end

local function maximized(window)
    return (window.fullscreen or 0) == 1
end

-- Zones, as fractions of the work area: x, y, width, height
local zones = {
    ["left"] = { 0, 0, 0.5, 1 },
    ["right"] = { 0.5, 0, 0.5, 1 },
    ["top-left"] = { 0, 0, 0.5, 0.5 },
    ["top-right"] = { 0.5, 0, 0.5, 0.5 },
    ["bottom-left"] = { 0, 0.5, 0.5, 0.5 },
    ["bottom-right"] = { 0.5, 0.5, 0.5, 0.5 },
    ["left-third"] = { 0, 0, 1 / 3, 1 },
    ["middle-third"] = { 1 / 3, 0, 1 / 3, 1 },
    ["right-third"] = { 2 / 3, 0, 1 / 3, 1 },
    ["left-two-thirds"] = { 0, 0, 2 / 3, 1 },
    ["right-two-thirds"] = { 1 / 3, 0, 2 / 3, 1 },
    ["center"] = { 0.15, 0.1, 0.7, 0.8 },
}
M.zones = zones

-- Puts a window (the active one, or `address`) into a zone of its monitor
function M.snap(zone, address)
    local window = find(address)
    local fraction = zones[zone]
    if not window or not fraction then
        return
    end
    if not window.floating then
        hl.dispatch(hl.dsp.window.float({ action = "set", window = target(window) }))
    end
    if window.fullscreen == 2 then
        hl.dispatch(hl.dsp.window.fullscreen({ mode = "fullscreen", action = "unset", window = target(window) }))
    end
    if maximized(window) then
        hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "unset", window = target(window) }))
    end
    local area = work_area(on_canvas() and hl.get_active_monitor() or window.monitor)
    local g = gap()
    -- A gap between neighbors, none at the edges of the work area
    local x0 = area.x + area.w * fraction[1] + (fraction[1] > 0 and g / 2 or 0)
    local y0 = area.y + area.h * fraction[2] + (fraction[2] > 0 and g / 2 or 0)
    local x1 = area.x + area.w * (fraction[1] + fraction[3]) - (fraction[1] + fraction[3] < 1 and g / 2 or 0)
    local y1 = area.y + area.h * (fraction[2] + fraction[4]) - (fraction[2] + fraction[4] < 1 and g / 2 or 0)
    local previous = snapped[window.address]
    snapped[window.address] = { zone = zone, restore = previous and previous.restore or geometry(window) }
    place(window, x0, y0, x1 - x0, y1 - y0)
    announce("snap:" .. zone)
end

function M.unsnap(window)
    local state = snapped[window.address]
    snapped[window.address] = nil
    if state then
        local g = state.restore
        place(window, g.x, g.y, g.w, g.h, g.world)
        announce("snap:none")
    end
end

function M.toggle_maximize(address)
    local window = find(address)
    if window then
        actions.toggle_maximize(window.address)
        announce("maximize")
    end
end

-- Windows 11's Super+arrows
function M.left()
    local window = active()
    if not window then return end
    local zone = snapped[window.address] and snapped[window.address].zone
    if zone == "right" then M.unsnap(window)
    elseif zone == "top-right" then M.snap("top-left")
    elseif zone == "bottom-right" then M.snap("bottom-left")
    elseif zone ~= "left" then M.snap("left") end
end

function M.right()
    local window = active()
    if not window then return end
    local zone = snapped[window.address] and snapped[window.address].zone
    if zone == "left" then M.unsnap(window)
    elseif zone == "top-left" then M.snap("top-right")
    elseif zone == "bottom-left" then M.snap("bottom-right")
    elseif zone ~= "right" then M.snap("right") end
end

function M.up()
    local window = active()
    if not window then return end
    local zone = snapped[window.address] and snapped[window.address].zone
    if zone == "left" then M.snap("top-left")
    elseif zone == "right" then M.snap("top-right")
    elseif zone == "bottom-left" then M.snap("left")
    elseif zone == "bottom-right" then M.snap("right")
    elseif not maximized(window) then M.toggle_maximize() end
end

function M.down()
    local window = hl.get_active_window()
    if not window then return end
    local zone = snapped[window.address] and snapped[window.address].zone
    if window.fullscreen == 2 then hl.dispatch(hl.dsp.window.fullscreen({ mode = "fullscreen", action = "unset", window = target(window) }))
    elseif maximized(window) then M.toggle_maximize()
    elseif zone == "left" then M.snap("bottom-left")
    elseif zone == "right" then M.snap("bottom-right")
    elseif zone == "top-left" then M.snap("left")
    elseif zone == "top-right" then M.snap("right")
    elseif zone then M.unsnap(window)
    else M.minimize() end
end

-- Switching from tiling: the windows already open become free where they are
hl.on("config.reloaded", function()
    for _, window in ipairs(hl.get_windows()) do
        if window.workspace and not window.workspace.special and is_main_window(window) then
            slot_for(window)
        end
        if window.workspace and not window.floating and not window.workspace.special and is_main_window(window) then
            hl.dispatch(hl.dsp.window.float({ action = "set", window = target(window) }))
            pcall(function() hl.dispatch(hl.dsp.window.tag({ tag = "+" .. TAG, window = target(window) })) end)
        end
    end
end)

M.TAG = TAG
return M
