-- Hyprland 0.55+ Lua configuration.

require("hyprland.env")
require("custom.env")

local variables = require("custom.variables")

if not variables.dont_load_default_execs then
    require("hyprland.execs")
end

if not variables.dont_load_default_general then
    require("hyprland.general")
end

if not variables.dont_load_default_rules then
    require("hyprland.rules")
end

if not variables.dont_load_default_colors then
    require("hyprland.colors")
end

if not variables.dont_load_default_keybinds then
    require("hyprland.keybinds")
end

require("custom.execs")
require("custom.general")
require("custom.rules")

-- Options changed in the settings app (Super+I). Generated, see custom/shell_settings.lua.
pcall(require, "custom.shell_settings")

-- nwg-displays compatibility files, converted to Lua.
require("workspaces")
require("monitors")
-- Displays changed in the settings app. Generated, see custom/monitors.lua.
pcall(require, "custom.monitors")

require("hyprland.shellOverrides.main")
