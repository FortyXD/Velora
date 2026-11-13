"""Settings-owned setup jobs. No terminal, user data, or model inference is involved."""
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time

SOURCE = Path(__file__).resolve().parent
ROOT = SOURCE.parents[2]

STEPS = {"preparing": 1, "dependencies": 1, "building": 2, "service": 2,
         "runtime": 3, "export-tools": 3, "models": 4, "verifying": 5, "done": 5}


class Progress:
    def __init__(self, with_models):
        self.state = dict(running=True, pid=os.getpid(), identity=identity(os.getpid()),
                          stage="preparing", started_at=time.time(), steps_total=5 if with_models else 2)

    def __call__(self, name, **details):
        if (state_dir() / "cancel").exists():
            raise Cancelled()
        if name != self.state.get("stage") or "stage_started_at" not in self.state:
            self.state["stage_started_at"] = time.time()
        step = min(STEPS.get(name, 1), self.state["steps_total"])
        self.state.update(stage=name, step=step,
                          steps_done=self.state["steps_total"] if name == "done" else step - 1,
                          progress=details)
        save_state(self.state)


def location(variable, default):
    return Path(os.environ.get(variable) or Path.home() / default)


def state_dir():
    path = location("XDG_STATE_HOME", ".local/state") / "velora-lens"
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    return path


def data_dir():
    return location("XDG_DATA_HOME", ".local/share") / "velora-lens"


def binary():
    for path in (Path.home() / ".local/bin/velora-searchd", Path("/usr/bin/velora-searchd")):
        if path.is_file() and os.access(path, os.X_OK):
            return path
    return None


def identity(pid):
    try:
        return Path(f"/proc/{int(pid)}/stat").read_text().rsplit(")", 1)[1].split()[19]
    except (OSError, ValueError, TypeError, IndexError):
        return None


def read_state():
    directory = state_dir()
    try:
        value = json.loads((directory / "setup.json").read_text())
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def save_state(value):
    directory = state_dir()
    with tempfile.NamedTemporaryFile(mode="w", dir=directory, delete=False) as stream:
        json.dump(value, stream)
        staged = Path(stream.name)
    os.replace(staged, directory / "setup.json")


def status():
    value = read_state()
    token = identity(value.get("pid")) if value.get("running") else None
    active = bool(token and token == value.get("identity"))
    if value.get("running") and not active:
        value.update(stage="interrupted", running=False)
    value.update(running=active, installed=binary() is not None,
                 models=(data_dir() / "models/manifest.json").is_file() and (data_dir() / "venv/bin/python").is_file(),
                 cancelling=active and (state_dir() / "cancel").exists())
    # Old jobs can report stage counts and elapsed time without restarting their download.
    value.setdefault("steps_total", 5)
    value.setdefault("step", STEPS.get(value.get("stage"), 1))
    value.setdefault("steps_done", value["steps_total"] if value.get("stage") == "done" else value["step"] - 1)
    started = value.get("started_at")
    if started is None and active:
        try:
            started = time.time() - float(Path("/proc/uptime").read_text().split()[0]) + int(token) / os.sysconf("SC_CLK_TCK")
        except (OSError, ValueError):
            pass
    if started is not None:
        value["elapsed_seconds"] = max(0, int(value.get("finished_at", time.time()) - started))
    # Installation diagnostics contain tool output only, never filenames from the search index.
    if value.get("stage") == "failed":
        try:
            with (state_dir() / "setup.log").open("rb") as stream:
                stream.seek(0, 2)
                stream.seek(max(0, stream.tell() - 6000))
                value["detail"] = stream.read().decode("utf-8", "replace")
        except OSError:
            pass
    return value


class Cancelled(Exception):
    pass


