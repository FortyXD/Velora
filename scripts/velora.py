#!/usr/bin/env python3
"""Velora's Arch installer and updater. Uses only the Python standard library."""
from __future__ import annotations

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import fcntl
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

if sys.version_info < (3, 11):
    sys.exit("Velora requires Python 3.11 or newer. Install the Arch 'python' package.")
import tomllib

sys.path.insert(0, str(Path(__file__).resolve().parent))
import builds
from runtime import sync_runtime

ROOT = Path(__file__).resolve().parents[1]


class VeloraError(Exception):
    pass


def run(command, *, cwd=None, capture=False, dry=False, env=None, timeout=None):
    command = [str(arg) for arg in command]
    if dry:
        print("  Would run: " + shlex.join(command))
        return ""
    sys.stdout.flush()
    environment = dict(os.environ if env is None else env, LANG="C.UTF-8", LC_ALL="C.UTF-8")
    try:
        result = subprocess.run(command, cwd=cwd, env=environment, text=True,
                                capture_output=capture, check=True, timeout=timeout)
    except subprocess.CalledProcessError as error:
        detail = (error.stderr or error.stdout or "").strip() if capture else ""
        raise VeloraError(f"Command failed ({error.returncode}): {shlex.join(command)}"
                          + (f"\n{detail}" if detail else "")) from error
    except (OSError, subprocess.TimeoutExpired) as error:
        raise VeloraError(f"Could not run {command[0]}: {error}") from error
    return result.stdout.strip() if capture else ""


def xdg(name, default):
    return Path(os.environ.get(name) or Path.home() / default).expanduser().absolute()


def state_dir():
    return xdg("XDG_STATE_HOME", ".local/state") / "velora"


def read_json(path, default=None):
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        return {} if default is None else default


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as temp:
        json.dump(data, temp, indent=2)
        temp.write("\n")
        temp_path = Path(temp.name)
    os.replace(temp_path, path)


