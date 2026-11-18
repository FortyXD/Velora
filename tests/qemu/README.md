# Desktop regression guest

All installation, builds, tests and UI checks run in this disposable QEMU guest.
The source checkout is shared read-only over 9p; `sync` copies it to the guest.
The harness never starts the product on the host.

Host prerequisites: QEMU, edk2-ovmf, xorriso, OpenSSH, rsync and Python. Download
the official Arch x86_64 cloud qcow2 and its matching `.SHA256` file from an
[Arch image mirror](https://geo.mirror.pkgbuild.com/images/). Keep both files;
`prepare` verifies the checksum and records it in `artifacts/qemu/image.json`.

```sh
python tests/qemu/run.py prepare --image /absolute/path/Arch-Linux-x86_64-cloudimg.qcow2
python tests/qemu/run.py start
# Set VELORA_QEMU_ACCEL=tcg before start when KVM is unavailable.
python tests/qemu/run.py sync
python tests/qemu/run.py guest 'bash ~/Velora/tests/qemu/bootstrap.sh'
python tests/qemu/run.py guest 'sudo reboot'
# Wait for SSH to return. The temporary login is velora / velora-test.
python tests/qemu/run.py guest 'cd ~/Velora && ./velora install --yes --skip-aur --without assistant,appearance,live-wallpapers --no-reload --no-updates --login-manager gdm --login-theme velora'
python tests/qemu/run.py guest 'bash ~/Velora/tests/qemu/checks.sh'
python tests/qemu/run.py screenshot gdm-autumn
```

The regression session in GDM is **Velora QEMU (Hyprland 0.57.0)**. Its matching
Arch packages are signature-verified and extracted into a private guest prefix;
the installed current system libraries remain intact. Fixtures cover Cyrillic
paths, spaces, GIF, video, audio, multi-page PDF, text, large text, damaged PDF,
archives and unknown files. `in-session.py` runs commands on that desktop from SSH.

```sh
python tests/qemu/run.py guest 'cd ~/Velora && python tests/qemu/in-session.py --detach --log shell.log qs -c ii'
python tests/qemu/run.py guest 'cd ~/Velora && python tests/qemu/in-session.py python tests/qemu/preview-lifecycle.py'
python tests/qemu/run.py guest 'cd ~/Velora && python tests/qemu/in-session.py --detach --log firefox.log firefox --no-remote --profile /home/velora/firefox-qemu file:///home/velora/upload-test.html'
python tests/qemu/run.py collect
python tests/qemu/run.py stop
# Wait for QEMU to exit before taking or restoring a disk snapshot.
python tests/qemu/run.py snapshot desktop-tested
```

`restore-snapshot desktop-tested` restores the disk and matching UEFI variables
while powered off. This avoids unreliable RAM snapshots with 9p. KVM is selected
when accessible; TCG uses the same disk and scenarios. Screenshots use the QEMU
display, including GDM. `key`, `type`, `click`, `move` and `sequence` send real
input to the guest. Example: `sequence '[["key","spc"],["wait",1],["screenshot","preview"]]'`.

After an install into an already running session, reopen Dolphin and restart the
guest session before testing portal selection. Existing applications retain old
shortcuts and portal routing until restarted. Do not run these commands against
the host user session.

Inspect screenshots for GDM authentication and session selection, folder creation
in Dolphin and Firefox, kdialog open/save/directory modes, all Quick Look formats,
and both dock families. Verify login restoration with `velora greeter restore`
and another GDM start. Keep screenshots, journals, package versions and assertion
results in `artifacts/qemu/`; failed attempts are evidence, not passing results.

To compare thumbnail capture costs, use the reference Python broker and the installed native helper inside the guest.

```sh
python tests/qemu/run.py guest 'python3 ~/Velora/tests/qemu/in-session.py python3 ~/Velora/tests/qemu/preview-performance.py ~/Velora/tests/fixtures/legacy/window_previews.py ~/.local/bin/velora-helper'
python tests/qemu/run.py guest 'cd ~/Velora && PYTHONPATH=tests python -m unittest test_desktop_extras.CaptureTests test_window_thumbnails'
```

`evidence/preview-performance.json` records captures, published frames, writes,
grim latency and CPU for static, animated and two-window scenarios. CPU includes
each broker and its completed grim children. Both workers use the same guest compositor.
The QML tests also check that frame replacement and failed decoding never flash
the fallback, and that changing subscriptions retains shared frames.
They cover returning to a visited window with no fresh capture yet, the bounded
shared image cache, expiry after use, and invalidation on lock and source-window closure.
For the graphical hover regression, open Firefox and Dolphin, visit both dock
icons once, then move between them repeatedly while the preview popup stays open.
Returning to either app must show its ready image immediately; only visible or
explicitly preparing cards may capture. Repeat in Waffle, then leave the panel and lock/unlock the guest
to verify that cached images are cleared. No diagnostic IPC handlers ship in the
product; the inspected states and screenshots are saved with the QEMU evidence.

`preview-latency.py` measures the time from a keypress or hover request to the
first and last drawable image, including each surface’s opening delay. It opens
1, 4 and 8 real windows in the guest and repeats each measurement on a warm
reopen. Pass the baseline and candidate Quickshell `ii` directories. The
runner instruments temporary copies and writes `evidence/preview-surface-latency.json`.

```sh
python tests/qemu/run.py guest 'cd ~/Velora && python tests/qemu/in-session.py python3 tests/qemu/preview-latency.py /tmp/velora-preview-baseline/dots/.config/quickshell/ii ~/Velora/dots/.config/quickshell/ii'
```

`sound-monitor.py` opens Sound settings with temporary PipeWire devices, sends
a 440 Hz tone through the microphone and checks the signal at the selected
speaker. It also checks the graph through silence and the monitor lifecycle on
toggle, navigation and process exit. It restores the original devices afterwards.

```sh
python tests/qemu/run.py guest 'cd ~/Velora && python tests/qemu/in-session.py python3 tests/qemu/sound-monitor.py'
```

For first-hover and cold-switch checks, run `preview-ready-fixture.py` in the guest
before starting Quickshell. It installs a **guest-only** 1.2-second capture delay
and a 16 ms check that every window in the current group has a selectable
card with a thumbnail or icon. Inspect
`in-session.py qs -c ii ipc call previewTest state`: `invalid` must remain zero.
During the first capture the popup opens with the correct titles and icons.
Switch apps and check that the cards immediately refer to the latest group.
Rapidly request a third app to verify that a late second result cannot replace it.
To delay only one window, put the delay in seconds and its Hyprland stable ID,
separated by a space, in `/tmp/velora-preview-test-delay`.
Creating `/tmp/velora-preview-test-fail` injects capture failures; deleting it
allows recovery. Removing `/tmp/velora-preview-test-delay` restores normal speed.
Leave the dock during preparation and lock/unlock to check cancellation and cleanup.
Finally run the fixture with `--restore` while unlocked to remove instrumentation
and restore the saved guest configuration. These markers do not affect the product
outside this temporary fixture.

## Free windows and the infinite canvas

Run `python tests/qemu/run.py sync` after starting the desktop guest. With the
guest's Hyprland 0.57.0 development headers and ABI-matched libraries, build the
window plugin and the frame sampler. The sampler is only used by the benchmark.

```sh
cmake -S tools/velora-windows -B /tmp/velora-windows-build -DCMAKE_BUILD_TYPE=Release
cmake --build /tmp/velora-windows-build --parallel 2
c++ -std=c++23 -O2 -shared -fPIC tests/qemu/canvas-frames.cpp -o /tmp/velora-frame-stats.so $(pkg-config --cflags --libs hyprland lua libeis-1.0)
```

Install the window plugin in the guest through the Velora installer, or copy
the ABI-matched artifacts from the build machine to the guest atomically.

```sh
python tests/qemu/run.py guest 'set -e; d="$HOME/.local/share/velora/hypr"; mkdir -p "$d"; cat > "$d/windows.next"; mv "$d/windows.next" "$d/libvelora-windows.so"' < /tmp/velora-windows-build/libvelora-windows.so
python tests/qemu/run.py guest 'cat > /tmp/velora-frame-stats.next && mv /tmp/velora-frame-stats.next /tmp/velora-frame-stats.so' < /tmp/velora-frame-stats.so
```

In the guest's `~/qemu-hyprland.lua`, call `require("hyprland.window_mode").load()`
before the window rules and load `require("hyprland.keybinds")` after them.
Keep the primary output at 1280×800 and add
`hl.monitor({output="Canvas-2", mode="1280x800@60", position="1280x0", scale=1})`.
The input fixture uses GTK 4, foot, grim, wtype, the ydotool user service
and a virtual clickpad created through the guest user's access to `/dev/uinput`.
Run the following from the guest checkout in the graphical session via SSH.

```sh
cc tests/qemu/canvas-touchpad.c -o /tmp/velora-canvas-touchpad $(pkg-config --cflags --libs libevdev)
session() { python tests/qemu/in-session.py "$@"; }
session hyprctl reload
session hyprctl output create headless Canvas-2  # if absent
session python tests/qemu/canvas-check.py --touchpad /tmp/velora-canvas-touchpad
session hyprctl plugin load /tmp/velora-frame-stats.so
session python tests/qemu/canvas-performance.py
session hyprctl plugin unload /tmp/velora-frame-stats.so
```

The input check inspects real GTK and Velora title buttons, client coordinates
at three zoom levels, gestures, independent views of the same window and its
saved position after relaunch. The benchmark compares four Free windows, four
canvas windows, and the same scene with 50 windows offscreen. Each sample reports
frame count, p95 render time in milliseconds, mean damaged pixels, mean windows
drawn and mean scene-build time in milliseconds. It checks a 15% p95 budget
and counts frames on an empty second monitor while the first animates.

# Graphical update scenario

After syncing the source into a fresh guest snapshot, run
`python3 ~/Velora/tests/qemu/prepare-gui-update.py`. It creates a local bare Git
remote and a new test release; it does not publish anything or change sudoers.
Open `settings.qml` through `in-session.py`, then click **Install update**. Check
that installation completes without a terminal and that dependencies, the native
addon and the saved GDM choice are reconciled.

`in-session.py python3 ~/Velora/tests/qemu/gui-worker-fixture.py hold` runs a
45-second fixture to check closing/reopening Settings while the user service
continues. The `prompt` fixture displays the real askpass UI and exercises Cancel
without requesting root or changing the VM's authorization policy. Retry through
the normal button afterwards. These two fixtures test the UI and process lifetime;
the preceding local-release scenario exercises the actual installer.

# Automatic GDM wallpaper synchronization

Run `python -m unittest discover -s tests -p test_greeter_wallpaper.py -v` inside
the guest. These tests exercise the real bubblewrap decoder as well as protocol
bounds, UID checks, session authorization and atomic publication.

Install with `sudo python3 -I scripts/greeter.py apply --source "$PWD" --owner-uid 1000`,
log in to the guest's graphical session, then run `python3 tests/qemu/greeter-sync.py`.
This guest-only scenario covers config changes, corrupt inputs, another UID,
malformed requests, the logind locked hint, opt-out/re-enable and watcher restart.
It leaves a blue/pink image for the GDM screenshot; original config is saved in
`~/evidence/sync-original-config.json`. Restart **guest** GDM and inspect the screen.
Repeat with a real GNOME session and both background GSettings keys, then test
`greeter.py restore`, another install and a guest reboot. Keep screenshots,
service journals, package versions and `systemd-analyze security` output in
`artifacts/qemu/sync-*`. Never restart the host GDM for these tests.

