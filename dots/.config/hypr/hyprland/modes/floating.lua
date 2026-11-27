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
-- Keep the grab point on the title bar when a maximized window restores during a drag.
hl.config({binds = {drag_center_window = false}})

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

local function monitor_size(monitor)
    local mode = monitor.mode
    if type(mode) == "table" and mode.width and mode.height then return mode.width, mode.height end
    local scale = math.max(0.1, monitor.scale or 1)
    local width, height = monitor.width, monitor.height
    if (monitor.transform or 0) % 2 == 1 then width, height = height, width end
    return math.floor(width / scale), math.floor(height / scale)
end

-- Layout coordinates exclude space reserved by panels. Maximized windows fill that area.
local function work_area(monitor, outer_gap)
    local width, height = monitor_size(monitor)
    local reserved = monitor.reserved or {}
    local g = outer_gap or gap()
    local left, top = reserved.left or 0, reserved.top or 0
    return {
        x = monitor.x + left + g,
        y = monitor.y + top + g,
        w = width - left - (reserved.right or 0) - g * 2,
        h = height - top - (reserved.bottom or 0) - g * 2,
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

-- Settings has its own floating/centering rule. It still gets normal drag and monitor recovery.
local function uses_free_placement(window)
    return is_main_window(window) and window.class ~= "org.velora.Settings"
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

local function frame_info(window)
    local native = hl.plugin and hl.plugin.velora
    return native and native.frame_info and native.frame_info(window.address) or {}
end

-- A window may straddle outputs. Recover it only when no work area has a usable
-- stretch of its title bar. Hyprland reports client coordinates below a system frame.
local function keep_title_visible(window, preferred)
    if on_canvas() or not window.floating or (window.fullscreen or 0) ~= 0
        or not window.monitor or not window.workspace or window.workspace.special then return end
    local box, inset = geometry(window), frame_info(window).top or 0
    local top = box.y - inset
    local monitors = hl.get_monitors()
    local destination
    for _, monitor in ipairs(monitors) do
        local area = work_area(monitor, 0)
        if monitor.name == (preferred or window.monitor).name then destination = area end
        local overlap = math.min(box.x + box.w, area.x + area.w) - math.max(box.x, area.x)
        if overlap >= math.min(160, box.w, area.w) and top >= area.y
            and top + math.min(28, box.h, area.h) <= area.y + area.h then return end
    end
    if not monitors[1] then return end
    local area = destination or work_area(monitors[1], 0)
    local x = math.max(area.x, math.min(box.x, area.x + area.w - box.w))
    local y = math.max(area.y, math.min(top, area.y + area.h - box.h - inset)) + inset
    hl.dispatch(hl.dsp.window.move({x = math.floor(x), y = math.floor(y), window = target(window)}))
end

local function place_free(window, from_tile)
    if on_canvas() then return end
    local area = work_area(window.monitor)
    local inset = frame_info(window).top or 0
    area.y, area.h = area.y + inset, math.max(1, area.h - inset)
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
    if from_tile or w > area.w or h > area.h then
        w, h = math.min(w, area.w * 0.8), math.min(h, area.h * 0.8)
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
end

hl.on("window.open", function(window)
    if not window or not window.monitor or not window.workspace or window.workspace.special or not window.floating or (window.fullscreen or 0) ~= 0 or not uses_free_placement(window) then
        return
    end
    local native = hl.plugin and hl.plugin.velora
    if not native or not native.regular or native.regular(window.address) then
        pcall(function() hl.dispatch(hl.dsp.window.tag({ tag = "+" .. TAG, window = target(window) })) end)
    end
    place_free(window, false)
end)

-- Keep normal geometry across client-driven F11 and maximize requests. Only windows
-- floated by this mode are repaired when a client returns from fullscreen tiled.
local free_geometry, was_full = {}, {}
local function tagged_free(window)
    for _, tag in ipairs(window.tags or {}) do
        if tag == TAG or tag == TAG .. "*" then return true end
    end
    return false
end
local function capture_free(window)
    if window and window.floating and (window.fullscreen or 0) == 0 and is_main_window(window) then
        free_geometry[window.address] = geometry(window)
    end
end
hl.on("window.active", capture_free)
hl.on("window.fullscreen", function(window)
    if not window or on_canvas() or not tagged_free(window) then return end
    if (window.fullscreen or 0) ~= 0 then was_full[window.address] = true; return end
    if not was_full[window.address] then return end
    was_full[window.address] = nil
    if not window.floating then M.recover_free(window) end
end)

function M.recover_free(window)
    if not window or on_canvas() or window.floating or not tagged_free(window) or (window.fullscreen or 0) ~= 0 then return false end
    hl.dispatch(hl.dsp.window.float({action = "set", window = target(window)}))
    local box = free_geometry[window.address]
    if box then place(window, box.x, box.y, box.w, box.h) else place_free(window, true) end
    return true
end

function M.toggle_float()
    local window = hl.get_active_window()
    if not window then return end
    local was_floating = window.floating
    if was_floating then capture_free(window) end
    hl.dispatch(hl.dsp.window.float({action = was_floating and "unset" or "set", window = target(window)}))
    hl.dispatch(hl.dsp.window.tag({tag = (was_floating and "-" or "+") .. TAG, window = target(window)}))
end

-- Snapped windows remember where they were, so the opposite key puts them back
local snapped = {}
local drag, preview_timer, stop_drag

local function remember(window)
    local index = slots[window.address]
    local was_snapped = snapped[window.address]
    if on_canvas() or not window.monitor or not window.workspace or window.workspace.special or not window.floating or (window.fullscreen or 0) ~= 0 or not uses_free_placement(window) then
        return
    end
    local g = was_snapped and was_snapped.restore or geometry(window)
    local entries = remembered[window.class] or {}
    index = index or 1
    for i = #entries + 1, index - 1 do entries[i] = {} end
    remembered[window.class] = entries
    entries[index] = { x = math.floor(g.x), y = math.floor(g.y), w = math.floor(g.w), h = math.floor(g.h), monitor = window.monitor.name }
    return true
end

hl.on("window.close", function(window)
    if not window then return end
    if drag and drag.address == window.address then stop_drag() end
    if remember(window) then save() end
    free_geometry[window.address], was_full[window.address] = nil, nil
    snapped[window.address], slots[window.address] = nil, nil
end)

hl.on("config.unload", function()
    stop_drag()
    local changed = false
    for _, window in ipairs(hl.get_windows()) do
        if slots[window.address] and remember(window) then changed = true end
    end
    if changed then save() end
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

local function snap_span(origin, available, offset, fraction, gap_size, min_size, max_size)
    local start = origin + available * offset + (offset > 0 and gap_size / 2 or 0)
    local end_edge = offset + fraction
    local finish = origin + available * end_edge - (end_edge < 1 and gap_size / 2 or 0)
    local nominal = math.floor(finish - start)
    local size = math.max(math.ceil(min_size or 1), math.min(nominal, math.floor(max_size or math.huge)))
    -- A minimum-size window grows inward from the edge where it was dropped.
    local anchor = offset == 0 and 0 or (end_edge == 1 and 1 or 0.5)
    return math.max(origin, math.floor(start + (nominal - size) * anchor)), size
end

local function snap_box(window, monitor, zone)
    if zone == "maximize" then return work_area(monitor, 0) end
    local area, fraction, g = work_area(monitor), zones[zone], gap()
    local info = on_canvas() and {} or frame_info(window)
    local inset = info.top or 0
    local x, w = snap_span(area.x, area.w, fraction[1], fraction[3], g, info.min_w, info.max_w)
    local y, h = snap_span(area.y, area.h, fraction[2], fraction[4], g,
        (info.min_h or 1) + inset, info.max_h and info.max_h + inset)
    return {x = x, y = y, w = w, h = h}, inset
end

-- Puts a window (the active one, or `address`) into a zone of its monitor
function M.snap(zone, address, monitor)
    local window = find(address)
    if not window or not zones[zone] then
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
    local box, inset = snap_box(window, monitor or (on_canvas() and hl.get_active_monitor() or window.monitor), zone)
    local previous = snapped[window.address]
    snapped[window.address] = { zone = zone, restore = previous and previous.restore or geometry(window) }
    place(window, box.x, box.y + inset, box.w, math.max(1, box.h - inset))
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
        capture_free(window)
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

-- Compare geometry across a real pointer gesture. A click or a resize at the edge
-- must not snap the window. Transparent binds leave client title bars interactive.
local last_preview = ""
local function preview(window, monitor, zone)
    local message = ""
    if zone then
        local box = snap_box(window, monitor, zone)
        local width, height = monitor_size(monitor)
        message = string.format("%s,%d,%d,%d,%d,%d,%d", monitor.name, width, height,
            box.x - monitor.x, box.y - monitor.y, box.w, box.h)
    end
    if message == last_preview then return end
    last_preview = message
    hl.dispatch(hl.dsp.event("velora-snap-preview:" .. message))
end

stop_drag = function()
    drag = nil
    preview_timer:set_enabled(false)
    preview()
end

local function drag_target(start)
    local window, cursor = hl.get_active_window(), hl.get_cursor_pos()
    if not window or window.address ~= start.address or not window.floating or not cursor then return end
    local box = geometry(window)
    local distance = math.abs(cursor.x - start.start.x) + math.abs(cursor.y - start.start.y)
    if start.fullscreen ~= 0 then
        if (window.fullscreen or 0) ~= 0 or distance < 8 then return end
        -- Restoring the previous size is part of this move. It is still eligible for snapping.
        start.fullscreen, start.box, start.restored = 0, box, true
    end
    if box.w ~= start.box.w or box.h ~= start.box.h then
        start.resized = true
        return window
    end
    if start.resized or distance < 8
        or (not start.restored and math.abs(box.x - start.box.x) + math.abs(box.y - start.box.y) < 8) then return end
    local monitor = hl.get_monitor_at_cursor()
    if not monitor then return window end
    local area = work_area(monitor)
    local side = cursor.x <= area.x + 8 and "left" or (cursor.x >= area.x + area.w - 8 and "right")
    local top = cursor.y <= area.y + 8
    if side then
        local corner = top and "top-" or (cursor.y >= area.y + area.h - 8 and "bottom-" or "")
        return window, monitor, corner .. side
    end
    return window, monitor, top and "maximize" or nil
end

preview_timer = hl.timer(function()
    if not drag then return end
    local window, monitor, zone = drag_target(drag)
    preview(window, monitor, zone)
end, {timeout = 32, type = "repeat"})
preview_timer:set_enabled(false)

function M.press()
    stop_drag()
    if on_canvas() then return end
    local window, cursor = hl.get_active_window(), hl.get_cursor_pos()
    if window and window.monitor and cursor then M.recover_free(window) end
    if window and window.monitor and window.floating and cursor then
        drag = {address = window.address, monitor = window.monitor.name, start = cursor,
            box = geometry(window), fullscreen = window.fullscreen or 0}
        preview_timer:set_enabled(true)
    end
end

function M.release()
    if not drag then return end
    local start = drag
    local window, monitor, zone = drag_target(start)
    capture_free(window)
    stop_drag()
    if not window then return end
    if zone == "maximize" then
        if window.monitor.name ~= monitor.name then
            hl.dispatch(hl.dsp.window.move({monitor = monitor.name, window = target(window)}))
        end
        if start.monitor == monitor.name then
            local restore = snapped[window.address] and snapped[window.address].restore or start.box
            place(window, restore.x, restore.y, restore.w, restore.h)
        end
        keep_title_visible(window, monitor)
        snapped[window.address] = nil
        if not maximized(window) then M.toggle_maximize(window.address) end
    elseif zone then
        local restore = snapped[window.address] and snapped[window.address].restore or start.box
        M.snap(zone, window.address, monitor)
        snapped[window.address].restore = restore
    else
        snapped[window.address] = nil
        keep_title_visible(window, monitor)
    end
end

hl.on("monitor.layout_changed", function()
    for _, window in ipairs(hl.get_windows()) do
        if (not drag or drag.address ~= window.address) and is_main_window(window) then keep_title_visible(window) end
    end
end)

-- Use the app's remembered free geometry when returning from tiling.
hl.on("config.reloaded", function()
    for _, window in ipairs(hl.get_windows()) do
        if window.workspace and not window.workspace.special and uses_free_placement(window) then
            slot_for(window)
        end
        if window.workspace and not window.floating and not window.workspace.special
            and (window.fullscreen or 0) == 0 and uses_free_placement(window) then
            hl.dispatch(hl.dsp.window.float({ action = "set", window = target(window) }))
            place_free(window, true)
            pcall(function() hl.dispatch(hl.dsp.window.tag({ tag = "+" .. TAG, window = target(window) })) end)
        elseif is_main_window(window) then
            keep_title_visible(window)
        end
    end
end)

M.TAG = TAG
return M