@contextmanager
def operation_lock():
    state_dir().mkdir(parents=True, exist_ok=True)
    with (state_dir() / "operation.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise VeloraError("Another Velora operation is running. Wait for it to finish.") from error
        yield


def manifest():
    with (ROOT / "dependencies/arch.toml").open("rb") as source:
        data = tomllib.load(source)
    if data.get("version") != 1 or not data.get("features"):
        raise VeloraError("Unsupported dependency manifest.")
    for feature in data["features"].values():
        for package in feature.get("repo", []) + feature.get("aur", []):
            if not re.fullmatch(r"[a-zA-Z0-9@_+][a-zA-Z0-9@._+:-]*", package):
                raise VeloraError(f"Invalid package name in manifest: {package!r}")
            if package.startswith("illogical-impulse-"):
                raise VeloraError("Legacy metapackages are not supported by Velora.")
    return data["features"]


def preferences():
    return read_json(state_dir() / "installation.json")


def package_metadata():
    return read_json(ROOT / ".velora-package.json")


def update_options():
    saved = read_json(state_dir() / "update-settings.json")
    return {"channel": saved.get("channel", "branch"),
            "automatic_checks": saved.get("automatic_checks", not preferences().get("no_updates", False))}


def configure_updates(args):
    options = update_options()
    if args.channel is not None:
        options["channel"] = args.channel
    if args.automatic_checks is not None:
        enabled = args.automatic_checks == "on"
        service = xdg("XDG_CONFIG_HOME", ".config") / "systemd/user/velora-update.service"
        if not service.exists():
            raise VeloraError("Run 'velora install' before enabling scheduled update checks.")
        run(["systemctl", "--user", "daemon-reload"])
        run(["systemctl", "--user", "enable" if enabled else "disable", "--now", "velora-update.timer"])
        options["automatic_checks"] = enabled
    write_json(state_dir() / "update-settings.json", options)
    print(json.dumps(options))


def latest_release(repository):
    match = re.fullmatch(r"(?:https://github\.com/|git@github\.com:)([\w.-]+)/([\w.-]+?)(?:\.git)?/?", repository)
    if not match:
        raise VeloraError("The release channel requires a github.com repository remote.")
    owner, name = match.groups()
    request = Request(f"https://api.github.com/repos/{owner}/{name}/releases/latest",
                      headers={"Accept": "application/vnd.github+json", "User-Agent": "Velora-updater"})
    try:
        with urlopen(request, timeout=20) as response:
            release = json.load(response)
    except HTTPError as error:
        if error.code == 404:
            raise VeloraError("No published GitHub release is available. Choose branch updates to follow development changes.") from error
        raise VeloraError(f"GitHub release lookup failed (HTTP {error.code}). Try again later.") from error
    except (URLError, TimeoutError, OSError, ValueError) as error:
        raise VeloraError(f"Could not check GitHub releases: {error}") from error
    tag = release.get("tag_name")
    if not isinstance(tag, str) or not tag or release.get("draft") or release.get("prerelease"):
        raise VeloraError("GitHub did not return a published stable release.")
    run(["git", "check-ref-format", f"refs/tags/{tag}"], capture=True)
    return {"version": tag, "url": release.get("html_url", "")}


def compare_package_revision(repository, current, target):
    if current == target:
        return 0, 0
    match = re.fullmatch(r"(?:https://github\.com/|git@github\.com:)([\w.-]+)/([\w.-]+?)(?:\.git)?/?", repository)
    if not match:
        raise VeloraError("Package updates require a GitHub repository URL.")
    owner, name = match.groups()
    request = Request(f"https://api.github.com/repos/{owner}/{name}/compare/{current}...{target}",
                      headers={"Accept": "application/vnd.github+json", "User-Agent": "Velora-updater"})
    try:
        with urlopen(request, timeout=20) as response:
            comparison = json.load(response)
        if comparison.get("status") not in ("ahead", "behind", "identical", "diverged"):
            raise ValueError("GitHub returned an unknown commit relationship")
        return int(comparison["behind_by"]), int(comparison["ahead_by"])
    except (URLError, TimeoutError, OSError, ValueError, KeyError) as error:
        raise VeloraError("Could not compare the installed package with GitHub. Ensure its source commit is published before updating: " + str(error)) from error


def build_metadata(root=None):
    root = ROOT if root is None else root
    existing = read_json(root / ".velora-package.json")
    if existing:
        return existing
    revision = run(["git", "rev-parse", "HEAD"], cwd=root, capture=True)
    branch = run(["git", "branch", "--show-current"], cwd=root, capture=True)
    return {"version": (root / "VERSION").read_text().strip(),
            "source_revision": revision,
            "source_repository": run(["git", "remote", "get-url", "origin"], cwd=root, capture=True),
            "source_branch": branch or "main",
            "commit_count": int(run(["git", "rev-list", "--count", "HEAD"], cwd=root, capture=True))}


def prepare_source_tree():
    status = run(["git", "submodule", "status", "--recursive"], cwd=ROOT, capture=True)
    if any(line and line[0] in "-+U" for line in status.splitlines()):
        run(["git", "submodule", "update", "--init", "--recursive"], cwd=ROOT)


def source_selection(args, features, *, wizard=False):
    selection = args.build_from_source
    saved = preferences().get("build_from_source", [])
    allowed = {pkg for item in features.values() for pkg in item.get("repo", []) + item.get("aur", [])}
    if selection is None:
        selected = [pkg for pkg in saved if pkg in allowed]
    else:
        selected = sorted(set(filter(None, selection.split(","))))
    if wizard and selection is None and sys.stdin.isatty() and not args.yes and not args.dry_run:
        choice = input("Build dependencies from source [Enter to keep " + (", ".join(selected) or "none")
                       + "; 'core' for Hyprland/Quickshell, package names, or 'none']: ").strip()
        if choice:
            selected = [] if choice == "none" else ["hyprland", "quickshell"] if choice == "core" else sorted(set(choice.replace(" ", "").split(",")))
    invalid = set(selected) - allowed
    if invalid:
        raise VeloraError("Source builds must name dependencies in the selected components: " + ", ".join(sorted(invalid)))
    binary = [pkg for pkg in selected if pkg.endswith("-bin")]
    if binary:
        raise VeloraError("Binary-only recipes cannot be built from source: " + ", ".join(binary))
    aur = {pkg for item in features.values() for pkg in item.get("aur", [])}
    if args.skip_aur and aur.intersection(selected):
        raise VeloraError("--skip-aur conflicts with a selected AUR source build.")
    args.source_packages = sorted(selected)
    return args.source_packages


def selected_features(args, *, wizard=False):
    features = manifest()
    saved = preferences()
    excluded = set(saved.get("without", [])) if args.without is None else set(filter(None, args.without.split(",")))
    unknown = excluded - features.keys()
    required = {name for name, item in features.items() if item.get("required")}
    if unknown or excluded & required:
        raise VeloraError("Unknown or required features cannot be excluded: "
                          + ", ".join(sorted(unknown | (excluded & required))))
    if wizard and sys.stdin.isatty() and not args.yes and not args.dry_run:
        optional = [name for name in features if name not in required]
        print("\nVelora installer — Arch Linux\n")
        print("Required: " + ", ".join(sorted(required)))
        for index, name in enumerate(optional, 1):
            marker = " " if name in excluded else "x"
            print(f"  {index}. [{marker}] {name}: {features[name]['description']}")
        choice = input("\nKeep selection [Enter], or enter optional component numbers (or 'none'): ").strip()
        if choice:
            try:
                numbers = [] if choice.lower() == "none" else [int(part) for part in choice.replace(",", " ").split()]
                if any(number < 1 or number > len(optional) for number in numbers):
                    raise ValueError
            except ValueError as error:
                raise VeloraError("Enter component numbers from the list, separated by spaces.") from error
            chosen = {optional[number - 1] for number in numbers}
            excluded = set(optional) - chosen
    return {name: item for name, item in features.items() if name not in excluded}, sorted(excluded)


def missing_packages(packages):
    """The packages that are not installed, counting ones provided by another package (curl-git provides curl)."""
    packages = list(packages)
    if not packages or not shutil.which("pacman"):
        return packages
    try:
        # pacman -T prints the dependencies nothing installed satisfies and exits with 127 when there are some
        result = subprocess.run(["pacman", "-T", "--", *packages], text=True, capture_output=True, timeout=120,
                                env=dict(os.environ, LANG="C.UTF-8", LC_ALL="C.UTF-8"))
        if result.returncode in (0, 127):
            return [line.strip() for line in result.stdout.splitlines() if line.strip()]
    except (OSError, subprocess.TimeoutExpired):
        pass
    installed = set(run(["pacman", "-Qq"], capture=True).splitlines())
    return [pkg for pkg in packages if pkg not in installed]


def package_plan(features, skip_aur=False, source_packages=()):
    repo = sorted({pkg for item in features.values() for pkg in item.get("repo", [])})
    aur = [] if skip_aur else sorted({pkg for item in features.values() for pkg in item.get("aur", [])})
    missing = set(missing_packages(repo + aur))
    return [pkg for pkg in repo if pkg in missing and pkg not in source_packages], [pkg for pkg in aur if pkg in missing and pkg not in source_packages]


GOOGLE_SANS_FLEX = "https://github.com/end-4/google-sans-flex"


def font_installed(family):
    if not shutil.which("fc-list"):
        return False
    return family.lower() in run(["fc-list", ":", "family"], capture=True).lower()


def install_fonts(dry=False):
    """The shell's default font isn't packaged for Arch, so it is fetched into the user's fonts once.
    A failure only warns: the shell falls back to another font."""
    if font_installed("Google Sans Flex"):
        return
    target = xdg("XDG_DATA_HOME", ".local/share") / "fonts/velora-google-sans-flex"
    if dry:
        print(f"  Would download the Google Sans Flex font from {GOOGLE_SANS_FLEX} into {target}")
        return
    print("Installing the Google Sans Flex font...", flush=True)
    try:
        with tempfile.TemporaryDirectory(prefix="velora-font-") as temporary:
            checkout = Path(temporary) / "font"
            run(["git", "clone", "--depth", "1", "--", GOOGLE_SANS_FLEX, checkout], timeout=600)
            fonts = [path for path in checkout.rglob("*") if path.suffix.lower() in (".ttf", ".otf")]
            if not fonts:
                raise VeloraError("The font repository has no font files.")
            target.mkdir(parents=True, exist_ok=True)
            for font in fonts:
                shutil.copy2(font, target / font.name)
        if shutil.which("fc-cache"):
            run(["fc-cache", "-f", target])
    except VeloraError as error:
        print(f"Warning: Google Sans Flex was not installed ({error}). Install it later with 'velora deps'.", file=sys.stderr)


def preflight(args, features):
    errors = []
    for tool in ("bash", "git", "python3"):
        if not shutil.which(tool):
            errors.append(f"Missing command: {tool}")
    if not args.skip_packages:
        for tool in ("pacman", "sudo"):
            if not shutil.which(tool):
                errors.append(f"Missing command: {tool}. Package installation supports Arch Linux only.")
    for source in ("dots/.config/hypr", "dots/.config/quickshell", "home/.zshrc", "home/.tmux.conf",
                   "dots/.config/illogical-impulse/config.example.json", "dependencies/python/requirements.txt"):
        if not (ROOT / source).exists():
            errors.append(f"Repository file is missing: {source}. Use a complete clone of Velora.")
    if errors:
        raise VeloraError("Preflight failed:\n  - " + "\n  - ".join(errors))


def install_dependencies(args, features):
    sources = getattr(args, "source_packages", [])
    repo, aur = package_plan(features, args.skip_aur, sources)
    print(f"Dependencies: {len(repo)} missing Arch packages, {len(aur)} missing AUR packages.", flush=True)
    if repo:
        # Arch requires full upgrades when refreshing repository databases.
        run(["sudo", "pacman", "-Syu", "--needed", "--", *repo], dry=args.dry_run)
    if sources:
        prerequisites = ["base-devel", "git"]
        if any(pkg in item.get("repo", []) for pkg in sources for item in features.values()):
            prerequisites.append("devtools")
        run(["sudo", "pacman", "-Syu", "--needed", "--", *prerequisites], dry=args.dry_run)
        official = {pkg for item in features.values() for pkg in item.get("repo", [])}
        for name in sources:
            builds.build_dependency(name, official=name in official, run=run,
                                   state=state_dir() / "source-builds",
                                   cache=xdg("XDG_CACHE_HOME", ".cache") / "velora/packages",
                                   dry=args.dry_run, force=args.rebuild)
    if aur:
        helper = shutil.which("yay") or shutil.which("paru")
        if not helper:
            if args.dry_run:
                print("  Would build yay from https://aur.archlinux.org/yay.git using makepkg.")
            else:
                print("No AUR helper found. Building yay from its AUR recipe.", flush=True)
                with tempfile.TemporaryDirectory(prefix="velora-yay-") as temporary:
                    checkout = Path(temporary) / "yay"
                    run(["git", "clone", "--depth=1", "https://aur.archlinux.org/yay.git", checkout])
                    run(["makepkg", "-si", "--needed"], cwd=checkout)
            helper = shutil.which("yay") or "yay"
        run([helper, "-S", "--needed", "--", *aur], dry=args.dry_run)
    venv = xdg("XDG_STATE_HOME", ".local/state") / "quickshell/.venv"
    if not (venv / "bin/python").exists():
        run(["uv", "venv", "--python", "3.12", str(venv)], dry=args.dry_run)
    run(["uv", "pip", "sync", "--python", str(venv / "bin/python"),
         str(ROOT / "dependencies/python/requirements.txt")], dry=args.dry_run)
    run(["sudo", "systemctl", "enable", "--now", "power-profiles-daemon"], dry=args.dry_run)


def restore_journal(journal):
    if not journal.exists():
        raise VeloraError(f"Installation journal does not exist: {journal}")
    entries = [json.loads(line) for line in journal.read_text().splitlines() if line.strip()]
    # Validate the whole journal before restoring any target.
    for entry in entries:
        target, backup = Path(entry["target"]), entry["backup"]
        if not target.is_absolute() or (backup and not Path(os.path.abspath(backup)).is_relative_to(journal.parent.absolute())):
            raise VeloraError("Invalid path in the installation journal.")
        if backup and not os.path.lexists(backup):
            raise VeloraError(f"Backup is missing: {backup}. No files have been restored.")
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    for index, entry in enumerate(reversed(entries)):
        target = Path(entry["target"])
        if os.path.lexists(target):
            # Keep later edits as well, including user-created directories.
            recovery = journal.parent / f"before-restore-{stamp}" / str(index)
            recovery.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(target), recovery)
        if entry["backup"]:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(entry["backup"], target)
    journal.rename(journal.with_suffix(".restored"))
    print(f"Configuration restored. Later files were kept in {journal.parent}.")


