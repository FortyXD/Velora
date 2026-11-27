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

# Packages and native tools are managed by scripts/velora.py.

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

for name in hypr quickshell kitty foot fuzzel matugen fish fontconfig Kvantum kde-material-you-colors mpv wlogout xdg-desktop-portal zshrc.d tmux; do
  link_item "$repo_root/dots/.config/$name" "$config_home/$name"
done

# Import missing files only. Preserve links as links and never merge through a
# nested symlink. Publish each copy when complete so an interrupted relink can retry.
rebase_settings_links() {
  python3 - "$previous_settings" "$shell_settings" "$1" "$2" <<'PY'
import os
from pathlib import Path
import stat
import sys

source, destination, item, staged = map(Path, sys.argv[1:])
relative = item.relative_to(source)
source, destination = source.resolve(), destination.resolve()
links = (staged,) if staged.is_symlink() else (p for p in staged.rglob("*") if p.is_symlink())
for link in links:
    target = link.readlink()
    if target.is_absolute():
        continue
    parent = (relative / link.relative_to(staged)).parent
    before = source / parent / target
    after = destination / parent / target
    external = Path(os.path.abspath(before))
    if external.is_relative_to(source) or external == Path(os.path.abspath(after)):
        continue
    # Keep the external symlink's own name if its owner retargets it later.
    # A symlink followed by ".." in the original path needs physical resolution.
    if os.path.realpath(before) != os.path.realpath(external):
        external = Path(os.path.realpath(before.parent)) / before.name
    mode = stat.S_IMODE(link.parent.stat().st_mode)
    try:
        if not mode & stat.S_IWUSR:
            link.parent.chmod(mode | stat.S_IWUSR)
        link.unlink()
        link.symlink_to(external)
    finally:
        if not mode & stat.S_IWUSR:
            link.parent.chmod(mode)
PY
}

discard_staged_setting() {
  [[ -n $staged ]] || return 0
  if [[ -d $staged && ! -L $staged ]]; then
    find -P "$staged" -type d -exec chmod u+rwx -- {} \;
  fi
  rm -rf -- "$staged"
  staged=
}

import_settings() {
  local source=$1 dest=$2 item name target
  for item in "$source"/*; do
    name=${item##*/}
    target="$dest/$name"
    if [[ $item == "$previous_settings/config.example.json" ]]; then continue; fi
    if [[ ! -e $target && ! -L $target ]]; then
      # A sibling can be renamed atomically even for a read-only directory or
      # when this part of the user's configuration lives on another filesystem.
      if [[ -d $item && ! -L $item ]]; then
        staged=$(mktemp -d -- "$dest/.velora-settings.XXXXXXXX")
      else
        staged=$(mktemp -- "$dest/.velora-settings.XXXXXXXX")
      fi
      cp -aT --remove-destination -- "$item" "$staged"
      if [[ -L $staged || -d $staged ]]; then rebase_settings_links "$item" "$staged"; fi
      mv -nT -- "$staged" "$target"
      if [[ ! -e $staged && ! -L $staged ]]; then
        staged=
        record_change "$target"
        continue
      fi
      # A running shell created the target while the copy was being prepared.
      discard_staged_setting
    fi
    if [[ -d $item && ! -L $item && -d $target && ! -L $target ]]; then
      import_settings "$item" "$target"
    fi
  done
}

shell_settings="$config_home/velora"
legacy_settings="$config_home/illogical-impulse"
previous_settings="$legacy_settings"
# A moved checkout can still contain runtime data behind the now-dangling old link.
if [[ -L $legacy_settings && ! -e $legacy_settings && $(readlink -- "$legacy_settings") == */dots/.config/illogical-impulse ]]; then
  previous_settings="$repo_root/dots/.config/illogical-impulse"
fi
if ! $dry_run && [[ ! -d $shell_settings ]]; then
  mkdir -p -m 700 -- "$shell_settings"
  record_change "$shell_settings"
fi
if [[ ! $legacy_settings -ef $shell_settings && ( -d $previous_settings || $previous_settings != "$legacy_settings" ) ]]; then
  if $dry_run; then
    if [[ -d $previous_settings ]]; then
      printf 'Would import shell settings from %s into %s\n' "$previous_settings" "$shell_settings"
    fi
    printf 'Link %s -> %s\n' "$legacy_settings" "$shell_settings"
  else
    if [[ -d $previous_settings && ! $previous_settings -ef $shell_settings ]]; then
      (
        shopt -s dotglob nullglob
        staged=
        trap discard_staged_setting EXIT
        import_settings "$previous_settings" "$shell_settings"
      )
    fi
    link_item "$shell_settings" "$legacy_settings"
  fi
