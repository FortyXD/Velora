"""Write the recovery record before the installer moves an existing target."""
import errno
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile


def read_changes(journal):
    entries = []
    with Path(journal).open("rb") as source:
        for line in source:
            if not line.strip():
                continue
            try:
                entries.append(json.loads(line))
            except ValueError:
                # A short append cannot have moved its target. Keep the committed prefix.
                if line.endswith(b"\n"):
                    raise
                break
    return entries


def record_change(journal, target, backup=""):
    entry = {"target": str(target), "backup": str(backup)}
    if backup:
        original = os.lstat(target)
        entry["original"] = [original.st_dev, original.st_ino, stat.S_IFMT(original.st_mode)]
    record = (json.dumps(entry) + "\n").encode()
    with Path(journal).open("ab", buffering=0) as output:
        offset = output.tell()
        try:
            if output.write(record) != len(record):
                raise OSError(errno.ENOSPC, "No space left to record the configuration backup", str(journal))
            os.fsync(output.fileno())
        except OSError:
            os.ftruncate(output.fileno(), offset)
            raise


def move_to_backup(target, backup):
    target = Path(target)
    try:
        os.rename(target, backup)
        return
    except OSError as error:
        if error.errno != errno.EXDEV:
            raise
    # Keep the original intact until a complete copy, including hard links and
    # metadata, is available to recovery on the destination filesystem.
    temporary = str(backup) + ".partial"
    if subprocess.run(["cp", "-aT", "--", target, temporary]).returncode:
        raise OSError(f"Could not finish copying {target} to {temporary}")
    os.rename(temporary, backup)
    if subprocess.run(["sync", "-f", "--", Path(backup).parent]).returncode:
        raise OSError(f"Could not flush the configuration backup at {backup}")
    if subprocess.run(["rm", "-rf", "--", target]).returncode:
        raise OSError(f"Could not remove {target} after backing it up to {backup}")


def stage_application_files(journal, paths):
    """Let external settings tools edit private copies. Keep the original file or symlink for restore."""
    journal = Path(journal)
    for path in map(Path, paths):
        if not os.path.lexists(path):
            record_change(journal, path)
            continue
        if not path.is_file() and not (path.is_symlink() and not path.exists()):
            raise OSError(f"Cannot edit application settings at {path}: expected a regular file")
        backup = journal.parent / "integration" / f"app-{journal.stat().st_size}"
        backup.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=path.parent, prefix=".velora-app-") as temporary:
            staged = Path(temporary) / "settings"
            if path.is_file():
                shutil.copy2(path, staged)
            record_change(journal, path, backup)
            move_to_backup(path, backup)
            if staged.exists():
                staged.replace(path)


if __name__ == "__main__":
    try:
        if sys.argv[1] == "--stage-applications":
            stage_application_files(sys.argv[2], sys.argv[3:])
        elif sys.argv[1] == "--back-up":
            journal, target, backup = sys.argv[2:]
            if journal:
                record_change(journal, target, backup)
            move_to_backup(target, backup)
        else:
            record_change(*sys.argv[1:])
    except OSError as error:
        sys.exit(f"Could not record the configuration backup: {error}")
