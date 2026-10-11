local h = require("hyprland.helpers")
local M = {}

-- Binds with a `description` show up in the cheat sheet under "Your shortcuts".
-- Simple app shortcuts are easier to add in Settings > Keyboard Shortcuts.
function M.setup(api)
    local bind = api.bind or h.bind
    local unbind = api.unbind or h.unbind
    local exec = api.exec or h.exec

    -- User helpers.
    bind("Ctrl+Super", "Slash", exec([=[xdg-open ~/.config/illogical-impulse/config.json]=]), {
        id = "custom.edit_shell_config",
        description = "Edit the shell config file",
    })
    bind("Ctrl+Super+Alt", "Slash", exec([=[xdg-open ~/.config/hypr/custom/keybinds.lua]=]), {
        id = "custom.edit_keybinds",
        description = "Edit your keybinds file",
    })
end

return M