def journal_file(journal, target, content=None, link=None, remove=False):
    target.parent.mkdir(parents=True, exist_ok=True)
    if link and target.is_symlink() and target.resolve() == link.resolve():
        return
    if content is not None and target.is_file() and not target.is_symlink() and target.read_text() == content:
        return
    backup = ""
    if os.path.lexists(target):
        backup = str(journal.parent / "integration" / str(len(journal.read_text().splitlines())))
        Path(backup).parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(target), backup)
    with journal.open("a") as output:
        output.write(json.dumps({"target": str(target), "backup": backup}) + "\n")
    if remove:
        return
    if link:
        target.symlink_to(link)
    else:
        target.write_text(content)


def systemd_quote(value):
    # systemd expands percent specifiers and dollar variables inside ExecStart.
    return '"' + str(value).replace("\\", "\\\\").replace('"', '\\"').replace("%", "%%").replace("$", "$$") + '"'


def desktop_quote(value):
    value = str(value)
    for character in ("\\", '"', "`", "$"):
        value = value.replace(character, "\\" + character)
    return '"' + value.replace("\\", "\\\\").replace("%", "%%") + '"'


def register_installation(journal, args, without):
    config = xdg("XDG_CONFIG_HOME", ".config")
    data = xdg("XDG_DATA_HOME", ".local/share")
    binary = Path.home() / ".local/bin/velora"
    journal_file(journal, binary, link=ROOT / "velora")
    journal_file(journal, data / "applications/velora-update.desktop", content=(
        "[Desktop Entry]\nType=Application\nName=Update Velora\n"
        "Comment=Review and install Velora updates\nIcon=system-software-update\n"
        f"Exec={desktop_quote(ROOT / 'velora')} update --interactive\nTerminal=true\nCategories=Settings;DesktopSettings;\n"))
    # systemd calls the entry point directly, without relying on the login PATH.
    service = ("[Unit]\nDescription=Check for Velora updates\n\n[Service]\nType=oneshot\n"
               f"ExecStart=/usr/bin/bash {systemd_quote(ROOT / 'velora')} update --check --notify\n"
               "Environment=GIT_TERMINAL_PROMPT=0\nTimeoutStartSec=90\n")
    timer = ("[Unit]\nDescription=Check for Velora updates every six hours\n\n[Timer]\n"
             "OnStartupSec=5min\nOnUnitActiveSec=6h\nRandomizedDelaySec=10min\n\n"
             "[Install]\nWantedBy=timers.target\n")
    journal_file(journal, config / "systemd/user/velora-update.service", content=service)
    journal_file(journal, config / "systemd/user/velora-update.timer", content=timer)
    timer_link = config / "systemd/user/timers.target.wants/velora-update.timer"
    automatic = not args.no_updates and update_options()["automatic_checks"]
    if not automatic:
        if os.path.lexists(timer_link):
            journal_file(journal, timer_link, remove=True)
    else:
        journal_file(journal, timer_link, link=config / "systemd/user/velora-update.timer")
    journal_file(journal, state_dir() / "installation.json", content=json.dumps({
        "repository": str(ROOT), "without": without, "skip_aur": args.skip_aur,
        "skip_packages": args.skip_packages, "no_updates": args.no_updates,
        "build_from_source": getattr(args, "source_packages", []),
        "installation_type": "package" if package_metadata() else "checkout",
    }, indent=2) + "\n")
    if shutil.which("systemctl"):
        try:
            run(["systemctl", "--user", "daemon-reload"])
            run(["systemctl", "--user", "start" if automatic else "stop", "velora-update.timer"])
        except VeloraError:
            print("Automatic checks could not start. After login, run: systemctl --user enable --now velora-update.timer")


