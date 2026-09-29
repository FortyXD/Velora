local h = require("hyprland.helpers")

local commands = {
    [=[~/.config/hypr/hyprland/scripts/start_geoclue_agent.sh]=],
    [=[qs -c $qsConfig &]=],
    [=[~/.config/hypr/custom/scripts/__restore_video_wallpaper.sh]=],
    [=[gnome-keyring-daemon --start --components=secrets]=],
    [=[hypridle]=],
    [=[dbus-update-activation-environment --all]=],
    [=[sleep 1 && dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP]=],
    [=[easyeffects --hide-window --service-mode]=],
    [=[wl-paste --type text --watch bash -c 'cliphist store && qs -c $qsConfig ipc call cliphistService update']=],
    [=[wl-paste --type image --watch bash -c 'cliphist store && qs -c $qsConfig ipc call cliphistService update']=],
    [=[hyprctl setcursor Bibata-Modern-Classic 24]=],
    [=[kando]=],
}

hl.on("hyprland.start", function()
    for _, command in ipairs(commands) do
        hl.exec_cmd(h.expand(command))
    end
end)
