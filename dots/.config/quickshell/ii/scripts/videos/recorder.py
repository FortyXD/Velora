#!/usr/bin/env python3
"""Single-owner wlroots recording controller. No shell interpolation or global signals."""
import argparse
from collections import deque
import ctypes
import fcntl
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time

ACTIVE = {"selecting", "countdown", "starting", "recording", "stopping"}
STARTUP_TIMEOUT = 15
STOP_GRACE = 2
DEFAULTS = dict(mode="region", audio="system", systemSource="", microphoneSource="", fps=30,
                quality="balanced", format="mp4", delay=0)


def child_guard(parent_pid, death_signal):
    # Load libc before fork. Arm before exec, then close the death-before-prctl
    # race by checking the *original* parent, not a PID obtained in the child.
    libc = ctypes.CDLL(None, use_errno=True)

    def guard():
        if death_signal != signal.SIGKILL:
            signal.signal(death_signal, signal.SIG_DFL)
        if libc.prctl(1, death_signal, 0, 0, 0) != 0:  # PR_SET_PDEATHSIG
            raise OSError(ctypes.get_errno(), "Cannot arm recorder parent-death guard")
        if os.getppid() != parent_pid:
            os._exit(1)
    return guard


def child_gate(parent_pid, death_signal, descriptor, command):
    # This is a separate Python exec, not a blocking preexec_fn (Popen waits
    # for the latter's exec-error pipe). The gate inherits unignorable PDEATHSIG
    # KILL, and cannot run the target until its same-PID identity is published.
    try:
        go = os.read(descriptor, 1)
    finally:
        os.close(descriptor)
    if go != b"G":
        return 1
    child_guard(parent_pid, death_signal)()
    os.execvp(command[0], command)


def monitor_preflight(output=None):
    monitors = [m for m in json.loads(run(["hyprctl", "monitors", "-j"])) if not m.get("disabled")]
    if any("LOCK" in (m.get("solitaryBlockedBy") or []) for m in monitors):
        raise ValueError("Screen is locked; unlock before recording")
    selected = [m for m in monitors if m.get("name") == output] if output else monitors
    # Missing fields on older Hyprland/fakes are unknown, not DPMS-off.
    if selected and all(m.get("dpmsStatus") is False for m in selected):
        raise ValueError("Recording monitor is powered off (DPMS); wake it before recording")
    return monitors


def run(args):
    return subprocess.check_output(args, text=True, stderr=subprocess.PIPE, timeout=5).strip()


def videos_dir():
    try:
        path = Path(run(["xdg-user-dir", "VIDEOS"]))
        if path.is_absolute() and path != Path.home():
            return str(path)
    except (OSError, subprocess.SubprocessError):
        pass
    return str(Path.home() / "Videos")


def settings(path):
    if path.exists():
        try:
            document = json.loads(path.read_text())
            data = document.get("screenRecord", {})
            if data is None:
                data = {}
            if not isinstance(data, dict):
                raise ValueError("screenRecord must be an object")
        except (json.JSONDecodeError, AttributeError) as error:
            raise ValueError("Invalid recording configuration: " + str(error)) from error
    else:
        data = {}
    result = {key: data.get(key) if data.get(key) is not None else value
              for key, value in DEFAULTS.items()}
    folder_value = data.get("savePath")
    result["savePath"] = videos_dir() if folder_value in (None, "") else folder_value
    for key, choices in dict(mode=("screen", "region"), audio=("none", "system", "microphone", "both"),
                             quality=("high", "balanced", "small"), format=("mp4", "mkv"),
                             fps=(30, 60), delay=(0, 3, 5, 10)).items():
        if (result[key] not in choices or isinstance(result[key], bool)
                or (key in ("fps", "delay") and type(result[key]) is not int)):
            raise ValueError("Invalid recording setting: " + key)
    for key in ("savePath", "systemSource", "microphoneSource"):
        if not isinstance(result[key], str) or "\0" in result[key]:
            raise ValueError("Invalid recording setting: " + key)
    folder = Path(result["savePath"]).expanduser()
    if not folder.is_absolute():
        raise ValueError("Recording folder must be an absolute path")
    result["savePath"] = str(folder)
    return result