fi
shell_config="$shell_settings/config.json"
if [[ ! -e $shell_config && ! -L $shell_config ]]; then
  if $dry_run; then
    if [[ ! -e $previous_settings/config.json && ! -L $previous_settings/config.json ]]; then
      printf 'Would create %s from config.example.json.\n' "$shell_config"
    fi
  else
    (
      seed=$(mktemp -- "$shell_settings/.config.json.XXXXXX")
      trap 'rm -f -- "$seed"' EXIT
      cp -- "$repo_root/dots/.config/velora/config.example.json" "$seed"
      mv -nT -- "$seed" "$shell_config"
      if [[ ! -e $seed ]]; then record_change "$shell_config"; fi
    )
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
  mkdir -p -- "$(dirname -- "$dest")"
  cp -- "$template" "$dest"
}
seed_generated "$repo_root/dots/.config/hypr/custom/shell_settings_default.json" "$repo_root/dots/.config/hypr/custom/shell_settings.json"
seed_generated "$repo_root/dots/.config/hypr/custom/shell_settings_default.lua" "$repo_root/dots/.config/hypr/custom/shell_settings.lua"
seed_generated "$repo_root/dots/.config/hypr/hyprland/colors_default.lua" "$repo_root/dots/.config/hypr/hyprland/colors.lua"
seed_generated "$repo_root/dots/.config/hypr/hyprlock/colors_default.conf" "$repo_root/dots/.config/hypr/hyprlock/colors.conf"
seed_generated "$repo_root/dots/.config/fuzzel/fuzzel_theme_default.ini" "$repo_root/dots/.config/fuzzel/fuzzel_theme.ini"

link_item "$repo_root/dots/.config/wireplumber/wireplumber.conf.d/51-auto-audio-routes.conf" "$config_home/wireplumber/wireplumber.conf.d/51-auto-audio-routes.conf"
link_item "$repo_root/dots/.local/share/wireplumber/scripts/folis/prefer-plugged-routes.lua" "$data_home/wireplumber/scripts/folis/prefer-plugged-routes.lua"
link_item "$repo_root/dots/.local/share/org.kde.syntax-highlighting/themes/Velora.theme" "$data_home/org.kde.syntax-highlighting/themes/Velora.theme"
link_item "$repo_root/dots/.config/neofetch/velora-ascii.txt" "$config_home/neofetch/velora-ascii.txt"
link_item "$repo_root/dots/.config/neofetch/velora.conf" "$config_home/neofetch/velora.conf"
for theme_config in btop/btop.conf neofetch/config.conf; do
  theme_source=$theme_config
  [[ $theme_config != neofetch/config.conf ]] || theme_source=neofetch/velora.conf
  if [[ ! -e $config_home/$theme_config && ! -L $config_home/$theme_config ]]; then
    seed_generated "$repo_root/dots/.config/$theme_source" "$config_home/$theme_config"
    if ! $dry_run; then record_change "$config_home/$theme_config"; fi
  fi
done
link_item "$repo_root/dots/.config/starship.toml" "$config_home/starship.toml"
link_item "$repo_root/home/.zshrc" "$target_home/.zshrc"
link_item "$repo_root/home/.tmux.conf" "$target_home/.tmux.conf"
link_item "$repo_root/dots/.local/share/icons/velora.svg" "$data_home/icons/velora.svg"
legacy_icon="$data_home/icons/illogical-impulse.svg"
if [[ -L $legacy_icon && $(readlink -- "$legacy_icon") == */dots/.local/share/icons/illogical-impulse.svg ]]; then
  link_item "$repo_root/dots/.local/share/icons/velora.svg" "$legacy_icon"
fi
link_item "$repo_root/dots/.local/share/icons/hicolor/scalable/apps/org.velora.Settings.svg" "$data_home/icons/hicolor/scalable/apps/org.velora.Settings.svg"
link_item "$repo_root/dots/.local/share/applications/org.velora.Settings.desktop" "$data_home/applications/org.velora.Settings.desktop"
# The Python installer merges Dolphin toolbar additions into the existing XML.
link_item "$repo_root/dots/.local/share/dbus-1/services/org.freedesktop.FileManager1.service" "$data_home/dbus-1/services/org.freedesktop.FileManager1.service"
if [[ -x /usr/local/racket/bin/drracket ]]; then
  link_item "$repo_root/dots/.local/share/applications/drracket.desktop" "$data_home/applications/drracket.desktop"
