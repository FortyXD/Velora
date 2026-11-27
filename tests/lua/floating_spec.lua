-- hyprland/modes/floating.lua against a stand-in for Hyprland's `hl`: windows, one monitor, and a
-- record of what was dispatched. Run by tests/test_window_modes.py with lua5.4.
local state_dir = os.getenv("VELORA_TEST_STATE")

local handlers, dispatched, rules = {}, {}, {}
local bind_options
local timer
local monitor = { name = "DP-1", x = 0, y = 0, width = 2000, height = 1200, scale = 1,
    reserved = { top = 40, left = 0, bottom = 0, right = 0 } }
local monitors = {monitor}
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
    config = function(config) bind_options = config.binds end,
    window_rule = function(rule) rules[#rules + 1] = rule end,
    on = function(event, fn) handlers[event] = fn end,
    timer = function(callback)
        timer = {tick = callback, set_enabled = function(self, enabled) self.enabled = enabled end}
        return timer
    end,
    get_config = function(name) if name == "general:gaps_out" then return { top = 10 } end end,
    get_windows = function() return windows end,
    get_monitors = function() return monitors end,
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

do
    local code = window("0xc", "com.microsoft.VSCode", 50, 60, 700, 480)
    code.tags = {"velora-free"}
    handlers["window.active"](code)
    code.fullscreen = 2
    handlers["window.fullscreen"](code)
    code.fullscreen, code.floating, code.size = 0, false, {x=1900,y=1100}
    handlers["window.fullscreen"](code)
    check("F11 restores a tagged editor to its free geometry", code.floating and geometry(code) == "50,60 700x480")
    code.tags, code.floating = {}, false
    check("a deliberately tiled editor stays tiled", not free.recover_free(code) and not code.floating)
    table.remove(windows)
end

check("every window floats", rules[1].float == true and rules[1].match.class == ".*")
check("restoring by drag preserves the title grab point", bind_options.drag_center_window == false)

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
check("and minimizes it next", editor.workspace.name == "special:velora-min-31")
free.restore("0x1")
check("restoring brings it back here", editor.workspace.id == 1)

-- Desktop: everything away and back
local terminal = window("0x2", "terminal", 100, 100, 600, 400)
free.show_desktop()
check("show desktop hides every window", editor.workspace.name == "special:velora-desktop-31" and terminal.workspace.name == "special:velora-desktop-31")
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

local settings = window("0x8", "org.velora.Settings", 500, 320, 1000, 600)
handlers["window.open"](settings)
check("Settings keeps its centered position and is not tagged for tiling", #dispatched == before)

local other = window("0x9", "notes", 20, 20, 600, 400)
other.workspace = { id = 7, name = "7", special = false }
free.minimize(other.address)
package.loaded["hyprland.window_actions"] = nil
local reloaded = require("hyprland.window_actions")
reloaded.restore(other.address)
check("restore on another workspace after reload", other.workspace.id == 7)
local scratch = window("0xa", "scratch", 0, 0, 400, 200)
scratch.workspace = { id = -90, name = "special:scratch", special = true }
reloaded.restore(scratch.address)
check("a scratchpad keeps its workspace", scratch.workspace.name == "special:scratch")
local count = #dispatched
reloaded.minimize("0xdeadbeef")
check("a closed address never minimizes the focused window", #dispatched == count)
local docA = window("0xb", "documents", 0, 0, 500, 300)
local docB = window("0xc", "documents", 0, 0, 500, 300)
local docC = window("0xd", "documents", 0, 0, 500, 300)
handlers["window.open"](docA)
handlers["window.open"](docB)
handlers["window.open"](docC)
docA.at, docB.at = {x=70, y=80}, {x=940, y=260}
handlers["window.close"](docA)
docC.at = {x=1380, y=140}
handlers["window.close"](docC)
local partial = assert(loadfile(state_dir .. "/velora/window-geometry.lua"))().documents
check("a pending middle slot preserves the first and third positions", partial[1].x == 70 and partial[2].x == nil and partial[3].x == 1380)
handlers["window.close"](docB)
local savedSlots = assert(loadfile(state_dir .. "/velora/window-geometry.lua"))().documents
check("independent geometry slots survive closing out of order", savedSlots[1].x == 70 and savedSlots[2].x == 940 and savedSlots[3].x == 1380)
other.workspace = { id=nil, name="work", addressable_name="work", special=false }
reloaded.minimize(other.address)
reloaded.restore(other.address)
check("named workspaces recover their addressable selector", other.workspace.name == "name:work")
-- A scaled monitor to the left of the primary has negative layout coordinates.
monitor.x, monitor.y, monitor.width, monitor.height, monitor.scale = -1280, 100, 1920, 1080, 1.5
monitor.mode = { width = 1280, height = 720 }
local pointer = {x=-600, y=460}
hl.get_cursor_pos = function() return pointer end
hl.get_monitor_at_cursor = function() return monitor end
active = window("0xf", "scale-test", -850, 310, 600, 400)
local prefix = "velora-snap-preview:"
local function previews()
    local result = {}
    for _, action in ipairs(dispatched) do
        if action.kind == "event" and action.args:sub(1, #prefix) == prefix then
            result[#result + 1] = action.args:sub(#prefix + 1)
        end
    end
    return result
end
check("no preview timer while idle", not timer.enabled)
free.press()
pointer = {x=-1279, y=480}
timer.tick()
check("moving the pointer alone does not show a window target", #previews() == 0)
active.at = {x=-1280, y=310}
timer.tick()
check("target appears before release on the scaled output", previews()[1] == "DP-1,1280,720,10,50,625,660" and active.size.x == 600)
timer.tick()
check("same zone sends no duplicate events", #previews() == 1)
pointer = {x=-1279, y=105}
timer.tick()
check("the corner updates to a quarter", previews()[2] == "DP-1,1280,720,10,50,625,325")
pointer = {x=-600, y=460}
timer.tick()
check("leaving the edge hides the target before release", previews()[3] == "")
pointer = {x=-1279, y=480}
timer.tick()
free.release()
check("edge drag uses the target monitor's logical left half", geometry(active) == "-1270,150 625x660", geometry(active))
check("dropping unmaps the preview and stops sampling", previews()[5] == "" and not timer.enabled)
free.unsnap(active)
check("restore recovers the pre-drag position", geometry(active) == "-850,310 600x400", geometry(active))
pointer = {x=-600, y=460}
free.press()
pointer, active.at = {x=-640,y=101}, {x=-891,y=151}
timer.tick()
check("top previews the maximized area below reserved panels", previews()[6] == "DP-1,1280,720,0,40,1280,680")
free.release()
check("dropping at the top maximizes", active.fullscreen == 1 and not timer.enabled)
free.down()
check("unmaximizing returns to the pre-drag position", geometry(active) == "-850,310 600x400", geometry(active))
free.press()
active.size.x = active.size.x + 20
pointer = {x=-1279,y=480}
local count_after_press = #previews()
timer.tick()
free.release()
check("a resize has no drop target", #previews() == count_after_press)
-- Drag by the body. The pointer still has room to move when the title is already offscreen.
local frame = {top=32}
hl.plugin = {velora = {frame_info = function() return frame end}}
pointer = {x=-630,y=540}
free.press()
pointer, active.at = {x=-720,y=290}, {x=-940,y=60}
free.release()
check("a body drag leaves the entire system title below the reserved panel", active.at.x == -940 and active.at.y == 172)
free.snap("left")
check("the snapped frame fits the preview including its title", active.at.y - 32 == 150 and active.size.y + 32 == 660)
free.unsnap(active)
frame.min_w, frame.min_h = 760, 500
free.snap("bottom-right")
check("a larger minimum size grows inward from the right and bottom", geometry(active) == "-770,310 760x500", geometry(active))
free.unsnap(active)
frame.min_w, frame.min_h = nil, nil
local upper = {name="DP-2", x=-1280, y=-620, mode={width=1280, height=720}}
monitors[2] = upper
active.at = {x=-900, y=55}
handlers["monitor.layout_changed"]()
check("a title accessible on an upper monitor stays there", active.at.y == 55)
monitors[2] = nil
handlers["monitor.layout_changed"]()
check("unplugging that monitor brings the title back", active.at.y == 172)
active.at = {x=-2300, y=80}
handlers["config.reloaded"]()
check("reload recovers an already stranded window", active.at.x == -1280 and active.at.y == 172)
active.fullscreen, pointer = 1, {x=-280,y=180}
free.press()
active.fullscreen, active.at, active.size = 0, {x=-1220,y=260}, {x=600,y=400}
pointer = {x=-1279,y=480}
timer.tick()
check("a restored drag can snap in the same gesture", previews()[#previews()] == "DP-1,1280,720,10,50,625,660")
free.release()
check("a restored drag drops including the frame", active.at.y == 182 and active.size.y == 628)
hl.plugin = nil
active.floating = false
active.size = {x=1900, y=1070}
handlers["config.reloaded"]()
check("a new tiled window fits on its scaled monitor after switching to free", active.floating and active.size.x <= 1008 and active.size.y <= 528)
os.exit(failures == 0 and 0 or 1)