def sources():
    data = json.loads(run(["pactl", "--format=json", "list", "sources"]))
    return [dict(value=item["name"], displayName=item.get("description") or item["name"],
                 monitor=item.get("monitor_of_sink") not in (None, 4294967295, "4294967295")
                 or item["name"].endswith(".monitor")) for item in data]


def audio_modules():
    # PipeWire's pactl JSON module records omit IDs on some releases. The
    # documented short TSV form includes the ID needed for safe unload.
    modules = []
    current = None
    for line in run(["pactl", "list", "short", "modules"]).splitlines():
        # Native PipeWire modules contain multiline configuration arguments;
        # only an ID<TAB>name<TAB> prefix starts a new module record.
        header = re.match(r"^(\d+)\t([^\t]+)\t(.*)$", line)
        if header:
            current = dict(index=int(header[1]), name=header[2], argument=header[3].split("\t")[0])
            modules.append(current)
        elif line.strip():
            if current is None or re.search(r"(?:^|\t)module-(?:null-sink|loopback)(?:\t|$)", line):
                raise ValueError("Unexpected pactl module-list format; cannot safely clean audio mixer")
            current["argument"] += "\n" + line.rstrip("\t")
    return modules


def audio_source(options):
    if options["audio"] == "none":
        return None
    available = sources()
    monitor = options["audio"] == "system"
    selected = options["systemSource" if monitor else "microphoneSource"]
    if not selected:
        selected = (run(["pactl", "get-default-sink"]) + ".monitor" if monitor
                    else run(["pactl", "get-default-source"]))
    if not any(item["value"] == selected and item["monitor"] == monitor for item in available):
        raise ValueError("Selected audio device is unavailable or has the wrong type: " + selected)
    return selected


def identity(pid):
    try:
        fields = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
        return fields[19] if fields[0] != "Z" else None
    except (OSError, IndexError):
        return None


def read_state(directory):
    try:
        value = json.loads((directory / "state.json").read_text())
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def status(directory):
    state = read_state(directory)
    try:
        with (directory / "owner.lock").open("r") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                alive = False
            except BlockingIOError:
                alive = True
            try:
                owner = json.loads(lock.read())
            except ValueError:
                owner = {}
            if alive and (state.get("pid"), state.get("identity")) != (owner.get("pid"), owner.get("identity")):
                return {"state": "starting"}
    except OSError:
        alive = False
    if not alive or identity(state.get("pid")) != state.get("identity"):
        child_alive = state.get("childIdentity") and identity(state.get("childPid")) == state["childIdentity"]
        if child_alive:
            state["state"] = ("stopping" if state.get("error") else
                              "recording" if state.get("childKind") == "recorder" else "selecting")
            state["orphaned"] = True
        elif state.get("mixerSink"):
            state.update(state="stopping", orphaned=True)
        else:
            state["state"] = "error" if state.get("state") == "error" else "idle"
        if alive:
            state["state"] = "starting"  # owner is publishing its initial state
    return state or {"state": "idle"}


def stop(directory):
    state = status(directory)
    if state.get("state") not in ACTIVE or not state.get("pid"):
        return False
    if state.get("orphaned"):
        return False  # recovery must first acquire the owner lock
    pid = state["pid"]
    # Open a pidfd *before* checking start time: never signal a reused numeric PID.
    descriptor = os.pidfd_open(pid)
    try:
        if identity(pid) == state.get("identity"):
            signal.pidfd_send_signal(descriptor, signal.SIGTERM)
            return True
    finally:
        os.close(descriptor)