fi

# Writes a generated file from stdin, moving a different existing file to the backup
install_generated() {
  local dest=$1 mode=${2:-755} tmp relative
  if $dry_run; then
    printf 'Would install %s\n' "$dest"
    cat > /dev/null
    return
  fi
  mkdir -p -- "$(dirname -- "$dest")"
  tmp=$(mktemp "${dest}.XXXXXX")
  cat > "$tmp"
  chmod "$mode" "$tmp"
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

btop_theme="$config_home/btop/themes/Velora.theme"
if [[ ! -e $btop_theme && ! -L $btop_theme ]]; then
  btop_conf="$config_home/btop/btop.conf"
  stock_theme='^[[:space:]]*color_theme[[:space:]]*=[[:space:]]*"Default"[[:space:]]*$'
  if [[ -f $btop_conf && ! -L $btop_conf ]] && grep -Eq "$stock_theme" "$btop_conf"; then
    install_generated "$btop_conf" "$(stat -c %a -- "$btop_conf")" < <(sed -E "s/$stock_theme/color_theme = \"Velora\"/" "$btop_conf")
  fi
  seed_generated "$repo_root/dots/.config/matugen/templates/btop/Velora.theme" "$btop_theme"
  if ! $dry_run; then record_change "$btop_theme"; fi
fi

helper="$config_home/quickshell/ii/scripts/helper"
service_menus="$data_home/kio/servicemenus"
install_generated "$service_menus/velora-assistant.desktop" <<EOF
[Desktop Entry]
Type=Service
MimeType=all/allfiles;inode/directory;
X-KDE-Protocols=file
X-KDE-MinNumberOfUrls=1
Actions=askVelora;
X-KDE-ServiceTypes=KonqPopupMenu/Plugin
[Desktop Action askVelora]
Name=Ask Velora
Name[ru]=Спросить Velora
Icon=system-search
Exec="$helper" assistant-select %F
EOF
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
Exec="$helper" create-archive zip %F

[Desktop Action tarGz]
Name=tar.gz archive
Name[ru]=Архив tar.gz
Icon=archive-insert
Exec="$helper" create-archive tar.gz %F
EOF

# Toolbox: "Convert to" runs in the background and notifies; the rest opens the toolbox window
quick_convert_menu() { # file mime-types target:Name:Name[ru]...
  local file=$1 mimes=$2 actions="" entry key name name_ru body=""
  shift 2
  for entry in "$@"; do
    IFS=: read -r key name name_ru <<<"$entry"
    actions+="$key;"
    body+=$'\n'"[Desktop Action $key]"$'\n'"Name=$name"$'\n'"Name[ru]=$name_ru"$'\n'"Icon=document-export"$'\n'"Exec=\"$helper\" toolbox-quick $key %F"$'\n'
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
Exec="$helper" toolbox-open converter %F
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
Exec="$helper" toolbox-open ocr %f
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
Exec="$helper" toolbox-open qr %f
EOF

install_generated "$service_menus/velora-preview.desktop" <<EOF
[Desktop Entry]
Type=Service
MimeType=all/allfiles;inode/directory;
X-KDE-Protocols=file
X-KDE-Priority=TopLevel
Actions=preview;

[Desktop Action preview]
Name=Quick Look
Name[ru]=Быстрый просмотр
Icon=preview
Exec="$HOME/.local/bin/velora" preview %F
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
if $desktop_integration; then
  if $dry_run; then
    printf 'Would set the base default apps and ask which app to use for other file types.\n'
  else
    # Without the helper yet (it is built by velora deps), the shell does this when it starts
    "$config_home/quickshell/ii/scripts/helper" apps sync 2>/dev/null || true
  fi
fi

if $desktop_integration && command -v ollama >/dev/null 2>&1 && [[ ! -e /etc/systemd/system/ollama-proxy.socket ]]; then
  printf 'Tip: to run Ollama only when it is used (saves power), run:\n  sudo %s\n' "$repo_root/dots/.local/share/folis/systemd/ollama-on-demand.sh"
fi

if $desktop_integration && command -v kwriteconfig6 >/dev/null 2>&1; then
  if $dry_run; then
    printf 'Would hide Dolphin Activities and use the configured Kitty terminal on F4.\n'
  else
    python3 "$(dirname -- "${BASH_SOURCE[0]}")/kde.py"
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
