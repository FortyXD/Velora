# Login and file previews

`velora install --login-theme velora` opts into the Autumn GDM appearance.
The default is `keep`; the chosen setting is retained for updates.
`velora greeter status` reports support and installation state.
`velora greeter restore` restores the original files and returns the saved choice
to `keep`. Changes appear on the next GDM start; installation does not end a session.

These features arrive through the normal **Settings > General > Software Update**
flow or `velora update`; there is no separate administration panel. Dolphin's
toolbar, the file-dialog addon, Quick Look and KDE preferences are installed in
the user's home directory. Administrator authorization is needed for missing
system packages, the first GDM opt-in, or changed system resources. An unchanged
GDM installation and already configured system services are checked without
privileges and skipped on repeat updates. Package installations managed by pacman
still require its normal authorization. No passwordless root helper is installed.

**Install update** starts a user service and displays progress directly in Settings,
without opening a terminal. Closing Settings does not interrupt installation;
reopening the page restores its progress and result. The GUI reconciles dependencies
for the saved component selection, including installations originally bootstrapped
with `--skip-packages`. A normal graphical password prompt is opened by sudo only
when authorization is required; Velora never stores that password. Errors and
cancelled authorization leave a **Retry update** button. Retrying also finishes an
installation whose source download already succeeded. Progress and a private log
are stored in `~/.local/state/velora/gui-update.json` and `gui-update.log`.

The extension is restricted to GDM and the tested GNOME Shell **51.1** release.
Other releases retain the standard login. Native GDM authentication, user and
session selection, keyboard layout, accessibility and power controls remain in
GNOME. System assets live under `/usr/share/gnome-shell/extensions/velora-greeter@velora`;
the original configuration backup is `/var/lib/velora/greeter`. No GNOME library,
PAM configuration or compiled shell resource is replaced. Autumn is the fallback
background. Opting into this theme also installs automatic wallpaper synchronization
for the installing account. Existing Velora GDM installations receive the bridge
through the same update button, with normal authorization once for its system files.
Subsequent wallpaper changes require no password or terminal commands.

**Wallpaper > Login screen wallpaper** controls synchronization. Disabling it
returns to Autumn and deletes the generated wallpaper copies. The login background
is public to all users of the computer. It follows one designated account; an update
from another account does not change that ownership. Velora wallpaper changes and
GNOME's `picture-uri`, `picture-uri-dark` and light/dark preference are observed
automatically. Videos use Velora's existing still thumbnail; GIF uses its first frame.
Missing or unsupported files retain the last working background.
**Animate built-in wallpapers on the login screen** also renders the selected
Aurora, Liquid, Neon grid or Dunes preset with the desktop colors, speed and
frame rate. The bridge carries a preset index, playback settings and four RGB
colors alongside the still image. This is off by default. GDM uses the still image when animations
are disabled, the preset is unavailable or the user selects a picture or video.

The bridge has two separate processes:

- A user service observes settings, debounces changes and decodes images inside
  bubblewrap with no network or home access, just the opened input. Limits cover
  input size (64 MiB), decoded dimensions (24 million source pixels), memory, CPU
  and elapsed time. Output is bounded RGB, at most 2560×1600, without metadata.
- A socket-activated system service runs as the non-login `velora-greeter-sync`
  account, **not root**. Kernel socket credentials must match the configured UID;
  logind must report an active local graphical session with no locked hint. This
  is account-based authorization, not a guarantee that the sending process itself
  originated at the local keyboard. No active local graphical session means refusal.
  The service accepts only bounded appearance data or a reset request, never source paths,
  URLs, commands or compressed images. It checks the session again before publication.

The service can write only `/var/lib/velora-greeter`, applies fixed blur/dimming,
and atomically publishes immutable JPEG names and `current.json`. At most two images
are retained. The GDM extension watches that manifest, validates filenames, and
falls back to bundled Autumn when no valid image is available. The daemon exits
after 30 seconds idle; the user watcher uses settings notifications and a 15-second
fallback for session activation or editing an existing image. Broken images are
not repeatedly decoded until the input changes. No sudoers or polkit exemption is
installed. Original system configs and startup drop-ins are backed up and restored
by `velora greeter restore`; restoration also stops both services and deletes the
generated images. The disabled non-login system account is retained to avoid UID reuse.

