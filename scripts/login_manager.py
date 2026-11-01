"""Optional graphical login setup; inspection never changes services."""
import configparser
import os
from pathlib import Path
import shlex
import shutil
import subprocess


MANAGERS = {
    "gdm": ("GDM (GNOME)", "gdm", "gdm.service"),
    "sddm": ("SDDM", "sddm", "sddm.service"),
    "lightdm": ("LightDM", "lightdm", "lightdm.service"),
    "greetd": ("greetd", "greetd", "greetd.service"),
    "ly": ("Ly", "ly", "ly.service"),
    "plasma-login-manager": ("Plasma Login Manager", "plasma-login-manager", "plasmalogin.service"),
    "cosmic-greeter": ("COSMIC Greeter", "cosmic-greeter", "cosmic-greeter.service"),
    "lxdm": ("LXDM", "lxdm", "lxdm.service"),
    "xdm": ("XDM", "xorg-xdm", "xdm.service"),
}
CHOICES = ("skip", "existing", *MANAGERS)
SYSTEM_UNIT_DIRS = (Path("/etc/systemd/system"), Path("/run/systemd/system"),
                    Path("/usr/local/lib/systemd/system"), Path("/usr/lib/systemd/system"))


def probe(command):
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=15,
                                env=dict(os.environ, LANG="C.UTF-8", LC_ALL="C.UTF-8"))
        return result.stdout if result.returncode == 0 else None
    except (OSError, subprocess.TimeoutExpired):
        return None


def inspect(alias=None):
    if alias is None:
        aliases = [directory / "display-manager.service" for directory in SYSTEM_UNIT_DIRS]
        alias = next((path for path in aliases if path.exists() or path.is_symlink()), aliases[0])
    package_output = probe(["pacman", "-Qq"])
    unit_output = probe(["systemctl", "list-unit-files", "--type=service", "--no-legend", "--no-pager"])
    active_output = probe(["systemctl", "list-units", "--type=service", "--state=active",
                           "--plain", "--no-legend", "--no-pager"])
    packages = set((package_output or "").splitlines())
    unit_files = {}
    for line in (unit_output or "").splitlines():
        fields = line.split()
        if len(fields) >= 2:
            unit_files[fields[0]] = fields[1]
    active = {line.split()[0] for line in (active_output or "").splitlines() if line.split()}
    configured = alias.resolve().name if alias.is_symlink() else "display-manager.service" if alias.exists() else None
    if configured is None and "display-manager.service" in unit_files:
        # Generators and custom unit search paths can supply the alias outside
        # the standard directories. Preserve that setup even if its name is unknown.
        configured = "display-manager.service"
    found = []
    for name, (label, package, unit) in MANAGERS.items():
        if name == "ly":
            unit = next((item for item in sorted(active | set(unit_files))
                         if item.startswith("ly@") and item != "ly@.service"), unit)
        enabled = unit_files.get(unit, "").startswith("enabled") or unit == configured
        installed = package in packages or unit in unit_files or unit in active or unit == configured
        if installed:
            found.append({"name": name, "label": label, "package": package, "unit": unit,
                          "installed": installed, "active": unit in active,
                          "enabled": enabled, "configured": unit == configured})
    if configured and not any(item["unit"] == configured for item in found):
        found.append({"name": "existing", "label": configured, "package": None, "unit": configured,
                      "installed": True, "active": configured in active, "enabled": True, "configured": True})
    found.sort(key=lambda item: (not (item["active"] and item["configured"]), not item["active"],
                                 not item["configured"], not item["enabled"], item["name"]))
    return {"managers": found, "default_target": (probe(["systemctl", "get-default"]) or "").strip(),
            "inspection_complete": all(output is not None for output in (package_output, unit_output, active_output))}


