local h = require("hyprland.helpers")

-- Not started here (power): the GeoClue agent is started by the weather service when GPS is used,
-- EasyEffects by its quick toggle.
local commands = {
    [=[qs -c $qsConfig &]=],
    [=[~/.config/hypr/custom/scripts/__restore_video_wallpaper.sh]=],
    [=[gnome-keyring-daemon --start --components=secrets]=],
    [=[hypridle]=],
    [=[dbus-update-activation-environment --all]=],
    [=[sleep 1 && dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP]=],
    [=[wl-paste --type text --watch bash -c 'cliphist store && qs -c $qsConfig ipc call cliphistService update']=],
    [=[wl-paste --type image --watch bash -c 'cliphist store && qs -c $qsConfig ipc call cliphistService update']=],
    [=[if [ -d /usr/share/icons/Bibata-Modern-Classic ] || [ -d "${XDG_DATA_HOME:-$HOME/.local/share}/icons/Bibata-Modern-Classic" ] || [ -d "$HOME/.icons/Bibata-Modern-Classic" ]; then hyprctl setcursor Bibata-Modern-Classic 24; else hyprctl setcursor breeze_cursors 24; fi]=],
    [=[command -v kando >/dev/null 2>&1 && kando]=],
}

hl.on("hyprland.start", function()
    for _, command in ipairs(commands) do
        hl.exec_cmd(h.expand(command))
    end
end)
