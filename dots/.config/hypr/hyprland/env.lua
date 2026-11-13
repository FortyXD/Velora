local home = os.getenv("HOME") or "/home/andrey"

-- Wayland
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- Applications
hl.env("XDG_DATA_DIRS", home .. "/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share")

-- Video in Qt apps (the shell's lock screen and previews, the settings app): VA-API only. Qt probes the
-- hardware encoders as soon as it plays anything, and probing CUDA wakes a hybrid laptop's NVIDIA GPU
-- (or, once that GPU has crashed, hangs the app); both variables are needed to keep it away.
hl.env("QT_FFMPEG_DECODING_HW_DEVICE_TYPES", "vaapi")
hl.env("QT_FFMPEG_ENCODING_HW_DEVICE_TYPES", "vaapi")

-- Themes
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "kde")
hl.env("XDG_MENU_PREFIX", "plasma-")

-- Match the per-user daemon configured by the installer; do not share a /tmp socket.
local runtime = os.getenv("XDG_RUNTIME_DIR")
if runtime then
    hl.env("YDOTOOL_SOCKET", runtime .. "/ydotool.sock")
end

-- Virtual environment
local state_home = os.getenv("XDG_STATE_HOME")
if not state_home or state_home == "" then
    state_home = home .. "/.local/state"
end
hl.env("ILLOGICAL_IMPULSE_VIRTUAL_ENV", state_home .. "/quickshell/.venv")

-- Velora's own generic Qt addon, scoped to this session. It leaves KIO operations intact.
local qt_plugins = (os.getenv("XDG_DATA_HOME") or (home .. "/.local/share")) .. "/velora/qt6/plugins"
local plugin_file = io.open(qt_plugins .. "/generic/libvelora-file-dialog.so", "rb")
if plugin_file then
    plugin_file:close()
    local existing_paths = os.getenv("QT_PLUGIN_PATH") or ""
    hl.env("QT_PLUGIN_PATH", qt_plugins .. (existing_paths ~= "" and (":" .. existing_paths) or ""))
    local existing_plugins = os.getenv("QT_QPA_GENERIC_PLUGINS") or ""
    if not existing_plugins:find("velora-file-dialog", 1, true) then
        existing_plugins = existing_plugins .. (existing_plugins ~= "" and "," or "") .. "velora-file-dialog"
    end
    hl.env("QT_QPA_GENERIC_PLUGINS", existing_plugins)
end