def choose(requested, saved, inventory, *, interactive=False, ask=None):
    ask = input if ask is None else ask
    found = inventory["managers"]
    if requested is None and saved in CHOICES:
        requested = saved
    if requested is None and interactive:
        if ask("Use a graphical login screen for Velora? [y/N] ").strip().lower() not in ("y", "yes"):
            return "skip"
        if found:
            default = found[0]["name"]
            choices = ", ".join(item["name"] for item in found)
            answer = ask(f"Use an existing login manager [{choices}; Enter for {default}, or skip]: ").strip().lower()
            requested = answer or default
        else:
            requested = ask("Install a login manager [Enter for gdm (GNOME), sddm, or skip]: ").strip().lower() or "gdm"
    requested = requested or "skip"
    if requested not in CHOICES:
        raise ValueError("Unknown login manager choice: " + requested)
    if requested == "skip":
        return requested
    if requested == "existing":
        if not found:
            raise ValueError("No existing login manager was found. Choose --login-manager gdm or sddm, or skip.")
        preferred = found[0]
        if len(found) > 1 and not (preferred["configured"] or preferred["active"] or preferred["enabled"]):
            raise ValueError("Multiple login managers are installed. Select one explicitly with --login-manager NAME.")
        requested = preferred["name"]
    selected = next((item for item in found if item["name"] == requested), None)
    conflicts = [item["label"] for item in found if item["name"] != requested
                 and (item["active"] or item["enabled"] or item["configured"])]
    if conflicts:
        raise ValueError("Keeping the existing login manager (" + ", ".join(conflicts)
                         + "). Use --login-manager existing or skip; switch managers explicitly in system administration first.")
    if requested not in ("gdm", "sddm") and not selected:
        raise ValueError("Only GDM and SDDM can be installed automatically; other managers must already be configured.")
    if selected and requested not in ("gdm", "sddm") and not (selected["enabled"] or selected["active"]):
        raise ValueError(f"{selected['label']} is installed but needs its greeter/service configured before reuse.")
    return requested


def describe(choice, inventory, *, skip_packages=False):
    detected = ", ".join(item["label"] + (" (active)" if item["active"] else " (enabled)" if item["enabled"] else " (installed)")
                         for item in inventory["managers"]) or "none found"
    print("  Detected login managers: " + detected)
    if skip_packages:
        print(f"  Graphical login: leave packages and services unchanged (--skip-packages; choice: {choice})")
    elif choice == "skip":
        print("  Graphical login: keep the current setup; no package or service changes")
    else:
        label = MANAGERS[choice][0] if choice in MANAGERS else choice
        present = any(item["name"] == choice and item["installed"] for item in inventory["managers"])
        action = "reuse" if present else "install"
        print(f"  Graphical login: {action} {label}; verify the Hyprland session entry; enable graphical boot if needed")
        print("  Login services will not be started, stopped, or restarted during installation.")


def session_entry(directory=Path("/usr/share/wayland-sessions")):
    for path in sorted(directory.glob("hyprland*.desktop"), key=lambda item: (item.name != "hyprland.desktop", item.name)):
        entry = configparser.ConfigParser(interpolation=None, strict=False)
        try:
            entry.read_string(path.read_text())
            command = shlex.split(entry.get("Desktop Entry", "Exec", fallback=""))
            try_exec = entry.get("Desktop Entry", "TryExec", fallback="").strip()
            if (entry.get("Desktop Entry", "Type", fallback="") == "Application"
                    and command and shutil.which(command[0]) and (not try_exec or shutil.which(try_exec))):
                return path
        except (OSError, ValueError, configparser.Error):
            continue
    raise ValueError("Hyprland's Wayland session desktop entry is missing or invalid. Reinstall the hyprland package before enabling graphical login.")


def configure(choice, run, *, dry=False, skip_packages=False, inventory=None):
    if choice == "skip" or skip_packages:
        return
    inventory = inspect() if inventory is None else inventory
    if not inventory["default_target"] or not inventory.get("inspection_complete", True):
        raise ValueError("Could not inspect systemd's login services and boot target. Leave the login manager unchanged and retry from the installed system.")
    choice = choose(choice, None, inventory)  # Refuse a manager introduced since plan review.
    selected = next((item for item in inventory["managers"] if item["name"] == choice), None)
    if choice in ("gdm", "sddm") and not (selected and selected["installed"]):
        run(["sudo", "pacman", "-Syu", "--needed", "--", MANAGERS[choice][1]], dry=dry)
    if dry:
        print("  Would verify the Hyprland package's /usr/share/wayland-sessions/hyprland*.desktop entry.")
    else:
        print("  Hyprland login session: " + str(session_entry()))
    if not (selected and selected["enabled"]):
        unit = selected["unit"] if selected else MANAGERS[choice][2]
        run(["sudo", "systemctl", "enable", "--", unit], dry=dry)
    if inventory["default_target"] != "graphical.target":
        run(["sudo", "systemctl", "set-default", "graphical.target"], dry=dry)
    print("Select Hyprland in the login screen's session menu after reboot. Existing login themes and authentication settings are retained.")