def install(args):
    features, without = selected_features(args, wizard=True)
    # Persist the user's AUR choice, including for subsequent updates.
    if args.skip_aur is None:
        args.skip_aur = preferences().get("skip_aur", False)
    source_selection(args, features, wizard=True)
    if args.build_package is None and sys.stdin.isatty() and not args.yes and not args.dry_run and not package_metadata():
        args.build_package = input("Build and install Velora as an Arch package? [y/N] ").strip().lower() in ("y", "yes")
    preflight(args, features)
    print("\nInstallation plan", flush=True)
    print("  Components: " + ", ".join(features))
    print(f"  Configuration: {xdg('XDG_CONFIG_HOME', '.config')}")
    print("  Existing files: back up before replacing; restore on linking failure")
    print("  Dependencies: " + ("keep installed packages and Python environment" if args.skip_packages else "install missing packages and sync the locked Python environment"))
    print("  Source builds: " + (", ".join(args.source_packages) or "none"))
    print("  Velora installation: " + ("build an Arch package" if args.build_package else "system package" if package_metadata() else "current checkout"))
    if not args.skip_packages and not args.skip_aur and not (shutil.which("yay") or shutil.which("paru")):
        print("  AUR helper: build yay from AUR if needed (use --skip-aur to omit AUR packages)")
    print("  Update checks: " + ("disabled" if args.no_updates else "every six hours; install on request"))
    if args.dry_run:
        if args.build_package:
            builds.build_package(ROOT, xdg("XDG_CACHE_HOME", ".cache") / "velora/packages", {}, run, dry=True, install=True)
        if not args.skip_packages:
            install_dependencies(args, features)
        install_fonts(dry=True)
        run(["bash", ROOT / "scripts/install.sh", "--dry-run", "--skip-packages", "--no-reload"])
        print("Would register the velora command, update launcher and user timer. No files changed.")
        return
    if sys.stdin.isatty() and not args.yes:
        if input("\nInstall this configuration? [Y/n] ").strip().lower() not in ("", "y", "yes"):
            print("Installation cancelled.")
            return
    elif not sys.stdin.isatty() and not args.yes:
        raise VeloraError("For unattended installation, pass --yes. Use --dry-run to inspect the plan.")
    if args.build_package:
        if package_metadata():
            raise VeloraError("Velora is already installed as a package. Use 'velora package' to rebuild its archive.")
        prepare_source_tree()
        builds.build_package(ROOT, xdg("XDG_CACHE_HOME", ".cache") / "velora/packages", build_metadata(), run, install=True)
        run(install_command(Path("/usr/bin/velora"), args, without),
            env=dict(os.environ, VELORA_PARENT_OPERATION=str(os.getpid())))
        return
    if not args.skip_packages:
        install_dependencies(args, features)
    # Finish network operations before replacing any configuration files.
    if not package_metadata():
        run(["git", "submodule", "update", "--init", "--recursive"], cwd=ROOT)
    install_fonts()
    backup = state_dir() / "backups" / datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    backup.mkdir(parents=True)
    journal = backup / "journal.jsonl"
    journal.touch()
    environment = dict(os.environ, VELORA_BACKUP_ROOT=str(backup), VELORA_INSTALL_JOURNAL=str(journal))
    if package_metadata():
        runtime = xdg("XDG_DATA_HOME", ".local/share") / "velora/runtime"
        conflicts = sync_runtime(ROOT, runtime)
        environment["VELORA_SOURCE_ROOT"] = str(runtime)
        if conflicts:
            print("Local edits preserved. Review incoming templates in " + str(runtime / ".incoming"))
            for conflict in conflicts:
                print("  " + conflict)
    try:
        run(["bash", ROOT / "scripts/install.sh", "--skip-packages", "--no-reload"], env=environment)
        register_installation(journal, args, without)
    except (Exception, KeyboardInterrupt):
        print("Installation did not finish. Restoring configuration files...", file=sys.stderr)
        restore_journal(journal)
        raise
    if not args.no_reload and os.environ.get("HYPRLAND_INSTANCE_SIGNATURE") and shutil.which("hyprctl"):
        try:
            run(["hyprctl", "reload"])
        except VeloraError:
            print("Configuration installed. Hyprland reload failed; log in again to load it.")
    print(f"\nVelora installed. Backup: {backup}\nRestore with: velora restore {backup.name}")
    print("Open Settings with Super+I. Update Velora from Settings > About, or run: velora update")
    print("User configuration lives in the writable runtime directory." if package_metadata()
          else "Keep the checkout in place: your configuration links point to it.")


