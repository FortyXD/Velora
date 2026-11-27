local h = require("hyprland.helpers")

-- Not started here (power): the GeoClue agent is started by the weather service when GPS is used,
-- EasyEffects by its quick toggle.
local commands = {
    [=[~/.config/hypr/custom/scripts/__restore_video_wallpaper.sh]=],
    [=[gnome-keyring-daemon --start --components=secrets]=],
    [=[hypridle]=],
    [=[dbus-update-activation-environment --all]=],
    [=[sleep 1 && dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP]=],
    [=[if [ -d /usr/share/icons/Bibata-Modern-Classic ] || [ -d "${XDG_DATA_HOME:-$HOME/.local/share}/icons/Bibata-Modern-Classic" ] || [ -d "$HOME/.icons/Bibata-Modern-Classic" ]; then hyprctl setcursor Bibata-Modern-Classic 24; else hyprctl setcursor breeze_cursors 24; fi]=],
    [=[command -v kando >/dev/null 2>&1 && kando]=],
}

local M = {}
function M.start_shell()
    hl.exec_cmd(h.expand([=["${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprland/scripts/start-shell.sh" "$qsConfig"]=]))
end

hl.on("hyprland.start", function()
    M.start_shell()
    for _, command in ipairs(commands) do
        hl.exec_cmd(h.expand(command))
    end
end)

return M