def notify(title, body, expire=5000):
    if shutil.which("notify-send"):
        try:
            subprocess.run(["notify-send", "-a", "Recorder", "-t", str(expire), title, body], timeout=3,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except (OSError, subprocess.SubprocessError):
            pass


class Recorder:
    def __init__(self, directory):
        self.directory = directory
        self.cancel = threading.Event()
        self.child = None
        self.state = dict(state="starting", pid=os.getpid(), identity=identity(os.getpid()),
                          startedAt=0, file="", error="")
        self.logs = deque(maxlen=100)
        self.initialized = threading.Event()
        self.modules = []
        self.mixer_sink = ""
        self.saved_file = ""

    def publish(self, phase, **changes):
        self.state.update(changes, state=phase)
        descriptor, temporary = tempfile.mkstemp(dir=self.directory, prefix=".state-")
        try:
            with os.fdopen(descriptor, "w") as stream:
                json.dump(self.state, stream)
            os.replace(temporary, self.directory / "state.json")
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)

    def wait(self, seconds):
        return self.cancel.wait(seconds)

    def signal_handler(self, *_):
        self.cancel.set()

    def launch_child(self, command, kind, phase, **kwargs):
        parent_pid = os.getpid()
        death_signal = signal.SIGINT if kind == "recorder" else signal.SIGTERM
        reader, writer = os.pipe()
        try:
            self.child = subprocess.Popen(
                [sys.executable, str(Path(__file__).resolve()), "--child-gate",
                 str(parent_pid), str(int(death_signal)), str(reader), *command],
                pass_fds=(reader,), preexec_fn=child_guard(parent_pid, signal.SIGKILL), **kwargs)
            os.close(reader)
            reader = None
            self.publish(phase, childPid=self.child.pid, childIdentity=identity(self.child.pid), childKind=kind)
            os.write(writer, b"G")
        finally:
            if reader is not None:
                os.close(reader)
            os.close(writer)  # EOF also aborts an unreleased gate on failure

    def select(self):
        self.publish("selecting")
        self.launch_child(["slurp"], "selector", "selecting", stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, text=True)
        while self.child.poll() is None:
            if self.wait(.05):
                self.terminate_child(self.child.pid, self.state.get("childIdentity"), "selector", owned=True)
                self.child.communicate(timeout=3)
                return None
        output, diagnostic = self.child.communicate()
        if self.child.returncode != 0 and diagnostic.strip():
            raise ValueError("Region selection failed: " + diagnostic.strip()[-2000:])
        return output.strip() if self.child.returncode == 0 else None

    def mixed_source(self, options):
        system = audio_source(dict(options, audio="system"))
        microphone = audio_source(dict(options, audio="microphone"))
        previous = run(["pactl", "get-default-sink"])
        sink = f"velora_recording_{os.getpid()}_{secrets.token_hex(6)}"
        self.mixer_sink = sink
        # Publish the unique ownership tag BEFORE creating modules, closing the
        # crash gap between pactl returning and persisting the resulting module ID.
        self.publish(self.state["state"], mixerSink=sink)
        self.modules.append(run(["pactl", "load-module", "module-null-sink", "sink_name=" + sink,
                                 "sink_properties=device.description=Velora-Recording device.class=filter"]))
        self.publish(self.state["state"], modules=self.modules)
        # Some PulseAudio policies auto-select new sinks; restore immediately, not at stop.
        if run(["pactl", "get-default-sink"]) == sink:
            run(["pactl", "set-default-sink", previous])
        for source in (system, microphone):
            self.modules.append(run(["pactl", "load-module", "module-loopback", "source=" + source,
                                     "sink=" + sink, "source_dont_move=true", "sink_dont_move=true",
                                     "latency_msec=20"]))
            self.publish(self.state["state"], modules=self.modules)
        return sink + ".monitor"

    def cleanup_audio(self):
        if not self.mixer_sink:
            return
        modules = audio_modules()
        pattern = r"(?:^|\s)(?:sink_name|sink)=" + re.escape(self.mixer_sink) + r"(?:\s|$)"
        owned = [item for item in modules if item.get("name") in ("module-null-sink", "module-loopback")
                 and re.search(pattern, item.get("argument", ""))]
        # Loopbacks first, sink last. Validate module identity, not a possibly
        # reused PulseAudio ID after an audio-server restart.
        owned.sort(key=lambda item: (item["name"] == "module-null-sink", -int(item["index"])))
        for item in owned:
            try:
                run(["pactl", "unload-module", str(item["index"])])
            except (OSError, subprocess.SubprocessError):
                pass  # try every owned module, then verify what actually remains
        remaining = audio_modules()
        if any(item.get("name") in ("module-null-sink", "module-loopback")
               and re.search(pattern, item.get("argument", "")) for item in remaining):
            raise ValueError("Audio mixer cleanup failed; press Stop again to retry")
        self.modules.clear()
        self.mixer_sink = ""
        self.publish(self.state["state"], modules=[], mixerSink="")

    def terminate_child(self, pid, token, kind, owned=False):
        """Bounded stop; only a live owner's proven uninitialized encoder is killable."""
        try:
            descriptor = os.pidfd_open(pid)
        except ProcessLookupError:
            return
        try:
            def alive():
                if owned:
                    return self.child.poll() is None  # reap our own zombies
                return token and identity(pid) == token

            def initialized():
                filename = self.state.get("file")
                has_output = filename and Path(filename).exists() and Path(filename).stat().st_size > 0
                return has_output or (self.initialized.is_set() if owned else
                                      self.state.get("encoderInitialized") or self.state.get("startedAt"))

            def send_and_wait(sig):
                if not alive():
                    return True
                signal.pidfd_send_signal(descriptor, sig)
                deadline = time.monotonic() + STOP_GRACE
                while alive() and time.monotonic() < deadline:
                    time.sleep(.025)
                return not alive()

            if send_and_wait(signal.SIGINT if kind == "recorder" else signal.SIGTERM):
                return
            if kind == "recorder" and initialized():
                raise ValueError("Recorder is still finalizing/not responding; file and ownership retained. Press Stop to retry")
            if send_and_wait(signal.SIGTERM):
                return
            # A missing persisted readiness flag does NOT prove an orphan was
            # uninitialized: buffered MKV may still have been zero bytes at crash.
            if kind == "recorder" and (not owned or initialized()):
                raise ValueError("Recorder is not responding; initialization is uncertain, file and ownership retained. Press Stop to retry")
            if not send_and_wait(signal.SIGKILL):
                raise ValueError("Recorder could not be stopped; ownership retained. Press Stop to retry")
        except ProcessLookupError:
            pass
        finally:
            os.close(descriptor)

    def recover(self, previous):
        self.state.update(previous, pid=os.getpid(), identity=identity(os.getpid()))
        self.mixer_sink = previous.get("mixerSink", "")
        self.modules = previous.get("modules", [])
        self.publish("stopping")
        pid, token = previous.get("childPid"), previous.get("childIdentity")
        if token and identity(pid) == token:
            self.terminate_child(pid, token, previous.get("childKind"))
        self.cleanup_audio()
        filename = previous.get("file")
        if filename and Path(filename).exists() and Path(filename).stat().st_size:
            if run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                    "stream=codec_type", "-of", "csv=p=0", filename]) != "video":
                raise ValueError("Recovered file has no valid video stream: " + filename)
            self.saved_file = filename

    def capture_logs(self, stream):
        # Read fixed-size chunks, not unbounded lines, and drain throughout recording.
        preview = b""
        while chunk := stream.read1(1024):
            self.logs.append(chunk)
            preview = (preview + chunk)[-16384:]
            # Container buffers (notably MKV) can keep the file at zero bytes for
            # seconds. FFmpeg's output/stream description proves muxer+encoder init.
            if b"Output #0," in preview and re.search(rb"Stream #0:\d+.*Video:", preview):
                self.initialized.set()

    def record(self, options, args):
        if not shutil.which("wf-recorder"):
            raise ValueError("wf-recorder is not installed")
        if not shutil.which("ffprobe"):
            raise ValueError("ffprobe is not installed (install ffmpeg)")
        region = args.region
        if region:
            options["mode"] = "region"
        elif args.fullscreen:
            options["mode"] = "screen"
        elif args.select_region:
            options["mode"] = "region"
        if args.mic:
            options["audio"] = "both"
        elif args.sound:
            options["audio"] = "system"
        elif args.silent:
            options["audio"] = "none"
        # Validate before selection, but create mixing modules only just before capture.
        if options["audio"] == "both":
            audio_source(dict(options, audio="system"))
            audio_source(dict(options, audio="microphone"))
            source = None
        else:
            source = audio_source(options)
        output = None
        monitors = monitor_preflight()
        if options["mode"] == "screen":
            output = next((m["name"] for m in monitors if m.get("focused") and not m.get("disabled")), None)
            if not output:
                raise ValueError("No focused monitor is available")
            monitor_preflight(output)
        elif not region:
            region = self.select()
            if not region:
                self.publish("idle")
                return
        if region and not re.fullmatch(r"-?\d+,-?\d+ [1-9]\d*x[1-9]\d*", region):
            raise ValueError("Invalid recording region")
        folder = Path(options["savePath"])
        folder.mkdir(parents=True, exist_ok=True)
        # Reserve a unique filename; -y only overwrites our own empty reservation.
        descriptor, filename = tempfile.mkstemp(prefix=time.strftime("recording_%Y-%m-%d_%H.%M.%S_"),
                                                suffix="." + options["format"], dir=folder)
        os.close(descriptor)
        self.state["file"] = filename
        stop_attempted = False
        try:
            delay = options["delay"]
            self.publish("countdown", remaining=delay)
            if delay:
                notify("Recording countdown", f"{delay} s — press the recording button again to cancel", expire=delay * 1000)
            for remaining in range(delay, 0, -1):
                self.publish("countdown", remaining=remaining)
                if self.wait(1):
                    return
            # Allow region selectors / overlays to disappear even without a countdown.
            if self.wait(.25):
                return
            monitor_preflight(output)
            if options["audio"] == "both":
                source = self.mixed_source(options)
            else:
                source = audio_source(options)
            if self.cancel.is_set():
                return
            command = ["wf-recorder", "-y", "--pixel-format", "yuv420p", "-c", "libx264",
                       "-p", "preset=veryfast", "-p", "crf=" + str(dict(high=18, balanced=23, small=28)[options["quality"]]),
                       "-r", str(options["fps"]), "-F", "pad=ceil(iw/2)*2:ceil(ih/2)*2", "-f", filename]
            command += ["-o", output] if output else ["--geometry", region]
            if source:
                command += ["--audio=" + source, "-C", "aac"]
            self.publish("starting", remaining=0)
            # Gate execution until ownership is published. After release, owner
            # death sends SIGINT so initialized encoders can finalize normally.
            self.launch_child(command, "recorder", "starting", stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT)
            reader = threading.Thread(target=self.capture_logs, args=(self.child.stdout,), daemon=True)
            reader.start()
            deadline = time.monotonic() + STARTUP_TIMEOUT
            while self.child.poll() is None and not self.cancel.is_set():
                if self.initialized.is_set():
                    self.publish("recording", startedAt=time.time() * 1000, encoderInitialized=True)
                    break
                if time.monotonic() > deadline:
                    raise ValueError(f"Recorder did not initialize within {STARTUP_TIMEOUT:g} seconds (screen may be locked or powered off)")
                self.wait(.05)
            while self.child.poll() is None and not self.cancel.is_set():
                self.wait(.1)
            requested = self.cancel.is_set()
            if self.child.poll() is None:
                self.publish("stopping")
                stop_attempted = True
                self.terminate_child(self.child.pid, self.state.get("childIdentity"), "recorder", owned=True)
            reader.join(timeout=2)
            if not requested or self.child.returncode not in (0, -signal.SIGINT):
                raise ValueError("Recorder exited unexpectedly (exit " + str(self.child.returncode) + ")")
            if not Path(filename).stat().st_size:
                return
            if run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                    "stream=codec_type", "-of", "csv=p=0", filename]) != "video":
                raise ValueError("Recorded file has no valid video stream: " + filename)
            self.saved_file = filename
        finally:
            if self.child and self.child.poll() is None and not stop_attempted:
                self.publish("stopping")
                self.terminate_child(self.child.pid, self.state.get("childIdentity"), "recorder", owned=True)
            if (not self.child or self.child.poll() is not None) and Path(filename).exists() and Path(filename).stat().st_size == 0:
                Path(filename).unlink()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", nargs="?", choices=("toggle", "stop", "status", "sources"), default="toggle")
    parser.add_argument("--config", type=Path, default=Path(os.environ.get("VELORA_RECORDER_CONFIG", str(Path.home() / ".config/illogical-impulse/config.json"))))
    parser.add_argument("--runtime-dir", type=Path, default=Path(os.environ.get("VELORA_RECORDER_RUNTIME", os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}") + "/velora-recorder")))
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--region")
    mode.add_argument("--fullscreen", action="store_true")
    mode.add_argument("--select-region", action="store_true")
    parser.add_argument("--sound", action="store_true")
    parser.add_argument("--silent", action="store_true")
    parser.add_argument("--mic", action="store_true", help="Record system sound and microphone together")
    args = parser.parse_args(argv)
    if args.silent and (args.sound or args.mic):
        parser.error("--silent cannot be combined with --sound or --mic")
    directory = args.runtime_dir
    if args.action == "sources":
        try:
            print(json.dumps(sources()))
            return 0
        except (OSError, ValueError, subprocess.SubprocessError):
            print("[]")
            return 1
    if args.action == "status":
        print(json.dumps(status(directory)))
        return 0
    if args.action == "stop" and not status(directory).get("orphaned"):
        try:
            stop(directory)
        except ProcessLookupError:
            pass
        return 0
    os.umask(0o077)
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (directory / "owner.lock").open("a+") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            # The owner may still be publishing its first state after acquiring the lock.
            for _ in range(30):
                try:
                    if stop(directory):
                        break
                except ProcessLookupError:
                    pass
                time.sleep(.01)
            return 0
        previous = read_state(directory)
        lock.seek(0)
        lock.truncate()
        json.dump(dict(pid=os.getpid(), identity=identity(os.getpid())), lock)
        lock.flush()
        recorder = Recorder(directory)
        for sig in (signal.SIGTERM, signal.SIGINT):
            signal.signal(sig, recorder.signal_handler)
        try:
            child_alive = previous.get("childIdentity") and identity(previous.get("childPid")) == previous["childIdentity"]
            if child_alive or previous.get("mixerSink"):
                recorder.recover(previous)
            elif args.action != "stop":
                recorder.publish("starting")
                recorder.record(settings(args.config), args)
            recorder.publish("stopping")
            recorder.cleanup_audio()
            recorder.publish("idle", childPid=None, childIdentity=None, error="", file=recorder.saved_file)
            if recorder.saved_file:
                notify("Recording saved", recorder.saved_file)
            return 0
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            detail = b"".join(recorder.logs).decode(errors="replace")[-3000:]
            message = (str(error) + ("\n" + detail if detail else ""))[-4000:]
            if recorder.saved_file:
                message += "\nVideo file retained: " + recorder.saved_file
            try:
                # Keep mixer ownership while a finalizing/unresponsive child is
                # retained for the next Stop; never announce a successful save.
                token = recorder.state.get("childIdentity")
                if not token or identity(recorder.state.get("childPid")) != token:
                    recorder.cleanup_audio()
            except (OSError, ValueError, subprocess.SubprocessError) as cleanup_error:
                message += "\nAudio cleanup failed (press Stop again to retry): " + str(cleanup_error)
            recorder.publish("error", error=message)
            (directory / "error.log").write_text(message + "\n")
            notify("Recording failed", message[:500])
            print(message, file=sys.stderr)
            return 1


if __name__ == "__main__":
    if len(sys.argv) > 5 and sys.argv[1] == "--child-gate":
        sys.exit(child_gate(int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), sys.argv[5:]))
    sys.exit(main())
