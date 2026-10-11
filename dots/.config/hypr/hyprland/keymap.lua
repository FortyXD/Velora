-- Keybind registry shared by the default and custom keybinds.
--
-- Binds with an `id` option can be remapped or turned off from the settings app, which
-- writes custom/keybind_overrides.lua. Binds with a `description` are listed in a JSON
-- manifest ($XDG_RUNTIME_DIR/folis-keybinds.json) that the cheat sheet (Super+/) and the
-- settings app read, so both always show what is actually bound.
local h = require("hyprland.helpers")

local M = {}

M.manifest_path = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/folis-keybinds.json"
M.capture_submap = "shortcut-capture"

local MOD_ORDER = { "SUPER", "CTRL", "ALT", "SHIFT" }
local MOD_NAMES = { SUPER = "Super", CTRL = "Ctrl", ALT = "Alt", SHIFT = "Shift" }
local MOD_ALIASES = { WIN = "SUPER", MOD4 = "SUPER", LOGO = "SUPER", CONTROL = "CTRL", MOD1 = "ALT" }
-- Options only this module understands; everything else goes to hl.bind
local OWN_OPTIONS = { id = true, custom = true }

local state

-- Starts a fresh registry and reads the overrides again. Called once per config load.
function M.begin()
    state = {
        groups = {},
        group_order = {},
        group = nil,
        entries = {},
        entry_order = {},
        hidden = {},
        remap = {},
        custom = {},
    }
    package.loaded["custom.keybind_overrides"] = nil
    local ok, overrides = pcall(require, "custom.keybind_overrides")
    if ok and type(overrides) == "table" then
        state.remap = type(overrides.remap) == "table" and overrides.remap or {}
        state.custom = type(overrides.custom) == "table" and overrides.custom or {}
    end
end

-- "ctrl+SUPER" -> { "Super", "Ctrl" }
function M.mods_list(mods)
    local present = {}
    for part in (mods or ""):upper():gmatch("[^+%s]+") do
        present[MOD_ALIASES[part] or part] = true
    end
    local list = {}
    for _, mod in ipairs(MOD_ORDER) do
        if present[mod] then
            list[#list + 1] = MOD_NAMES[mod]
        end
    end
    return list
end

local function combo(mods, key)
    return table.concat(M.mods_list(mods), "+"):upper() .. "|" .. tostring(key):upper()
end

-- Following binds belong to this group until the next call
function M.group(id, name, icon)
    if not state.groups[id] then
        state.groups[id] = { id = id, name = name, icon = icon or "keyboard" }
        state.group_order[#state.group_order + 1] = id
    end
    state.group = id
end

local function record(key_id, fields)
    local entry = state.entries[key_id]
    if not entry then
        entry = { group = state.group or "other" }
        state.entries[key_id] = entry
        state.entry_order[#state.entry_order + 1] = key_id
    end
    for name, value in pairs(fields) do
        if entry[name] == nil then
            entry[name] = value
        end
    end
    return entry
end

-- Wraps `bind_fn(mods, key, dispatcher, options)` so it understands `id`, applies the
-- user's remaps and records described binds for the manifest.
function M.binder(bind_fn)
    return function(mods, key, dispatcher, options)
        options = options or {}
        local id = options.id
        local description = options.description
        local default_mods, default_key = mods, key
        local remap = id and state.remap[id]
        local disabled = remap == false
        if type(remap) == "table" and remap.key then
            mods, key = remap.mods or "", remap.key
        end

        if not id and not description then
            -- Undescribed binds aren't listed, but recording a shortcut must not collide with them
            if key ~= "Super_L" and key ~= "Super_R" then
                state.hidden[combo(mods, key)] = true
            end
        else
            local entry = record(id or ("fixed:" .. combo(default_mods, default_key)), {
                id = id,
                remappable = id ~= nil and not options.custom,
                custom = options.custom,
                mods = M.mods_list(mods),
                key = key,
                default_mods = M.mods_list(default_mods),
                default_key = default_key,
                combo = combo(mods, key),
                disabled = disabled,
                remapped = type(remap) == "table",
                locked = options.locked == true,
            })
            if description and not entry.description then
                entry.description = description
            end
        end

        if disabled then
            return nil
        end
        local hl_options = {}
        for name, value in pairs(options) do
            if not OWN_OPTIONS[name] then
                hl_options[name] = value
            end
        end
        return bind_fn(mods, key, dispatcher, hl_options)
    end
end

-- Wraps `unbind_fn(mods, key)` so unbound keys also leave the manifest
function M.unbinder(unbind_fn)
    return function(mods, key)
        local target = combo(mods, key)
        state.hidden[target] = nil
        for _, entry in pairs(state.entries) do
            if entry.combo == target then
                entry.removed = true
            end
        end
        return unbind_fn(mods, key)
    end
end

-- A row for the cheat sheet that isn't a single bind, like Super+1…0
function M.note(mods, key, description)
    record("note:" .. combo(mods, key) .. ":" .. description, {
        mods = M.mods_list(mods),
        key = key,
        description = description,
        combo = combo(mods, key),
        note = true,
    })
end

-- Shortcuts added in the settings app: launch an app or run a command
function M.bind_custom(bind)
    for index, shortcut in ipairs(state.custom) do
        local command = shortcut.command
        if shortcut.app and shortcut.app ~= "" then
            command = "~/.config/hypr/hyprland/scripts/default_apps.py open " .. string.format("%q", shortcut.app)
        end
        if command and command ~= "" and shortcut.key and shortcut.key ~= "" then
            bind(shortcut.mods or "", shortcut.key, h.exec(command), {
                id = "custom:" .. index,
                custom = true,
                description = shortcut.description or command,
            })
        end
    end
end

local function json(value)
    local kind = type(value)
    if kind == "string" then
        return '"' .. value:gsub('[%c"\\]', function(char)
            local escapes = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\t"] = "\\t" }
            return escapes[char] or string.format("\\u%04x", char:byte())
        end) .. '"'
    elseif kind == "number" or kind == "boolean" then
        return tostring(value)
    elseif kind == "table" then
        local parts = {}
        if #value > 0 or next(value) == nil then
            for _, item in ipairs(value) do
                parts[#parts + 1] = json(item)
            end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        local names = {}
        for name in pairs(value) do
            names[#names + 1] = name
        end
        table.sort(names)
        for _, name in ipairs(names) do
            parts[#parts + 1] = json(tostring(name)) .. ":" .. json(value[name])
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
end

-- Writes everything recorded since begin() for the cheat sheet and the settings app
function M.write_manifest()
    local groups, binds, hidden = {}, {}, {}
    for _, id in ipairs(state.group_order) do
        groups[#groups + 1] = state.groups[id]
    end
    for _, key_id in ipairs(state.entry_order) do
        local entry = state.entries[key_id]
        if entry.description and not entry.removed then
            binds[#binds + 1] = entry
        end
    end
    for hidden_combo in pairs(state.hidden) do
        hidden[#hidden + 1] = hidden_combo
    end
    table.sort(hidden)
    local temp_path = M.manifest_path .. ".tmp"
    local file = io.open(temp_path, "w")
    if not file then
        return
    end
    file:write(json({ groups = groups, binds = binds, hidden = hidden }), "\n")
    file:close()
    os.rename(temp_path, M.manifest_path)
end

return M
