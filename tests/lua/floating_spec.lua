-- hyprland/modes/floating.lua against a stand-in for Hyprland's `hl`: windows, one monitor, and a
-- record of what was dispatched. Run by tests/test_window_modes.py with lua5.4.
local state_dir = os.getenv("VELORA_TEST_STATE")

local handlers, dispatched, rules = {}, {}, {}
local monitor = { name = "DP-1", x = 0, y = 0, width = 2000, height = 1200, scale = 1,
    reserved = { top = 40, left = 0, bottom = 0, right = 0 } }
local workspace = { id = 1, name = "1", special = false }
local windows = {}

local function window(address, class, x, y, w, h)
    local entry = { address = address, class = class, floating = true, fullscreen = 0, pinned = false, mapped = true,
        at = { x = x, y = y }, size = { x = w, y = h }, workspace = workspace, monitor = monitor, tags = {} }
    windows[#windows + 1] = entry
    return entry
end

local function by_address(selector)
    local address = selector and selector:match("^address:(.*)$")
    for _, entry in ipairs(windows) do
        if entry.address == address then
            return entry
        end
    end
end

local active
local function dispatcher(kind)
    return function(args) return { kind = kind, args = args or {} } end
end

hl = {
    window_rule = function(rule) rules[#rules + 1] = rule end,
    on = function(event, fn) handlers[event] = fn end,
    get_config = function(name) if name == "general:gaps_out" then return { top = 10 } end end,
    get_windows = function() return windows end,
    get_active_window = function() return active end,
    get_active_workspace = function() return workspace end,
    dispatch = function(action)
        dispatched[#dispatched + 1] = action
        -- Apply what the module relies on afterwards
        local target = by_address(action.args.window) or active
        if action.kind == "resize" and target then
            target.size = { x = action.args.x, y = action.args.y }
        elseif action.kind == "move" and target and action.args.x then
            target.at = { x = action.args.x, y = action.args.y }
        elseif action.kind == "move" and target and action.args.workspace then
            local name = action.args.workspace
            target.workspace = { id = tonumber(name) or -99, name = name, special = name:match("^special:") ~= nil }
        elseif action.kind == "fullscreen" and target then
            target.fullscreen = target.fullscreen == 0 and 1 or 0
        elseif action.kind == "float" and target then
            target.floating = action.args.action ~= "unset"
        end
    end,
    dsp = {
        focus = dispatcher("focus"),
        event = dispatcher("event"),
        window = {
            resize = dispatcher("resize"), move = dispatcher("move"), float = dispatcher("float"),
            fullscreen = dispatcher("fullscreen"), tag = dispatcher("tag"),
        },
    },
}
os.getenv = (function(get)
    return function(name)
        if name == "XDG_STATE_HOME" then return state_dir end
        return get(name)
    end
end)(os.getenv)

local free = require("hyprland.modes.floating")

local failures = 0
local function check(name, condition, detail)
    if not condition then
        failures = failures + 1
        print("FAIL " .. name .. (detail and (": " .. detail) or ""))
    else
        print("ok   " .. name)
    end
end
local function geometry(w)
    return string.format("%d,%d %dx%d", w.at.x, w.at.y, w.size.x, w.size.y)
end

check("every window floats", rules[1].float == true and rules[1].match.class == ".*")

-- Work area: x 10..1990, y 50..1190 (bar 40 on top, gaps 10): 1980 x 1140
local editor = window("0x1", "editor", 300, 300, 800, 600)
active = editor
free.left()
check("Super+Left snaps to the left half", geometry(editor) == "10,50 985x1140", geometry(editor))
free.up()
check("then Super+Up the top-left quarter", geometry(editor) == "10,50 985x565", geometry(editor))
free.down()
check("Super+Down from there back to the half", geometry(editor) == "10,50 985x1140", geometry(editor))
free.right()
check("the opposite key puts it back where it was", geometry(editor) == "300,300 800x600", geometry(editor))

free.up()
check("Super+Up maximizes a free window", editor.fullscreen == 1)
free.down()
check("Super+Down restores it", editor.fullscreen == 0)
free.down()
check("and minimizes it next", editor.workspace.name == "special:minimized")
free.restore("0x1")
check("restoring brings it back here", editor.workspace.id == 1)

-- Desktop: everything away and back
local terminal = window("0x2", "terminal", 100, 100, 600, 400)
free.show_desktop()
check("show desktop hides every window", editor.workspace.name == "special:desktop" and terminal.workspace.name == "special:desktop")
free.show_desktop()
check("and brings them back", editor.workspace.id == 1 and terminal.workspace.id == 1)

-- Remembered on close, reopened there
handlers["window.close"](terminal)
for index, entry in ipairs(windows) do
    if entry == terminal then table.remove(windows, index) end
end
local file = io.open(state_dir .. "/velora/window-geometry.lua")
check("closing writes where the app was", file ~= nil)
if file then file:close() end
local reopened = window("0x3", "terminal", 700, 400, 600, 400)
handlers["window.open"](reopened)
check("its next window opens there", geometry(reopened) == "100,100 600x400", geometry(reopened))

-- A new app opens centered; a second window in the same spot steps aside
local first = window("0x4", "files", 0, 0, 1000, 600)
handlers["window.open"](first)
check("a new app opens centered", geometry(first) == "500,320 1000x600", geometry(first))
local second = window("0x5", "files", 0, 0, 1000, 600)
handlers["window.open"](second)
check("the next one cascades", geometry(second) == "532,352 1000x600", geometry(second))

-- Too big for the screen: shrunk to fit
local huge = window("0x6", "viewer", 0, 0, 4000, 3000)
handlers["window.open"](huge)
check("an oversized window fits the work area", huge.size.x <= 1980 and huge.size.y <= 1140, geometry(huge))

-- Dialogs and popups are left alone
local dialog = window("0x7", "editor", 5, 5, 300, 150)
local before = #dispatched
handlers["window.open"](dialog)
check("small windows aren't placed", #dispatched == before)

os.exit(failures == 0 and 0 or 1)