Dolphin gains its native Create Folder action before the menu button. The Velora
Qt6 generic plugin pins KIO's existing action at the right edge of file dialogs,
including KDE portal dialogs. It uses KDE's normal operation and error handling.
Session environment and a user service override load the plugin. Reopen running
Dolphin instances and start a new desktop session after first installation.

Dolphin's hover selection toggles are off by default. Git status badges remain
opt-in under Dolphin's version-control plugins; installation and updates no longer
enable the Git plugin automatically. These marks are independent of AI search.

`velora preview PATH...` opens a separate Quick Look window. Space or Escape
closes it, Left/Right switches files, and Enter opens the current file in its
default application. Dolphin's Quick Look service action uses Space; its previous
selection-mode shortcut moves to Shift+Space. Text fields keep ordinary typing.
Images, GIF, video, audio, PDF, bounded text and archive listings are supported.
Video starts muted; audio waits for Play. Unsupported or damaged files retain an
Open action and metadata. PDF rendering and archive listing run in bounded child
processes; archives are never extracted.

Official KDE packages provide Git integration, video/document thumbnails and
Filelight disk usage analysis. Existing KDE settings are supplemented. The KDE
palette is applied from Velora's generated colors without requiring KWin or a
separate theme daemon; disabling Qt application theming still takes precedence.

On Hyprland 0.57.0, window thumbnails use a separate `grim -T` capture broker.
Stable window IDs distinguish identical titles. The first capture uses the
window dimensions supplied by Hyprland and corrects for output scaling or
resizing from the returned image. Two captures can run at once. First frames
take priority over updates, with the selected Alt+Tab window first. Four
captures can start in an initial burst. The shared budget then replenishes at
sixteen starts per second. Moving windows refresh at up to 8 FPS, static windows
settle at two polls per second, and energy saving takes one frame.

Alt+Tab prepares thumbnails on the first keypress. The dock, workspace bar
and Waffle start preparing on hover. When the popup opens, every window in the
current group is selectable. Each card shows its own title and icon until its
image is ready. Moving to another app immediately switches the group. An
individual capture failure leaves that window selectable while capture retries.

Decoded images for the eight most recently viewed windows are shared across
these surfaces for up to 30 seconds after use. Reopening a popup can show its
last image while a fresh capture runs. A new image replaces the previous one
after decoding. Identical captures skip encoding and disk writes. Capture
stops and private frame files are removed when the last subscriber leaves.
Closing a source window discards its cached image, and locking clears the cache.

See [QEMU scenarios](../tests/qemu/README.md) for guest setup, signed regression
packages, snapshots, assertions and screenshot collection.


### Free windows and the infinite canvas

Choose a window mode under **Settings → Desktop → Windows**. In Free windows,
use the title bar or Alt+Space to minimize, maximize, restore or close a
window. The dock, taskbar and Alt+Tab can restore it. Super+Down restores a
maximized window and minimizes a free window. Super+Z opens snap layouts.
Each Wayland window can draw its own header or request a Velora title bar.
Brave and VS Code keep their built-in controls by default. XWayland windows
use their Motif hints and GTK frame extents. Changing a window's decoration
preference updates the frame while it is open. Alt+Space offers a per-app override.

On the infinite canvas, the workspaces and monitors look at one shared plane.
Hold Super and drag the middle mouse button to pan. Super+wheel zooms around
the pointer. On a touchpad, hold Super and scroll with two fingers to pan or
pinch to zoom. Super+Home frames the open windows and Super+End returns to
100%. Super+left drag moves a window and Super+right drag resizes it. A minimap
appears during navigation. Maximizing uses the active monitor's work area.

The canvas saves each camera and the positions of each application's windows in
`$XDG_STATE_HOME/velora/windows.json`. Free windows stores its per-window
geometry in `window-geometry.lua` in the same directory, normally
`~/.local/state/velora/`. Reopening an application restores its window
positions. The installer builds the native module for Hyprland
0.57.0. If the installed compositor has another ABI, Free windows stays
available through the window menu, panel and shortcuts.
