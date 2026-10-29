#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
repo_root=${VELORA_SOURCE_ROOT:-"$repo_root"}
target_home=${VELORA_TARGET_HOME:-"$HOME"}
config_home=${XDG_CONFIG_HOME:-"$target_home/.config"}
data_home=${XDG_DATA_HOME:-"$target_home/.local/share"}
state_home=${XDG_STATE_HOME:-"$target_home/.local/state"}
backup_root=${VELORA_BACKUP_ROOT:-"$state_home/velora/backups/$(date +%Y%m%d-%H%M%S)-$$"}
dry_run=false
install_packages=false
reload_hyprland=true
desktop_integration=false
[[ $target_home != "$HOME" ]] || desktop_integration=true

usage() {
  cat <<'HELP'
Usage: ./install.sh [--dry-run] [--skip-packages] [--skip-aur] [--no-reload]

Link Velora configuration files. Use ./velora install for the complete installer.
Existing targets are moved to ~/.local/state/velora/backups/.
--dry-run        Show planned changes.
--skip-packages  Link configs without installing packages.
--skip-aur       Install only official Arch packages.
--no-reload      Skip reloading a running Hyprland session.
HELP
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=true ;;
    --skip-packages) install_packages=false ;;
    --skip-aur) : ;;
    --no-reload) reload_hyprland=false ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$arg" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ $EUID -eq 0 ]]; then
  printf 'Run this script as your normal user, not root.\n' >&2
  exit 1
fi

# Packages and the Python environment are managed by scripts/velora.py.

record_change() {
  [[ -n ${VELORA_INSTALL_JOURNAL:-} ]] || return 0
  python3 - "$VELORA_INSTALL_JOURNAL" "$1" "${2:-}" <<'PY'
import json, sys
with open(sys.argv[1], "a") as journal:
    journal.write(json.dumps({"target": sys.argv[2], "backup": sys.argv[3]}) + "\n")
PY
}

shapes="$repo_root/dots/.config/quickshell/ii/modules/common/widgets/shapes/ShapeCanvas.qml"
if [[ ! -f $shapes ]]; then
  if $dry_run; then
    printf 'Would initialize Git submodules.\n'
  else
    git -C "$repo_root" submodule update --init --recursive
    [[ -f $shapes ]] || { printf 'Quickshell shapes submodule is missing.\n' >&2; exit 1; }
  fi
fi

