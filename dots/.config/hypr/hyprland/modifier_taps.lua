-- Modifier-only shortcuts run on a clean release, never after using another key.
-- Native release binds retain Hyprland's submap and session-lock filtering.
local h = require("hyprland.helpers")
local M = {}
local names = {
    Super = { "Super_L", "Super_R" }, Ctrl = { "Control_L", "Control_R" },
    Alt = { "Alt_L", "Alt_R" }, Shift = { "Shift_L", "Shift_R" },
}
local codes = { [37] = "Ctrl", [105] = "Ctrl", [50] = "Shift", [62] = "Shift",
    [64] = "Alt", [108] = "Alt", [133] = "Super", [134] = "Super" }

function M.kind(key)
    for kind, keys in pairs(names) do
        if key == kind or key == keys[1] or key == keys[2] then return kind end
    end
end

function M.new()
    local self = { held = {}, taps = {}, armed = {}, dirty = false }
    function self:cancel()
        self.armed = {}
        self.dirty = next(self.held) ~= nil
    end
    local function canvas_gesture()
        local native = hl.plugin and hl.plugin.velora
        return native and native.take_gesture and native.take_gesture()
    end
    hl.on("input.keyboard.key", function(code, _, pressed)
        if pressed == 1 then
            if self.held[code] then return end -- Ignore autorepeat
            if codes[code] == "Super" then canvas_gesture() end
            self.held[code] = true
            self.armed = {}
            if not codes[code] then self.dirty = true end
            if self.dirty then return end
            local held = {}
            for keycode in pairs(self.held) do held[codes[keycode] or "other"] = true end
            for _, tap in ipairs(self.taps) do
                local matches = true
                for kind in pairs(held) do if not tap.mods[kind] then matches = false end end
                for kind in pairs(tap.mods) do if not held[kind] then matches = false end end
                if matches then self.armed[tap] = true end
            end
        else
            self.held[code] = nil
            if next(self.held) == nil then self.dirty = false end
        end
    end)
    hl.on("keybinds.submap", function()
        self.held = {}; self.armed = {}; self.dirty = false
    end)
    function self:bind(mods, key, dispatcher, options)
        local tap = { mods = { [M.kind(key)] = true } }
        for _, mod in ipairs(mods) do tap.mods[mod] = true end
        self.taps[#self.taps + 1] = tap
        local release_options = {}
        for name, value in pairs(options) do release_options[name] = value end
        release_options.release = true
        release_options.ignore_mods = true
        release_options.transparent = true
        release_options.non_consuming = true
        release_options.repeating = nil
        local function released()
            if tap.mods.Super and canvas_gesture() then self:cancel(); return end
            if not self.armed[tap] then return end
            self.armed[tap] = nil
            if type(dispatcher) == "function" then dispatcher() else hl.dispatch(dispatcher) end
        end
        -- Releasing either half of a chord commits it, regardless of press order.
        for kind in pairs(tap.mods) do
            for _, physical_key in ipairs(names[kind]) do h.bind("", physical_key, released, release_options) end
        end
    end
    return self
end
return M
