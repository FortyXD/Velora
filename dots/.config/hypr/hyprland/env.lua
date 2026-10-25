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

-- Virtual environment
hl.env("ILLOGICAL_IMPULSE_VIRTUAL_ENV", home .. "/.local/state/quickshell/.venv")