link_item() {
  local source=$1 target=$2 relative
  [[ -e $source ]] || { printf 'Missing source: %s\n' "$source" >&2; exit 1; }
  if [[ -L $target && $(readlink -- "$target") == "$source" ]]; then
    printf 'Already linked: %s\n' "$target"
    return
  fi
  printf 'Link %s -> %s\n' "$target" "$source"
  if $dry_run; then return; fi
  mkdir -p -- "$(dirname -- "$target")"
  if [[ -e $target || -L $target ]]; then
    if [[ $target == "$config_home/illogical-impulse" && -d $target && ! -L $target ]]; then
      for state_file in config.json installed_true installed_listfile; do
        if [[ -e $target/$state_file && ! -e $source/$state_file ]]; then
          cp -a -- "$target/$state_file" "$source/$state_file"
        fi
      done
    fi
    relative=${target#"$target_home"/}
    [[ $relative != /* ]] || relative="external/${target#/}"
    mkdir -p -- "$backup_root/$(dirname -- "$relative")"
    mv -- "$target" "$backup_root/$relative"
    record_change "$target" "$backup_root/$relative"
    printf '  Backup: %s\n' "$backup_root/$relative"
  else
    record_change "$target"
  fi
  ln -s -- "$source" "$target"
}

for name in hypr quickshell kitty foot fuzzel matugen fish fontconfig Kvantum kde-material-you-colors mpv wlogout xdg-desktop-portal zshrc.d tmux illogical-impulse; do
  link_item "$repo_root/dots/.config/$name" "$config_home/$name"
done

# Keep runtime settings local; seed a new installation from the tracked example.
shell_config="$config_home/illogical-impulse/config.json"
if [[ ! -e $shell_config && ! -L $shell_config ]]; then
  if $dry_run; then
    printf 'Would create local shell settings from config.example.json.\n'
  else
    cp -- "$repo_root/dots/.config/illogical-impulse/config.example.json" "$shell_config"
  fi
fi

# Colors and settings-app output are rewritten while the desktop runs, so they aren't tracked;
# a new checkout starts from their defaults.
seed_generated() {
  local template=$1 dest=$2
  [[ -e $template && ! -e $dest && ! -L $dest ]] || return 0
  if $dry_run; then
    printf 'Would create %s from its default\n' "$dest"
    return
  fi
  cp -- "$template" "$dest"
}
seed_generated "$repo_root/dots/.config/hypr/custom/shell_settings_default.json" "$repo_root/dots/.config/hypr/custom/shell_settings.json"
seed_generated "$repo_root/dots/.config/hypr/custom/shell_settings_default.lua" "$repo_root/dots/.config/hypr/custom/shell_settings.lua"
seed_generated "$repo_root/dots/.config/hypr/hyprland/colors_default.lua" "$repo_root/dots/.config/hypr/hyprland/colors.lua"
seed_generated "$repo_root/dots/.config/hypr/hyprlock/colors_default.conf" "$repo_root/dots/.config/hypr/hyprlock/colors.conf"
seed_generated "$repo_root/dots/.config/fuzzel/fuzzel_theme_default.ini" "$repo_root/dots/.config/fuzzel/fuzzel_theme.ini"

link_item "$repo_root/dots/.config/wireplumber/wireplumber.conf.d/51-auto-audio-routes.conf" "$config_home/wireplumber/wireplumber.conf.d/51-auto-audio-routes.conf"
link_item "$repo_root/dots/.local/share/wireplumber/scripts/folis/prefer-plugged-routes.lua" "$data_home/wireplumber/scripts/folis/prefer-plugged-routes.lua"
link_item "$repo_root/dots/.config/starship.toml" "$config_home/starship.toml"
link_item "$repo_root/home/.zshrc" "$target_home/.zshrc"
link_item "$repo_root/home/.tmux.conf" "$target_home/.tmux.conf"
link_item "$repo_root/dots/.local/share/icons/illogical-impulse.svg" "$data_home/icons/illogical-impulse.svg"
link_item "$repo_root/dots/.local/share/icons/hicolor/scalable/apps/org.velora.Settings.svg" "$data_home/icons/hicolor/scalable/apps/org.velora.Settings.svg"
link_item "$repo_root/dots/.local/share/applications/org.velora.Settings.desktop" "$data_home/applications/org.velora.Settings.desktop"
link_item "$repo_root/dots/.local/share/kxmlgui5/dolphin/dolphinui.rc" "$data_home/kxmlgui5/dolphin/dolphinui.rc"
link_item "$repo_root/dots/.local/share/folis/dolphin-create-archive.py" "$data_home/folis/dolphin-create-archive.py"
link_item "$repo_root/dots/.local/share/dbus-1/services/org.freedesktop.FileManager1.service" "$data_home/dbus-1/services/org.freedesktop.FileManager1.service"
if [[ -x /usr/local/racket/bin/drracket ]]; then
  link_item "$repo_root/dots/.local/share/applications/drracket.desktop" "$data_home/applications/drracket.desktop"
fi

# Writes a generated file from stdin, moving a different existing file to the backup
install_generated() {
  local dest=$1 tmp relative
  if $dry_run; then
    printf 'Would install %s\n' "$dest"
    cat > /dev/null
    return
  fi
  mkdir -p -- "$(dirname -- "$dest")"
  tmp=$(mktemp "${dest}.XXXXXX")
  cat > "$tmp"
  chmod 755 "$tmp"
  if [[ -e $dest || -L $dest ]]; then
    if cmp -s -- "$tmp" "$dest"; then
      rm -- "$tmp"
      return
    fi
    relative=${dest#"$target_home"/}
    [[ $relative != /* ]] || relative="external/${dest#/}"
    mkdir -p -- "$backup_root/$(dirname -- "$relative")"
    mv -- "$dest" "$backup_root/$relative"
    record_change "$dest" "$backup_root/$relative"
  else
    record_change "$dest"
  fi
  mv -- "$tmp" "$dest"
}

service_menus="$data_home/kio/servicemenus"
install_generated "$service_menus/folis-create-archive.desktop" <<EOF
[Desktop Entry]
Type=Service
Name=Compress
Name[ru]=Создать архив
MimeType=all/allfiles;inode/directory;
X-KDE-Protocols=file
X-KDE-MinNumberOfUrls=1
X-KDE-Priority=TopLevel
X-KDE-Submenu=Compress
X-KDE-Submenu[ru]=Создать архив
Actions=zip;tarGz;

[Desktop Action zip]
Name=ZIP archive
Name[ru]=Архив ZIP
Icon=archive-insert
Exec=/usr/bin/python3 "$data_home/folis/dolphin-create-archive.py" zip %F

[Desktop Action tarGz]
Name=tar.gz archive
Name[ru]=Архив tar.gz
Icon=archive-insert
Exec=/usr/bin/python3 "$data_home/folis/dolphin-create-archive.py" tar.gz %F
EOF

# Toolbox: "Convert to" runs in the background and notifies; the rest opens the toolbox window
toolbox="$config_home/quickshell/ii/scripts/toolbox"
quick_convert_menu() { # file mime-types target:Name:Name[ru]...
  local file=$1 mimes=$2 actions="" entry key name name_ru body=""
  shift 2
  for entry in "$@"; do
    IFS=: read -r key name name_ru <<<"$entry"
    actions+="$key;"
    body+=$'\n'"[Desktop Action $key]"$'\n'"Name=$name"$'\n'"Name[ru]=$name_ru"$'\n'"Icon=document-export"$'\n'"Exec=\"$toolbox/quick.sh\" $key %F"$'\n'
  done
  install_generated "$service_menus/$file" <<EOF
[Desktop Entry]
Type=Service
MimeType=$mimes
X-KDE-Protocols=file
X-KDE-MinNumberOfUrls=1
X-KDE-Priority=TopLevel
X-KDE-Submenu=Convert to
X-KDE-Submenu[ru]=Преобразовать в
Actions=$actions
$body
EOF
}
quick_convert_menu folis-toolbox-image.desktop "image/*;" "png:PNG:PNG" "jpg:JPG:JPG" "webp:WebP:WebP" "pdf:PDF:PDF"
quick_convert_menu folis-toolbox-video.desktop "video/*;" "mp4:MP4:MP4" "webm:WebM:WebM" "gif:GIF:GIF" "mp3:MP3 (sound only):MP3 (только звук)"
quick_convert_menu folis-toolbox-audio.desktop "audio/*;" "mp3:MP3:MP3" "opus:Opus:Opus" "flac:FLAC:FLAC"

install_generated "$service_menus/folis-toolbox.desktop" <<EOF
[Desktop Entry]
Type=Service
MimeType=all/allfiles;
X-KDE-Protocols=file
X-KDE-MinNumberOfUrls=1
X-KDE-Priority=TopLevel
X-KDE-Submenu=Toolbox
X-KDE-Submenu[ru]=Инструменты
Actions=convert;

[Desktop Action convert]
Name=Convert…
Name[ru]=Конвертировать…
Icon=transform-move
Exec="$toolbox/open.sh" converter %F
EOF

install_generated "$service_menus/folis-toolbox-text.desktop" <<EOF
[Desktop Entry]
Type=Service
MimeType=image/*;application/pdf;
X-KDE-Protocols=file
X-KDE-MaxNumberOfUrls=1
X-KDE-Priority=TopLevel
X-KDE-Submenu=Toolbox
X-KDE-Submenu[ru]=Инструменты
Actions=ocr;

[Desktop Action ocr]
Name=Recognize text
Name[ru]=Распознать текст
Icon=edit-select-text
Exec="$toolbox/open.sh" ocr %f
EOF

install_generated "$service_menus/folis-toolbox-qr.desktop" <<EOF
[Desktop Entry]
Type=Service
MimeType=image/*;
X-KDE-Protocols=file
X-KDE-MaxNumberOfUrls=1
X-KDE-Priority=TopLevel
X-KDE-Submenu=Toolbox
X-KDE-Submenu[ru]=Инструменты
Actions=qr;

[Desktop Action qr]
Name=Scan QR code
Name[ru]=Сканировать QR-код
Icon=view-barcode-qr
Exec="$toolbox/open.sh" qr %f
EOF

if $desktop_integration && command -v xdg-mime >/dev/null 2>&1 && [[ -f /usr/share/applications/org.kde.dolphin.desktop ]]; then
  if $dry_run; then
    printf 'Would make Dolphin the default handler for directories.\n'
  else
    xdg-mime default org.kde.dolphin.desktop inode/directory
    if command -v gio >/dev/null 2>&1; then
      gio mime inode/directory org.kde.dolphin.desktop
    fi
    if command -v busctl >/dev/null 2>&1; then
      busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus ReloadConfig >/dev/null 2>&1 || true
    fi
  fi
fi

# Base default apps, archives opening in Dolphin, and the "Open with" chooser for every file type
# that has no app yet. The shell runs this again on start, for types that new apps bring.
default_apps="$config_home/hypr/hyprland/scripts/default_apps.py"
if $desktop_integration && [[ -x $default_apps ]]; then
  if $dry_run; then
    printf 'Would set the base default apps and ask which app to use for other file types.\n'
  else
    "$default_apps" sync
  fi
fi

if $desktop_integration && command -v ollama >/dev/null 2>&1 && [[ ! -e /etc/systemd/system/ollama-proxy.socket ]]; then
  printf 'Tip: to run Ollama only when it is used (saves power), run:\n  sudo %s\n' "$repo_root/dots/.local/share/folis/systemd/ollama-on-demand.sh"
fi

if $desktop_integration && command -v kwriteconfig6 >/dev/null 2>&1; then
  if $dry_run; then
    printf 'Would hide Dolphin Activities and use the configured Kitty terminal on F4.\n'
  else
    kwriteconfig6 --file "$config_home/kservicemenurc" --group Show --key kactivitymanagerd_fileitem_linking_plugin false
    kwriteconfig6 --file "$config_home/dolphinrc" --group ContextMenu --key ShowAddToPlaces false
    kwriteconfig6 --file "$config_home/dolphinrc" --group Shortcuts --key show_terminal_panel none
    kwriteconfig6 --file "$config_home/dolphinrc" --group Shortcuts --key open_terminal F4
    terminal_launcher="$config_home/hypr/custom/scripts/launch-terminal.sh"
    if [[ -x $terminal_launcher ]]; then
      kwriteconfig6 --file "$config_home/kdeglobals" --group General --key TerminalApplication "$terminal_launcher"
    else
      kwriteconfig6 --file "$config_home/kdeglobals" --group General --key TerminalApplication 'kitty -1'
    fi
    kwriteconfig6 --file "$config_home/kdeglobals" --group General --key TerminalService --delete
  fi
fi

if $desktop_integration && $reload_hyprland && command -v hyprctl >/dev/null 2>&1 && [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
  if $dry_run; then
    printf 'Would reload Hyprland.\n'
  else
    hyprctl reload
  fi
fi

if $dry_run; then
  printf 'Dry run complete; no files were changed.\n'
else
  printf 'Velora configuration linked. Changes to linked files now affect the system.\n'
fi
