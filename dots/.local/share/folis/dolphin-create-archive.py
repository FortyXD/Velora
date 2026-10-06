#!/usr/bin/env python3
"""Create a ZIP or tar.gz beside files selected in Dolphin."""

import os
import stat
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from pathlib import Path


def notify(title, message):
    try:
        subprocess.run(["notify-send", title, message], check=False, timeout=3)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass


def add_to_zip(archive, path, name):
    if path.is_symlink():
        info = zipfile.ZipInfo(name)
        info.create_system = 3
        info.external_attr = (stat.S_IFLNK | 0o777) << 16
        archive.writestr(info, os.readlink(path))
    elif path.is_dir():
        archive.write(path, name + "/")
        for child in sorted(path.iterdir()):
            add_to_zip(archive, child, name + "/" + child.name)
    else:
        archive.write(path, name)


def create_archive(format_name, names):
    if format_name not in ("zip", "tar.gz") or not names:
        raise ValueError("Select files or folders to archive")
    paths = [Path(name).absolute() for name in names]
    if any(not path.exists() and not path.is_symlink() for path in paths):
        raise FileNotFoundError("A selected file no longer exists")
    parent = paths[0].parent
    if any(path.parent != parent for path in paths):
        raise ValueError("Select files from the same folder")

    basename = paths[0].name if len(paths) == 1 and paths[0].is_dir() else paths[0].stem if len(paths) == 1 else "Archive"
    if not basename:
        basename = "Archive"
    descriptor, temporary = tempfile.mkstemp(prefix=".folis-archive-", suffix="." + format_name, dir=parent)
    os.close(descriptor)
    try:
        if format_name == "zip":
            with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED, allowZip64=True) as archive:
                for path in paths:
                    add_to_zip(archive, path, path.name)
        else:
            with tarfile.open(temporary, "w:gz") as archive:
                for path in paths:
                    archive.add(path, arcname=path.name)
        os.chmod(temporary, 0o644)
        for number in range(1, 10000):
            suffix = "" if number == 1 else f" ({number})"
            output = parent / f"{basename}{suffix}.{format_name}"
            try:
                os.link(temporary, output)
                return output
            except FileExistsError:
                continue
        raise FileExistsError("Could not choose a free archive name")
    finally:
        os.unlink(temporary)


if __name__ == "__main__":
    try:
        created = create_archive(sys.argv[1], sys.argv[2:])
    except (IndexError, OSError, ValueError, tarfile.TarError, zipfile.BadZipFile) as error:
        notify("Archive creation failed", str(error))
        print(error, file=sys.stderr)
        sys.exit(1)
    notify("Archive created", created.name)
    print(created)