def install_command(binary, args, without):
    command = [binary, "install", "--yes", "--without", ",".join(without),
               "--build-from-source", ",".join(getattr(args, "source_packages", []))]
    for attribute, flag in (("skip_aur", "--skip-aur"), ("skip_packages", "--skip-packages"),
                            ("no_updates", "--no-updates"), ("no_reload", "--no-reload")):
        if getattr(args, attribute, False):
            command.append(flag)
    return command


def git(*args):
    return run(["git", *args], cwd=ROOT, capture=True, timeout=60)


def update_status(*, fetch=True, channel=None):
    channel = channel or update_options()["channel"]
    packaged = package_metadata()
    if packaged:
        repository = packaged["source_repository"]
        branch = packaged["source_branch"]
        release = latest_release(repository) if channel == "release" and fetch else {}
        reference = f"refs/tags/{release['version']}" if release else f"refs/heads/{branch}"
        current = packaged["source_revision"]
        target = current
        if fetch:
            lines = run(["git", "ls-remote", "--", repository, reference, reference + "^{}"], capture=True, timeout=60).splitlines()
            refs = dict(line.split("\t", 1)[::-1] for line in lines if "\t" in line)
            target = refs.get(reference + "^{}", refs.get(reference, ""))
            if not re.fullmatch(r"[0-9a-f]{40,64}", target):
                raise VeloraError("The requested update reference is unavailable on GitHub.")
        else:
            cached = read_json(state_dir() / "update.json")
            if cached.get("channel") == channel:
                target = cached.get("target", current)
        ahead, behind = compare_package_revision(repository, current, target) if fetch else (0, int(target != current))
        return {"branch": branch, "repository": repository, "upstream": reference,
                "current": current, "target": target, "available": behind > 0,
                "ahead": ahead, "behind": behind, "dirty": False, "diverged": ahead > 0 and behind > 0,
                "current_version": packaged["version"], "latest_version": release.get("version", target[:12]),
                "release_url": release.get("url", ""), "installation_type": "package", "channel": channel,
                "checked_at": datetime.now(timezone.utc).isoformat(), "error": ""}
    branch = git("symbolic-ref", "--quiet", "--short", "HEAD")
    remote = git("config", f"branch.{branch}.remote")
    if remote == ".":
        raise VeloraError("Select a branch tracking your Velora remote before updating.")
    repository = git("remote", "get-url", remote)
    release = latest_release(repository) if channel == "release" and fetch else {}
    if release:
        git("fetch", "--no-recurse-submodules", "--", remote,
            f"+refs/tags/{release['version']}:refs/velora/releases/latest")
        upstream = "refs/velora/releases/latest^{commit}"
    elif channel == "release":
        upstream = "refs/velora/releases/latest^{commit}"
    else:
        if fetch:
            git("fetch", "--no-recurse-submodules", "--", remote)
        upstream = git("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}")
    ahead, behind = map(int, git("rev-list", "--left-right", "--count", f"HEAD...{upstream}").split())
    current = git("rev-parse", "HEAD")
    target = git("rev-parse", upstream)
    version_file = ROOT / "VERSION"
    version = version_file.read_text().strip() if version_file.exists() else current[:12]
    return {"branch": branch, "upstream": upstream, "current": git("rev-parse", "HEAD"),
            "target": target, "ahead": ahead, "behind": behind,
            "available": behind > 0, "diverged": ahead > 0 and behind > 0,
            "repository": repository, "channel": channel, "installation_type": "checkout",
            "current_version": version, "latest_version": release.get("version", target[:12]),
            "release_url": release.get("url", ""),
            "dirty": bool(git("status", "--porcelain", "--untracked-files=normal")),
            "checked_at": datetime.now(timezone.utc).isoformat(), "error": ""}


