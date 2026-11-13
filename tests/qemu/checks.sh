#!/usr/bin/env bash
set -euo pipefail
test -e /var/lib/velora-qemu-ready
cd "$HOME/Velora"
mkdir -p "$HOME/evidence"
python -m unittest discover -s tests -p test_desktop_extras.py 2>&1 | tee "$HOME/evidence/desktop-tests.log"
python -m unittest discover -s tests -p test_velora.py 2>&1 | tee "$HOME/evidence/installer-tests.log"
python -m unittest discover -s tests -p test_update_gui.py 2>&1 | tee "$HOME/evidence/gui-update-tests.log"
python -m unittest discover -s tests -p test_system_dependencies.py 2>&1 | tee "$HOME/evidence/system-service-tests.log"
python -m unittest discover -s tests -p 'test_install*.py' 2>&1 | tee "$HOME/evidence/install-extra-tests.log"
python -m unittest discover -s tests -p test_window_thumbnails.py 2>&1 | tee "$HOME/evidence/thumbnail-qml-tests.log"
python -m unittest discover -s tests -p 'test_wallpaper*.py' 2>&1 | tee "$HOME/evidence/wallpaper-tests.log"
cmake -S tools/velora-file-dialog -B /tmp/velora-dialog-tests -DBUILD_TESTING=ON -DCMAKE_BUILD_TYPE=Debug
cmake --build /tmp/velora-dialog-tests --parallel 2
ctest --test-dir /tmp/velora-dialog-tests --output-on-failure 2>&1 | tee "$HOME/evidence/file-dialog-tests.log"
pacman -Q > "$HOME/evidence/packages.txt"
uname -a > "$HOME/evidence/kernel.txt"
./velora greeter status > "$HOME/evidence/greeter-status.json"
sudo journalctl -b -u gdm --no-pager > "$HOME/evidence/gdm.log"
journalctl --user -b --no-pager > "$HOME/evidence/user-session.log"
