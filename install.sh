#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
config_home=${XDG_CONFIG_HOME:-"$HOME/.config"}
data_home=${XDG_DATA_HOME:-"$HOME/.local/share"}
state_home=${XDG_STATE_HOME:-"$HOME/.local/state"}
backup_root="$state_home/folis/backups/$(date +%Y%m%d-%H%M%S)-$$"
dry_run=false
install_packages=true
reload_hyprland=true
install_aur=true

usage() {
  cat <<'HELP'
Usage: ./install.sh [--dry-run] [--skip-packages] [--skip-aur] [--no-reload]

Install Arch packages and link Folis configs into your home directory.
Existing targets are moved to ~/.local/state/folis/backups/.
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
    --skip-aur) install_aur=false ;;
    --no-reload) reload_hyprland=false ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown option: %s\n' "$arg" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ $EUID -eq 0 ]]; then
  printf 'Run this script as your normal user, not root.\n' >&2
  exit 1
fi

if $install_packages; then
  if ! command -v pacman >/dev/null 2>&1; then
    printf 'Package installation currently supports Arch Linux (pacman).\n' >&2
    exit 1
  fi
  if $install_aur && ! $dry_run && ! command -v yay >/dev/null 2>&1; then
    printf 'Install yay first, or rerun with --skip-aur.\n' >&2
    exit 1
  fi
  mapfile -t packages < <(sed -E 's/[[:space:]]*#.*$//; /^[[:space:]]*$/d' "$repo_root/packages/arch.txt")
  if $dry_run; then
    printf 'Would install %s Arch packages with pacman.\n' "${#packages[@]}"
  else
    sudo pacman -S --needed -- "${packages[@]}"
  fi
  if $install_aur; then
    mapfile -t aur_packages < <(sed -E 's/[[:space:]]*#.*$//; /^[[:space:]]*$/d' "$repo_root/packages/aur.txt")
    if $dry_run; then
      printf 'Would install %s AUR packages with yay.\n' "${#aur_packages[@]}"
    else
      yay -S --needed -- "${aur_packages[@]}"
    fi
  fi
fi

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
      for state_file in installed_true installed_listfile; do
        if [[ -e $target/$state_file && ! -e $source/$state_file ]]; then
          cp -a -- "$target/$state_file" "$source/$state_file"
        fi
      done
    fi
    relative=${target#"$HOME"/}
    mkdir -p -- "$backup_root/$(dirname -- "$relative")"
    mv -- "$target" "$backup_root/$relative"
    printf '  Backup: %s\n' "$backup_root/$relative"
  fi
  ln -s -- "$source" "$target"
}

for name in hypr quickshell kitty foot fuzzel matugen fish fontconfig Kvantum kde-material-you-colors mpv wlogout xdg-desktop-portal zshrc.d tmux illogical-impulse; do
  link_item "$repo_root/dots/.config/$name" "$config_home/$name"
done
link_item "$repo_root/dots/.config/wireplumber/wireplumber.conf.d/51-auto-audio-routes.conf" "$config_home/wireplumber/wireplumber.conf.d/51-auto-audio-routes.conf"
link_item "$repo_root/dots/.config/starship.toml" "$config_home/starship.toml"
link_item "$repo_root/home/.zshrc" "$HOME/.zshrc"
link_item "$repo_root/home/.tmux.conf" "$HOME/.tmux.conf"
link_item "$repo_root/dots/.local/share/icons/illogical-impulse.svg" "$data_home/icons/illogical-impulse.svg"
link_item "$repo_root/dots/.local/share/kxmlgui5/dolphin/dolphinui.rc" "$data_home/kxmlgui5/dolphin/dolphinui.rc"
link_item "$repo_root/dots/.local/share/folis/dolphin-create-archive.py" "$data_home/folis/dolphin-create-archive.py"
link_item "$repo_root/dots/.local/share/dbus-1/services/org.freedesktop.FileManager1.service" "$data_home/dbus-1/services/org.freedesktop.FileManager1.service"

archive_menu="$data_home/kio/servicemenus/folis-create-archive.desktop"
if $dry_run; then
  printf 'Would install Dolphin archive menu: %s\n' "$archive_menu"
else
  mkdir -p -- "$(dirname -- "$archive_menu")"
  archive_menu_tmp=$(mktemp "${archive_menu}.XXXXXX")
  cat > "$archive_menu_tmp" <<EOF
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
  chmod 755 "$archive_menu_tmp"
  if [[ -e $archive_menu || -L $archive_menu ]]; then
    if cmp -s -- "$archive_menu_tmp" "$archive_menu"; then
      rm -- "$archive_menu_tmp"
    else
      relative=${archive_menu#"$HOME"/}
      mkdir -p -- "$backup_root/$(dirname -- "$relative")"
      mv -- "$archive_menu" "$backup_root/$relative"
      mv -- "$archive_menu_tmp" "$archive_menu"
    fi
  else
    mv -- "$archive_menu_tmp" "$archive_menu"
  fi
fi

if command -v xdg-mime >/dev/null 2>&1 && [[ -f /usr/share/applications/org.kde.dolphin.desktop ]]; then
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

if command -v kwriteconfig6 >/dev/null 2>&1; then
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

if $reload_hyprland && command -v hyprctl >/dev/null 2>&1 && [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
  if $dry_run; then
    printf 'Would reload Hyprland.\n'
  else
    hyprctl reload
  fi
fi

if $dry_run; then
  printf 'Dry run complete; no files were changed.\n'
else
  printf 'Folis setup complete. Changes to linked files now affect the system.\n'
fi