def update(args):
    if args.interactive and not sys.stdin.isatty():
        raise VeloraError("Interactive updates must be opened in a terminal.")
    try:
        status = update_status(fetch=not args.dry_run, channel=args.channel)
    except VeloraError as error:
        if not args.dry_run:
            previous = read_json(state_dir() / "update.json")
            write_json(state_dir() / "update.json", {**previous, "error": str(error),
                       "checked_at": datetime.now(timezone.utc).isoformat()})
        raise
    if args.dry_run:
        print(json.dumps(status, indent=2))
        print("Dry run: compared cached Git refs; did not fetch or change files.")
        return
    previous = read_json(state_dir() / "update.json")
    write_json(state_dir() / "update.json", status)
    if args.json:
        print(json.dumps(status))
    else:
        print(f"Velora: installed {status['current_version']} ({status['current'][:12]}), available {status['latest_version']}.")
    if args.check:
        if args.notify and status["available"] and previous.get("target") != status["target"] and shutil.which("notify-send"):
            try:
                run(["notify-send", "--app-name=Velora", "Velora update available",
                     "Open Settings > About > Install update, or run velora update."])
            except VeloraError:
                print("Update status saved. The desktop notification service is unavailable.")
        return
    if status["diverged"]:
        raise VeloraError("This branch has diverged from its remote. Merge or rebase your commits before updating; no files were replaced.")
    if status["dirty"]:
        raise VeloraError("Local changes are present. Review 'git status' and commit your work before updating. Velora will not stash or overwrite it.")
    if not status["available"]:
        print("Already up to date. To repair an existing installation, run: velora install")
        return
    if args.interactive:
        if status["installation_type"] == "checkout":
            print(git("log", "--oneline", f"HEAD..{status['upstream']}"))
        elif status.get("release_url"):
            print(status["release_url"])
        if input("\nInstall these updates and reconcile dependencies? [Y/n] ").strip().lower() not in ("", "y", "yes"):
            print("Update cancelled.")
            return
    old = status["current"]
    write_json(state_dir() / "last-update.json", {"previous": old, "target": status["target"], "complete": False})
    if status["installation_type"] == "package":
        with tempfile.TemporaryDirectory(prefix="velora-update-") as temporary:
            checkout = Path(temporary) / "source"
            run(["git", "clone", "--branch", status["branch"], "--single-branch", "--", status["repository"], checkout])
            run(["git", "checkout", "--detach", status["target"]], cwd=checkout)
            run(["git", "submodule", "update", "--init", "--recursive"], cwd=checkout)
            metadata = build_metadata(checkout)
            metadata["source_branch"] = status["branch"]
            builds.build_package(checkout, xdg("XDG_CACHE_HOME", ".cache") / "velora/packages", metadata, run, install=True)
        saved = preferences()
        install_args = argparse.Namespace(**saved, source_packages=saved.get("build_from_source", []))
        run(install_command(Path("/usr/bin/velora"), install_args, saved.get("without", [])),
            env=dict(os.environ, VELORA_PARENT_OPERATION=str(os.getpid())))
        write_json(state_dir() / "last-update.json", {"previous": old, "target": status["target"], "complete": True})
        write_json(state_dir() / "update.json", {**status, "current": status["target"], "available": False,
                   "current_version": metadata["version"], "behind": 0})
        print("Velora package updated. Restart Quickshell or log in again to load all changes.")
        return
    # Pin the fetched commit so another fetch cannot change what the user reviewed.
    git("merge", "--ff-only", status["target"])
    saved = preferences()
    command = [ROOT / "velora", "install", "--yes", "--without", ",".join(saved.get("without", []))]
    command += ["--build-from-source", ",".join(saved.get("build_from_source", []))]
    for key, option in (("skip_aur", "--skip-aur"), ("skip_packages", "--skip-packages"), ("no_updates", "--no-updates")):
        if saved.get(key):
            command.append(option)
    try:
        # The update process holds the lock; the child is the same operation.
        run(command, env=dict(os.environ, VELORA_PARENT_OPERATION=str(os.getpid())))
    except VeloraError:
        raise VeloraError("Source updated, but installation did not finish. Fix the reported error and run 'velora install --yes'. "
                          f"Previous source commit: {old}. See 'velora status' for recovery details.")
    write_json(state_dir() / "last-update.json", {"previous": old, "target": status["target"], "complete": True})
    write_json(state_dir() / "update.json", update_status(fetch=False))
    print("Update installed. Restart Quickshell or log in again to load all changes.")


