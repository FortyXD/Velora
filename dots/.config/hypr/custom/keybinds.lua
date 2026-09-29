local h = require("hyprland.helpers")
local M = {}

function M.setup(api)
    local bind = api.bind or h.bind
    local unbind = api.unbind or h.unbind
    local exec = api.exec or h.exec

    -- User helpers.
    bind("Ctrl+Super", "Slash", exec([=[xdg-open ~/.config/illogical-impulse/config.json]=])) -- Edit shell config
    bind("Ctrl+Super+Alt", "Slash", exec([=[xdg-open ~/.config/hypr/custom/keybinds.lua]=])) -- Edit extra keybinds

    -- Keep Super+B dedicated to the browser.
    unbind("Super", "B")
    bind("Super", "B", exec([=[brave]=])) -- Launch Brave

    -- Open the tuned Kitty + zsh + Starship setup.
    unbind("SUPER", "RETURN")
    bind("SUPER", "RETURN", exec("$terminal")) -- Terminal
end

return M