def run_job(with_models):
    phase = Progress(with_models)
    state = phase.state

    def cancelled(_signal, _frame):
        raise Cancelled()

    signal.signal(signal.SIGTERM, cancelled)
    signal.signal(signal.SIGINT, cancelled)
    try:
        phase("dependencies")
        packages = ["python", "python-pip", "openssl", "bubblewrap", "poppler", "tesseract",
                    "tesseract-data-eng", "tesseract-data-rus", "ffmpeg", "mpv", "gnome-keyring"]
        if not binary():
            packages += [pkg for command, pkg in (("cargo", "rust"), ("cc", "gcc"), ("pkg-config", "pkgconf"), ("make", "make")) if not shutil.which(command)]
        checked = subprocess.run(["/usr/bin/pacman", "-T", *packages], capture_output=True, text=True)
        if checked.returncode not in (0, 127):
            raise RuntimeError("Cannot check system packages")
        missing = checked.stdout.split()
        if missing:
            # The desktop's Polkit agent owns the password prompt; Lens never sees credentials.
            subprocess.run(["/usr/bin/pkexec", "/usr/bin/pacman", "-S", "--needed", "--noconfirm", *missing], check=True)
        phase("service")
        target = Path.home() / ".local/bin/velora-searchd"
        if not binary():
            phase("building")
            cache = location("XDG_CACHE_HOME", ".cache") / "velora/cargo-target"
            subprocess.run(["cargo", "build", "--release", "--locked", "--manifest-path", ROOT / "tools/Cargo.toml",
                            "-p", "velora-searchd"], env={**os.environ, "CARGO_TARGET_DIR": str(cache)}, check=True)
            target.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(dir=target.parent, prefix=".velora-searchd-", delete=False) as stream:
                staged = Path(stream.name)
                try:
                    with (cache / "release/velora-searchd").open("rb") as source:
                        shutil.copyfileobj(source, stream)
                    stream.flush()
                    staged.chmod(0o755)
                    os.replace(staged, target)
                finally:
                    staged.unlink(missing_ok=True)
        phase("service")
        spec = importlib.util.spec_from_file_location("velora_setup", ROOT / "scripts/velora.py")
        installer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(installer)
        unit = location("XDG_CONFIG_HOME", ".config") / "systemd/user/velora-searchd.service"
        unit.parent.mkdir(parents=True, exist_ok=True)
        unit.write_text(installer.lens_service_unit(binary()))
        subprocess.run(["systemctl", "--user", "daemon-reload"], check=True)
        subprocess.run(["systemctl", "--user", "start", "velora-searchd.service"], check=True)
        if with_models:
            import install
            install.install(data_dir(), progress=phase)
            # Wake an already unlocked index; a locked one detects the bundle on next unlock.
            import socket
            try:
                with socket.socket(socket.AF_UNIX) as client:
                    client.settimeout(2)
                    client.connect(str(Path(os.environ["XDG_RUNTIME_DIR"]) / "velora-lens/search.sock"))
                    client.sendall(b'{"id":1,"method":"rescan","params":{}}\n')
                    client.recv(4096)
            except (OSError, KeyError):
                pass
        phase("done")
    except Cancelled:
        state.update(stage="cancelled")
    except Exception as error:
        print(f"Setup failed: {error}", flush=True)
        state.update(stage="failed")
    finally:
        state.update(running=False, finished_at=time.time())
        save_state(state)


def start(with_models):
    # Hold an inherited lock before spawning, so repeated clicks cannot run two installers.
    with (state_dir() / "setup.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return status()
        (state_dir() / "cancel").unlink(missing_ok=True)
        with (state_dir() / "setup.log").open("w") as log:
            child = subprocess.Popen([sys.executable, "-B", __file__, "run", "models" if with_models else "service"],
                                     stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                                     start_new_session=True, pass_fds=(lock.fileno(),))
        # The child owns the lock and state from this point, even if Settings is closed.
        return dict(running=True, stage="preparing", pid=child.pid)


def cancel():
    value = status()
    if value.get("running"):
        (state_dir() / "cancel").touch(mode=0o600)
        # Let pacman finish its transaction; all other work can be stopped immediately.
        if value.get("stage") != "dependencies":
            try:
                pid = int(value["pid"])
                if os.getpgid(pid) == pid:
                    os.killpg(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
    return value


if __name__ == "__main__":
    os.umask(0o077)
    action = sys.argv[1] if len(sys.argv) > 1 else "status"
    if action == "run":
        run_job(sys.argv[2] == "models")
    else:
        try:
            result = start(len(sys.argv) > 2 and sys.argv[2] == "models") if action == "start" else cancel() if action == "cancel" else status()
            print(json.dumps(result), flush=True)
        except Exception as error:
            print(json.dumps(dict(running=False, stage="failed", detail=str(error)[:2000])), flush=True)
            sys.exit(1)