def doctor(args):
    failed = False
    print("Velora diagnostics — Arch Linux")
    for tool in ("python3", "bash", "git", "pacman", "uv", "Hyprland", "qs", "systemctl"):
        found = shutil.which(tool)
        print(f"  {'OK' if found else 'MISSING'}  {tool}" + (f": {found}" if found else ""))
        failed |= found is None
    print("  AUR helper: " + (shutil.which("yay") or shutil.which("paru") or "not installed (use --skip-aur)"))
    features, _ = selected_features(args)
    repo, aur = package_plan(features)
    print("  Missing official packages: " + (", ".join(repo) or "none"))
    print("  Missing AUR packages: " + (", ".join(aur) or "none"))
    venv = xdg("XDG_STATE_HOME", ".local/state") / "quickshell/.venv/bin/python"
    print("  Python environment: " + (str(venv) if venv.exists() else "missing; run velora deps"))
    font = font_installed("Google Sans Flex")
    print("  Google Sans Flex font: " + ("installed" if font else "missing; run velora deps"))
    if failed or repo or not venv.exists() or not font:
        raise VeloraError("Some checks need attention. Run 'velora install --dry-run' to inspect the repair plan.")


def parser():
    result = argparse.ArgumentParser(prog="velora", description="Velora — install, maintain and update your Arch desktop.")
    commands = result.add_subparsers(dest="command")
    for name, description in (("install", "Guided installation or repair"), ("deps", "Install missing dependencies"), ("doctor", "Check the installation without changing it")):
        sub = commands.add_parser(name, help=description)
        sub.add_argument("--without", default=None, help="Comma-separated optional features to omit")
        sub.add_argument("--dry-run", action="store_true", help="Show changes without applying them")
        sub.add_argument("--skip-aur", action="store_true", default=None)
        sub.add_argument("--skip-packages", action="store_true")
        sub.add_argument("--yes", action="store_true", help="Accept the installer plan; package managers still ask normally")
        sub.add_argument("--no-reload", action="store_true")
        sub.add_argument("--no-updates", action="store_true", help="Do not enable background update checks")
        sub.add_argument("--build-from-source", nargs="?", const="hyprland,quickshell", default=None,
                         metavar="PACKAGES", help="Build core dependencies or comma-separated package names from source")
        sub.add_argument("--no-source-builds", dest="build_from_source", action="store_const", const="",
                         help="Use repository/AUR packages instead of saved source builds")
        sub.add_argument("--rebuild", action="store_true", help="Rebuild selected source packages even when their recipes are unchanged")
        if name == "install":
            sub.add_argument("--build-package", action="store_true", default=None,
                             help="Build Velora as an Arch package and install it automatically")
    sub = commands.add_parser("update", help="Check or install updates from your tracked Velora branch")
    sub.add_argument("--check", action="store_true", help="Check only; never install")
    sub.add_argument("--notify", action="store_true", help="Notify once for each new target commit")
    sub.add_argument("--json", action="store_true")
    sub.add_argument("--dry-run", action="store_true")
    sub.add_argument("--interactive", action="store_true", help="Review commits before installing")
    sub.add_argument("--channel", choices=("branch", "release"), help="Check branch changes or the latest published GitHub release")
    sub = commands.add_parser("update-settings", help="Configure the GitHub update channel and automatic checks")
    sub.add_argument("--channel", choices=("branch", "release"))
    sub.add_argument("--automatic-checks", choices=("on", "off"))
    sub = commands.add_parser("package", help="Build a self-contained Velora Arch package from these sources")
    sub.add_argument("--output", type=Path, help="Directory for the .pkg.tar.zst archive")
    sub.add_argument("--install", action="store_true", help="Install the built package with pacman")
    sub.add_argument("--dry-run", action="store_true")
    commands.add_parser("status", help="Show saved installation and update state")
    commands.add_parser("components", help="List available dependency components")
    sub = commands.add_parser("restore", help="Restore configuration files from a Velora installation backup")
    sub.add_argument("backup", nargs="?", help="Backup ID; omit to list available backups")
    sub.add_argument("--yes", action="store_true")
    return result


