"""Arch source builds and self-contained Velora package preparation."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import tarfile
import tempfile


def copy_source(source, destination, root):
    """Copy source files without developer metadata or machine-specific symlinks."""
    if source.is_symlink():
        resolved = source.resolve()
        if not resolved.is_relative_to(root.resolve()):
            raise ValueError(f"Source symlink points outside the project: {source}")
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.symlink_to(os.path.relpath(resolved, source.parent.resolve()))
    elif source.is_dir():
        destination.mkdir(parents=True, exist_ok=True)
        for child in sorted(source.iterdir()):
            if child.name not in (".git", "__pycache__", ".venv"):
                copy_source(child, destination / child.name, root)
    else:
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)


def prepare_package(root, directory, metadata, run):
    directory.mkdir(parents=True, exist_ok=True)
    snapshot = directory / "snapshot/velora"
    snapshot.mkdir(parents=True)
    if (root / ".git").exists():
        # Include new project files, but honor .gitignore and exclude deleted paths.
        # NUL output is not stripped: whitespace can legitimately be part of a filename.
        names = run(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=root, capture=True).split("\0")
        for name in sorted(set(filter(None, names))):
            relative = Path(name)
            if relative.is_absolute() or ".." in relative.parts:
                raise ValueError("Invalid source path reported by Git")
            source = root / relative
            if (source.exists() or source.is_symlink()) and relative.parts[0] not in (".agents", ".aws", ".codex", ".git", "artifacts", "cache"):
                copy_source(source, snapshot / relative, root)
    else:
        for name in ("velora", "install.sh", "setup", "diagnose", "VERSION", "README.md", "LICENSE", "NOTICE",
                     "scripts", "dependencies", "packaging", "docs", "licenses", "dots", "home", "dots-extra"):
            source = root / name
            if source.exists():
                copy_source(source, snapshot / name, root)
    # Never package runtime credentials or install state, even if tracked accidentally.
    private = snapshot / "dots/.config/illogical-impulse"
    for name in ("config.json", "installed_true", "installed_listfile"):
        path = private / name
        if path.exists() or path.is_symlink():
            path.unlink()
    (snapshot / ".velora-package.json").write_text(json.dumps(metadata, indent=2) + "\n")
    version = re.sub(r"[^a-zA-Z0-9.+_]", ".", metadata["version"])
    revision = metadata["source_revision"][:12]
    version += f".r{metadata.get('commit_count', 0)}.g{revision}"
    archive = directory / "velora-source.tar.gz"
    with tarfile.open(archive, "w:gz") as output:
        output.add(snapshot, arcname="velora")
    checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
    recipe = (root / "packaging/arch/PKGBUILD.in").read_text()
    (directory / "PKGBUILD").write_text(recipe.replace("@VERSION@", version).replace("@SHA256@", checksum))
    return directory / "PKGBUILD"


def build_package(root, output, metadata, run, *, dry=False, install=False):
    if dry:
        print(f"  Would create a Velora source archive and PKGBUILD in a temporary build directory.")
        print(f"  Would save the built Arch package in {output}.")
        run(["makepkg", "--force", "--syncdeps", "--cleanbuild", "--clean"], dry=True)
        if install:
            print("  Would install the resulting Velora package with sudo pacman -U.")
        return None
    installed = set(run(["pacman", "-Qq"], capture=True).splitlines())
    if "base-devel" not in installed or not shutil.which("makepkg"):
        run(["sudo", "pacman", "-Syu", "--needed", "--", "base-devel", "git", "python"])
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="velora-package-") as temporary:
        directory = Path(temporary)
        prepare_package(root, directory, metadata, run)
        run(["makepkg", "--force", "--syncdeps", "--cleanbuild", "--clean"], cwd=directory,
            env=dict(os.environ, PKGDEST=str(output)))
        packages = [Path(line) for line in run(["makepkg", "--packagelist"], cwd=directory,
                    env=dict(os.environ, PKGDEST=str(output)), capture=True).splitlines()]
        if len(packages) != 1 or not packages[0].is_file():
            raise ValueError("makepkg did not produce the expected Velora package.")
        package = packages[0]
        if install:
            run(["sudo", "pacman", "-U", "--", package])
        print(f"Velora package: {package}")
        return package


def build_dependency(name, *, official, run, state, cache, dry=False, force=False):
    if not re.fullmatch(r"[a-zA-Z0-9@_+][a-zA-Z0-9@._+:-]*", name) or name.endswith("-bin"):
        raise ValueError(f"A source build requires a source package recipe, rather than a binary package: {name}")
    if dry:
        origin = "Arch's official packaging repository" if official else "AUR"
        print(f"  Would fetch {name} from {origin}, build with makepkg and install the result.")
        return
    cache.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=f"velora-build-{name}-") as temporary:
        workspace = Path(temporary)
        if official:
            run(["pkgctl", "repo", "clone", "--protocol", "https", name], cwd=workspace)
        else:
            run(["git", "clone", "--depth=1", f"https://aur.archlinux.org/{name}.git", workspace / name])
        recipe = workspace / name
        commit = run(["git", "rev-parse", "HEAD"], cwd=recipe, capture=True)
        record_path = state / f"{name}.json"
        record = json.loads(record_path.read_text()) if record_path.exists() else {}
        installed = run(["pacman", "-Qq"], capture=True).splitlines()
        if not force and not name.endswith(("-git", "-svn", "-hg")) and record.get("recipe") == commit and name in installed:
            version = run(["pacman", "-Q", name], capture=True)
            if record.get("installed") == version:
                print(f"  Source package {name} is already built from this recipe.")
                return
        run(["makepkg", "--syncdeps", "--install", "--cleanbuild", "--clean"], cwd=recipe,
            env=dict(os.environ, PKGDEST=str(cache)))
        installed_version = run(["pacman", "-Q", name], capture=True)
        state.mkdir(parents=True, exist_ok=True)
        record_path.write_text(json.dumps({"recipe": commit, "installed": installed_version}, indent=2) + "\n")
