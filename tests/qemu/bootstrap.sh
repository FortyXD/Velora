#!/usr/bin/env bash
# Run only inside the disposable Arch cloud guest created by run.py.
set -euo pipefail
test -e /var/lib/velora-qemu-ready
test "$(id -u)" -ne 0
mkdir -p "$HOME/evidence"
sudo pacman -Syu --needed --noconfirm base-devel git rsync python python-pillow python-gobject \
    cmake extra-cmake-modules qt6-base qt6-declarative qt6-multimedia qt6-5compat kio kdialog \
    gdm gnome-shell hyprland quickshell dolphin dolphin-plugins ffmpegthumbs kdegraphics-thumbnailers \
    filelight firefox foot grim poppler libarchive ffmpeg wl-clipboard uv
cd "$HOME/Velora"
if ! git rev-parse --git-dir >/dev/null 2>&1; then
    git init
    git add .
    git -c user.name='QEMU fixture' -c user.email='qemu@localhost' commit -qm 'Guest source snapshot'
fi
# Keep the host's installed libraries untouched; exercise the regression compositor
# with the matching, signed Arch libraries in a guest-only prefix.
mkdir -p "$HOME/hyprland0570" "$HOME/qemu-packages"
for package in hyprland-0.57.0-1 aquamarine-0.15.1-1 hyprgraphics-0.5.1-4; do
    name=${package%%-[0-9]*}
    filename="$package-x86_64.pkg.tar.zst"
    url="https://archive.archlinux.org/packages/${name:0:1}/$name/$filename"
    curl --fail --location --retry 3 "$url" -o "$HOME/qemu-packages/$filename"
    curl --fail --location --retry 3 "$url.sig" -o "$HOME/qemu-packages/$filename.sig"
    sudo pacman-key --verify "$HOME/qemu-packages/$filename.sig" "$HOME/qemu-packages/$filename"
    bsdtar -xf "$HOME/qemu-packages/$filename" -C "$HOME/hyprland0570"
done
sha256sum "$HOME"/qemu-packages/* > "$HOME/evidence/regression-packages.sha256"
python tests/qemu/desktop-fixtures.py
sudo systemctl enable gdm
sudo systemctl enable sshd
printf '%s\n' 'Reboot the guest to match the upgraded kernel and modules, then run the Velora installer.'