def main(argv=None):
    cli = parser()
    args = cli.parse_args(argv)
    if args.command is None:
        if sys.stdin.isatty():
            args = cli.parse_args(["install"])
        else:
            cli.print_help()
            return 0
    if args.command == "components":
        for name, item in manifest().items():
            print(f"{name:18} {'required' if item.get('required') else 'optional':8} {item['description']}")
        return 0
    if args.command == "status":
        print(json.dumps({"installation": preferences(), "update": read_json(state_dir() / "update.json"),
                          "update_settings": update_options(),
                          "last_update": read_json(state_dir() / "last-update.json")}, indent=2))
        return 0
    if args.command == "update-settings" and args.channel is None and args.automatic_checks is None:
        print(json.dumps(update_options()))
        return 0
    mutating = args.command in ("install", "deps", "restore", "package", "update-settings") or (args.command == "update" and not args.check)
    if mutating and not getattr(args, "dry_run", False) and os.geteuid() == 0:
        raise VeloraError("Run Velora as your normal user. It requests sudo only for system packages and services.")

    def execute():
        if args.command == "install":
            install(args)
        elif args.command == "deps":
            features, _ = selected_features(args)
            if args.skip_aur is None:
                args.skip_aur = preferences().get("skip_aur", False)
            source_selection(args, features)
            preflight(args, features)
            install_dependencies(args, features)
            install_fonts(dry=args.dry_run)
        elif args.command == "doctor":
            doctor(args)
        elif args.command == "update":
            update(args)
        elif args.command == "update-settings":
            configure_updates(args)
        elif args.command == "package":
            output = (args.output or xdg("XDG_CACHE_HOME", ".cache") / "velora/packages").expanduser().absolute()
            if not args.dry_run and not package_metadata():
                prepare_source_tree()
            builds.build_package(ROOT, output, {} if args.dry_run else build_metadata(), run,
                                 dry=args.dry_run, install=args.install)
        elif args.command == "restore":
            backups = state_dir() / "backups"
            if args.backup is None:
                print("Available configuration backups:")
                for journal in sorted(backups.glob("*/journal.jsonl"), reverse=True):
                    print("  " + journal.parent.name)
                return
            if Path(args.backup).name != args.backup:
                raise VeloraError("Pass a backup ID from 'velora restore', rather than a path.")
            if not args.yes:
                if not sys.stdin.isatty():
                    raise VeloraError("Use --yes for unattended restoration.")
                if input("Restore configuration from this backup? [y/N] ").lower() not in ("y", "yes"):
                    return
            restore_journal(backups / args.backup / "journal.jsonl")
            if shutil.which("systemctl"):
                try:
                    run(["systemctl", "--user", "stop", "velora-update.timer"])
                    run(["systemctl", "--user", "daemon-reload"])
                    timer_link = xdg("XDG_CONFIG_HOME", ".config") / "systemd/user/timers.target.wants/velora-update.timer"
                    if timer_link.exists():
                        run(["systemctl", "--user", "start", "velora-update.timer"])
                except VeloraError:
                    print("Files restored. Log in again to refresh the user timer state.")

    parent_operation = os.environ.get("VELORA_PARENT_OPERATION") == str(os.getppid())
    if getattr(args, "dry_run", False) or args.command == "doctor" or parent_operation or (args.command == "restore" and args.backup is None):
        execute()
    else:
        with operation_lock():
            execute()
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (VeloraError, OSError, ValueError) as error:
        print(f"\nVelora: {error}", file=sys.stderr)
        raise SystemExit(1)
    except KeyboardInterrupt:
        print("\nVelora: operation interrupted.", file=sys.stderr)
        raise SystemExit(130)
