-- hyprland/gestures.lua against a stand-in for Hyprland's `hl`. Run by tests/test_window_modes.py.
local runtime = os.getenv("VELORA_TEST_STATE")
local registered, events = {}, {}

hl = {
    gesture = function(spec) registered[#registered + 1] = spec end,
    dispatch = function(action) if action.event then events[#events + 1] = action.event end end,
    get_windows = function() return {} end,
    dsp = {
        event = function(text) return { event = text } end,
        global = function(name) return { global = name } end,
        exec_cmd = function(command) return { command = command } end,
        window = { move = function(args) return args end, fullscreen = function(args) return args end },
        workspace = { toggle_special = function() return {} end },
    },
}
os.getenv = (function(get)
    return function(name)
        if name == "XDG_RUNTIME_DIR" then return runtime end
        return get(name)
    end
end)(os.getenv)
package.preload["custom.gesture_overrides"] = function()
    return { volume = false, overview = { action = "command", command = "kitty" } }
end

local gestures = require("hyprland.gestures")
gestures.setup()

local failures = 0
local function check(name, condition, detail)
    print((condition and "ok   " or "FAIL ") .. name .. (not condition and detail and (": " .. detail) or ""))
    if not condition then failures = failures + 1 end
end

local function find(fingers, direction, mods)
    for _, spec in ipairs(registered) do
        if spec.fingers == fingers and spec.direction == direction and spec.mods == mods then return spec end
    end
end

check("the old three-finger move stays", find(3, "swipe", nil).action == "move")
check("the old pinch to float stays", find(3, "pinch", nil).action == "float")
check("four fingers sideways still switch workspaces", find(4, "horizontal", nil).action == "workspace")
check("a gesture turned off isn't registered", find(3, "vertical", "CTRL") == nil)
check("an overridden one runs its command", type(find(4, "up", nil).action) == "function")
check("modifiers keep combinations apart", find(3, "horizontal", "ALT") ~= nil and find(4, "up", "SUPER") ~= nil)

-- Four fingers toward you: the library follows the fingers
local library = find(4, "down", nil).action
library.start({})
library.update({ delta = { x = 0, y = 160 } })
library.finish({ cancelled = false })
check("a live gesture reports its start", events[1] == "gesture:library:begin:0.000", events[1])
check("then how far it went", events[2] == "gesture:library:update:0.500", events[2])
check("then that it ended", events[3] == "gesture:library:end:0.500", events[3])

local pinch = find(4, "pinchin", nil).action
pinch.start({})
pinch.update({ scale = 0.75 })
check("a pinch reports how far it closed", events[5] == "gesture:library:update:0.500", events[5])

local file = io.open(runtime .. "/velora-gestures.json")
local manifest = file and file:read("a") or ""
if file then file:close() end
check("the list is written for the settings app", manifest:find('"id":"app_library"', 1, true) ~= nil)
check("with what each one does now", manifest:find('"action":"none"', 1, true) ~= nil and manifest:find('"default_action":"volume"', 1, true) ~= nil)

os.exit(failures == 0 and 0 or 1)
