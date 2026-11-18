"""Restore the password prompt if the shell exits while its Wayland session is locked."""
import fcntl
import os
from pathlib import Path
import sys

from gi.repository import Gio, GLib, GLibUnix


def watch(shell_pid):
    screensaver = Gio.DBusProxy.new_for_bus_sync(
        Gio.BusType.SESSION, Gio.DBusProxyFlags.DO_NOT_AUTO_START, None,
        "org.freedesktop.ScreenSaver", "/org/freedesktop/ScreenSaver",
        "org.freedesktop.ScreenSaver", None,
    )
    loop = GLib.MainLoop()

    def active():
        # Hypridle forwards the compositor's hyprland-lock-notify-v1 state.
        return screensaver.call_sync("GetActive", None, Gio.DBusCallFlags.NONE, 1500, None).unpack()[0]

    def on_signal(proxy, sender, name, params):
        if name == "ActiveChanged" and not params.unpack()[0]:
            loop.quit()

    def recover():
        if active():
            instance = Path(os.environ["XDG_RUNTIME_DIR"]) / "hypr" / os.environ["HYPRLAND_INSTANCE_SIGNATURE"]
            with (instance / "velora-lock-recovery.lock").open("a") as lock:
                try:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    loop.quit()
                    return GLib.SOURCE_REMOVE
                os.set_inheritable(lock.fileno(), True)
                os.execlp("hyprlock", "hyprlock", "--immediate-render", "--grace", "0")
        loop.quit()
        return GLib.SOURCE_REMOVE

    def shell_exited(*_):
        # Give an unlock sent immediately before the shell exited time to reach hypridle.
        GLib.timeout_add(250, recover)
        return GLib.SOURCE_REMOVE

    screensaver.connect("g-signal", on_signal)
    if not active():
        return
    try:
        pidfd = os.pidfd_open(shell_pid)
    except ProcessLookupError:
        shell_exited()
    else:
        GLibUnix.fd_add_full(GLib.PRIORITY_DEFAULT, pidfd, GLib.IOCondition.IN, shell_exited)
    loop.run()


if __name__ == "__main__":
    watch(int(sys.argv[1]))
