"""Publish the saved terminal palette and refresh the terminals that use it."""
import fcntl
import json
import os
from pathlib import Path
import re
import signal
import stat
import subprocess
import sys
from tempfile import NamedTemporaryFile


HEX = re.compile(r"#[0-9a-fA-F]{6}")
ROLES = {"primary": "primary", "secondary": "secondary", "tertiary": "tertiary",
         "surface_container": "term0", "on_surface": "term7"}
OSC = {"foreground": 10, "background": 11, "cursor": 12,
       "selection_background": 17, "selection_foreground": 19}
EMULATORS = {"foot", "alacritty", "wezterm-gui", "wezterm-mux-ser", "wezterm-mux-server",
             "konsole", "kgx", "gnome-terminal-", "gnome-terminal-server", "xterm", "uxterm"}


def read_optional(path):
    try:
        return path.read_bytes()
    except FileNotFoundError:
        return b""


def read_json(path):
    try:
        data = json.loads(path.read_bytes())
    except FileNotFoundError:
        return {}
    if not isinstance(data, dict):
        raise ValueError(f"Expected an object in {path}")
    return data


def luminance(color):
    channels = [int(color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    linear = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in channels]
    return sum(v * weight for v, weight in zip(linear, (0.2126, 0.7152, 0.0722)))


def readable_ink(background, preferred):
    bg = luminance(background)
    if preferred:
        fg = luminance(preferred)
        if (max(bg, fg) + 0.05) / (min(bg, fg) + 0.05) >= 4.5:
            return preferred
    return "#000000" if bg > 0.179 else "#ffffff"


def terminal_colors(generated, appearance):
    settings = appearance.get("wallpaperTheming", {})
    if settings.get("enableTerminal", True) is False:
        return {}
    force_dark = settings.get("terminalGenerationProps", {}).get("forceDarkMode", False)
    scss = generated / "material_colors.scss"
    if scss.is_file():
        colors = dict(re.findall(r"^\$(\w+):\s*(#[0-9a-fA-F]{6});[ \t]*$", scss.read_text(), re.M))
        if not all(f"term{i}" in colors for i in range(16)):
            raise ValueError(f"Incomplete terminal colors in {scss}")
    else:
        # During first setup the shell's wallpaper colors can arrive before the ANSI palette.
        material = read_json(generated / "colors.json")
        colors = {re.sub(r"_(\w)", lambda m: m[1].upper(), k): v for k, v in material.items()
                  if isinstance(v, str) and HEX.fullmatch(v)}
        if not force_dark or luminance(colors.get("surfaceContainer", "#000000")) < 0.5:
            for source, dest in (("surfaceContainer", "term0"), ("onSurface", "term7")):
                if source in colors:
                    colors[dest] = colors[source]

    overrides = appearance.get("palette", {}).get("roleOverrides", {})
    for role, dest in ROLES.items():
        value = overrides.get(role) if isinstance(overrides, dict) else None
        if not isinstance(value, str) or not HEX.fullmatch(value):
            continue
        if dest == "term0" and force_dark and luminance(value) >= 0.5:
            continue
        colors[dest] = value
        if role in ("primary", "secondary", "tertiary"):
            ink = "on" + role.capitalize()
            colors[ink] = readable_ink(value, colors.get(ink))
        elif dest == "term7" and force_dark:
            colors[dest] = readable_ink(colors.get("term0", "#000000"), value)

    result = {}
    for line in (Path(__file__).resolve().parents[3] / "tools/velora-helper/src/palette/roles.txt").read_text().splitlines():
        if line and not line.startswith("#"):
            option, role = line.split()
            if role in colors:
                result[option] = colors[role].lower()
    return result


def sequences(colors):
    commands = []
    for option, value in colors.items():
        if option.startswith("color") and option[5:].isdigit():
            index = option[5:]
            commands.append(f"4;{index};{value}" if value else f"104;{index}")
        elif option in OSC:
            code = OSC[option]
            commands.append(f"{code};{value}" if value else str(code + 100))
    return "".join(f"\x1b]{cmd}\x1b\\" for cmd in commands).encode("ascii")


def publish(path, content):
    if not content:
        path.unlink(missing_ok=True)
        return
    with NamedTemporaryFile(dir=path.parent, delete=False) as tmp:
        try:
            tmp.write(content)
            tmp.flush()
            os.replace(tmp.name, path)
        finally:
            Path(tmp.name).unlink(missing_ok=True)


def refresh_terminals(update, kitty_reset):
    if not (os.environ.get("WAYLAND_DISPLAY") or os.environ.get("DISPLAY")):
        return
    # Restrict OSC traffic to the controlling terminals of emulators' own session leaders.
    # This excludes sshd, background jobs, test runners and unrelated pseudo-terminals.
    rows = subprocess.check_output(["ps", "-u", str(os.getuid()), "-o", "pid=,ppid=,sid=,tty=,comm="],
                                   text=True, errors="replace").splitlines()
    processes = [row.split(None, 4) for row in rows]
    parents = {row[0]: row[-1] for row in processes}
    terminals = {tty: (ppid, parents.get(ppid)) for pid, ppid, sid, tty, _ in processes
                 if pid == sid and re.fullmatch(r"pts/[0-9]+", tty)}
    # Only GUI Kitty processes with an open terminal, never a kitten or kitty +runpy.
    for pid in {ppid for ppid, emulator in terminals.values() if emulator == "kitty"}:
        try:
            os.kill(int(pid), signal.SIGUSR1)
        except (ProcessLookupError, PermissionError):
            pass
    for tty, (_, emulator) in terminals.items():
        if emulator == "kitty":
            data = kitty_reset
        elif emulator in EMULATORS:
            data = update
        else:
            continue
        if not data:
            continue
        try:
            fd = os.open("/dev/" + tty, os.O_WRONLY | os.O_NOCTTY | os.O_NONBLOCK | os.O_NOFOLLOW)
            with os.fdopen(fd, "wb", buffering=0) as stream:
                info = os.fstat(fd)
                if info.st_uid == os.getuid() and stat.S_ISCHR(info.st_mode):
                    stream.write(data)
        except OSError:
            continue  # A terminal can close between the process snapshot and the write.


def apply(generated, config, refresh=refresh_terminals):
    dest = generated / "terminal"
    dest.mkdir(parents=True, exist_ok=True)
    with (dest / ".palette.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        # Read both inputs under the lock. A delayed wallpaper job must pick up the latest edit.
        appearance = read_json(config).get("appearance", {})
        colors = terminal_colors(generated, appearance)
        conf = "".join(f"{k} {v}\n" for k, v in colors.items()).encode("ascii")
        osc = sequences(colors)
        kitty_path, osc_path = dest / "kitty-theme.conf", dest / "sequences.txt"
        old_conf, old_osc = read_optional(kitty_path), read_optional(osc_path)
        if (conf, osc) == (old_conf, old_osc):
            return
        old_options = re.findall(rb"^(\w+)[ \t]+#[0-9A-Fa-f]{6}\b", old_conf, re.M)
        reset = {key.decode("ascii"): None for key in old_options}
        publish(kitty_path, conf)
        publish(osc_path, osc)
        # Older shell hooks set dynamic Kitty colors that can outlive a config reload.
        kitty_reset = sequences(reset) if b"\x1b]708;" in old_osc else b""
        removed = {key: None for key in reset if key not in colors}
        refresh(sequences(removed) + osc, kitty_reset)


if __name__ == "__main__":
    state = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")
    config_home = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
    try:
        apply(state / "quickshell/user/generated", config_home / "illogical-impulse/config.json")
    except (OSError, ValueError) as error:
        sys.exit(f"Terminal colors: {error}")
