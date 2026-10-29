"""Recording lifecycle tests with executable fakes; never capture desktop or audio."""
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import signal
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

PROJECT = Path(__file__).resolve().parents[1]
BACKEND = PROJECT / "dots/.config/quickshell/ii/scripts/videos/recorder.py"
SPEC = importlib.util.spec_from_file_location("velora_recorder", BACKEND)
recorder = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(recorder)

FAKE = r'''#!/usr/bin/env python3
import json, os, pathlib, signal, sys, time
name=pathlib.Path(sys.argv[0]).name
args=sys.argv[1:]
with open(os.environ['FAKE_CALLS'],'a') as f: f.write(json.dumps([name]+args)+'\n')
if name=='xdg-user-dir': print(os.environ['FAKE_VIDEOS'])
elif name=='pactl':
    store=pathlib.Path(os.environ['FAKE_CALLS']+'.modules')
    modules=json.loads(store.read_text()) if store.exists() else []
    if args==['--format=json','list','modules']:
        print(json.dumps([{k:v for k,v in item.items() if k!='index'} for item in modules]))
    elif args==['list','short','modules']:
        if os.environ.get('FAKE_MODULE_SCHEMA_ERROR'): print('invalid module record')
        else:
            print('1'+chr(9)+'libpipewire-module-rt'+chr(9)+'{')
            print('    nice.level = -11')
            print('}'+chr(9))
            print('2'+chr(9)+'libpipewire-module-metadata'+chr(9)+chr(9))
            for item in modules: print(str(item['index'])+'\t'+item['name']+'\t'+item['argument']+'\t0')
    elif args[:2]==['--format=json','list']:
        print(json.dumps([{'name':'output.monitor','description':'Speakers','monitor_of_sink':1},
                          {'name':'other.monitor','description':'HDMI','monitor_of_sink':2},
                          {'name':'input','description':'Microphone','monitor_of_sink':4294967295}]))
    elif args==['get-default-sink']: print('output')
    elif args==['get-default-source']: print('input')
    elif args[0]=='load-module':
        if os.environ.get('FAKE_MIX_FAIL') and args[1]=='module-loopback': sys.exit(1)
        index=max([item['index'] for item in modules]+[536870911])+1
        modules.append(dict(index=index,name=args[1],argument=' '.join(args[2:])))
        store.write_text(json.dumps(modules))
        print(index)
    elif args[0]=='unload-module':
        if os.environ.get('FAKE_UNLOAD_FAIL') and pathlib.Path(os.environ['FAKE_UNLOAD_FAIL']).exists(): sys.exit(1)
        store.write_text(json.dumps([item for item in modules if str(item['index'])!=args[1]]))
elif name=='hyprctl': print(os.environ.get('FAKE_MONITORS','[{"name":"screen","focused":true}]'))
elif name=='ffprobe':
    if os.environ.get('FAKE_PROBE_FAIL'): sys.exit(1)
    print('video')
elif name=='slurp':
    if os.environ.get('FAKE_CHILD_READY'): pathlib.Path(os.environ['FAKE_CHILD_READY']).touch()
    if os.environ.get('FAKE_SELECT_WAIT'): time.sleep(60)
    if os.environ.get('FAKE_SELECT_ERROR'):
        print('Wayland connection failed',file=sys.stderr); sys.exit(1)
    if os.environ.get('FAKE_SELECT_CANCEL'): sys.exit(1)
    print('-200,10 65x63')
elif name=='wf-recorder':
    if os.environ.get('FAKE_START_FAIL'):
        print('encoder unavailable', flush=True); sys.exit(1)
    path=pathlib.Path(args[args.index('-f')+1])
    done=False
    def stop(*_):
        global done
        done=True
    signal.signal(signal.SIGINT,signal.SIG_IGN if os.environ.get('FAKE_STUBBORN') else stop)
    signal.signal(signal.SIGTERM,signal.SIG_IGN if os.environ.get('FAKE_STUBBORN') else stop)
    if not os.environ.get('FAKE_NO_READY'):
        print('Output #0, matroska, to file:\n  Stream #0:0: Video: h264, yuv420p',flush=True)
        if not os.environ.get('FAKE_BUFFERED'): path.write_bytes(b'header')
    if os.environ.get('FAKE_CHILD_READY'): pathlib.Path(os.environ['FAKE_CHILD_READY']).touch()
    while not done: time.sleep(.02)
    time.sleep(.25)
    path.write_bytes(b'header-finalized')
'''


class RecorderTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="velora-recorder-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for name in ("wf-recorder", "pactl", "hyprctl", "notify-send", "slurp", "ffprobe", "xdg-user-dir"):
            path = self.bin / name
            path.write_text(FAKE)
            path.chmod(0o755)
        self.config = self.root / "config.json"
        self.runtime = self.root / "runtime"
        self.calls = self.root / "calls.jsonl"
        self.options = dict(savePath=str(self.root / "Videos with spaces"), audio="none", mode="screen")
        self.write_config()
        self.env = {**os.environ, "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
                    "FAKE_CALLS": str(self.calls), "FAKE_VIDEOS": str(self.root / "XDG Videos"),
                    "VELORA_RECORDER_CONFIG": str(self.config), "VELORA_RECORDER_RUNTIME": str(self.runtime)}
        self.children = []
        self.addCleanup(self.cleanup_children)

    def cleanup_children(self):
        for child in self.children:
            if child.poll() is None:
                child.terminate()
                try: child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    child.kill(); child.wait()

    def write_config(self):
        self.config.write_text(json.dumps({"screenRecord": self.options}))

    def command(self, *args):
        return [sys.executable, str(BACKEND), *args]

    def call(self, *args, env=None):
        return subprocess.run(self.command(*args), env=env or self.env, capture_output=True, text=True, timeout=8)

    def start(self, *args, env=None):
        process = subprocess.Popen(self.command(*args), env=env or self.env,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.children.append(process)
        return process

    def wait_state(self, expected):
        deadline = time.monotonic() + 6
        while time.monotonic() < deadline:
            state = recorder.status(self.runtime)
            if state.get("state") == expected:
                return state
            time.sleep(.025)
        self.fail(f"Expected {expected}: {recorder.status(self.runtime)}; calls {self.get_calls()}")

    def get_calls(self, name=None):
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()] if self.calls.exists() else []
        return [call for call in calls if name is None or call[0] == name]

    def stop_capture(self, process):
        self.assertEqual(self.call("stop").returncode, 0)
        self.assertEqual(process.wait(timeout=6), 0)
        return self.wait_state("idle")

    def test_defaults_null_malformed_and_xdg_fallback(self):
        self.config.write_text('{"screenRecord":{"savePath":null,"fps":null}}')
        with patch.object(recorder, "run", return_value=str(Path.home())):
            options = recorder.settings(self.config)
        self.assertEqual(options["savePath"], str(Path.home() / "Videos"))
        self.assertEqual(options["fps"], 30)
        self.assertEqual(options["mode"], "region")
        self.assertEqual(options["audio"], "system")
        self.config.write_text('{bad')
        result = self.call()
        self.assertEqual(result.returncode, 1)
        self.assertIn("Invalid recording configuration", recorder.status(self.runtime)["error"])
        self.assertFalse(self.get_calls("wf-recorder"))
        self.options["delay"] = 3.0
        self.write_config()
        self.assertEqual(self.call().returncode, 1)
        self.assertIn("Invalid recording setting: delay", recorder.status(self.runtime)["error"])
        self.options.pop("delay")
        for value in ("relative", 17, ["a"]):
            self.options["savePath"] = value
            self.write_config()
            with self.subTest(value=value), self.assertRaises(ValueError):
                recorder.settings(self.config)

    def test_exact_audio_source_defaults_and_missing_selected(self):
        self.options.update(audio="system")
        self.write_config()
        process = self.start()
        state = self.wait_state("recording")
        self.assertGreater(state["startedAt"], 0)
        args = self.get_calls("wf-recorder")[0]
        self.assertIn("--audio=output.monitor", args)
        self.assertNotIn("--audio=other.monitor", args)
        self.stop_capture(process)
        self.options["systemSource"] = "missing.monitor"
        self.write_config()
        self.assertEqual(self.call().returncode, 1)
        self.assertIn("missing.monitor", recorder.status(self.runtime)["error"])
        self.assertEqual(len(self.get_calls("wf-recorder")), 1)

    def test_mapping_region_spaces_odd_dimensions_and_finalization(self):
        self.options.update(fps=60, quality="high", format="mkv")
        self.write_config()
        process = self.start("--region", "-200,10 65x63")
        state = self.wait_state("recording")
        args = self.get_calls("wf-recorder")[0]
        for value in ("60", "crf=18", "libx264", "yuv420p", "pad=ceil(iw/2)*2:ceil(ih/2)*2", "-200,10 65x63"):
            self.assertIn(value, args)
        self.assertNotIn("-t", args)
        self.assertTrue(state["file"].endswith(".mkv"))
        started = time.monotonic()
        final = self.stop_capture(process)
        self.assertGreater(time.monotonic() - started, .2)
        self.assertEqual(Path(final["file"]).read_bytes(), b"header-finalized")
        self.assertIn("Videos with spaces", final["file"])
        self.assertEqual((self.runtime / "state.json").stat().st_mode & 0o777, 0o600)

    def test_cancel_selection_and_countdown_no_recorder(self):
        self.options["mode"] = "region"
        self.write_config()
        result = self.call(env={**self.env, "FAKE_SELECT_CANCEL": "1"})
        self.assertEqual(result.returncode, 0)
        self.assertEqual(recorder.status(self.runtime)["state"], "idle")
        process = self.start(env={**self.env, "FAKE_SELECT_WAIT": "1"})
        self.wait_state("selecting")
        self.stop_capture(process)
        self.options.update(mode="screen", delay=3)
        self.write_config()
        process = self.start()
        self.wait_state("countdown")
        self.stop_capture(process)
        self.assertFalse(self.get_calls("wf-recorder"))
        self.assertEqual(list(Path(self.options["savePath"]).iterdir()), [])

    def test_start_failure_recovery_and_no_false_saved(self):
        process = self.start(env={**self.env, "FAKE_START_FAIL": "1"})
        self.assertEqual(process.wait(timeout=6), 1)
        state = self.wait_state("error")
        self.assertIn("encoder unavailable", state["error"])
        self.assertEqual(state["startedAt"], 0)
        self.assertFalse(any("Recording saved" in call for call in self.get_calls("notify-send")))
        process = self.start()
        self.wait_state("recording")
        self.stop_capture(process)

    def test_explicit_region_overrides_screen_default_and_reused_module_is_safe(self):
        process = self.start("--select-region")
        self.wait_state("recording")
        self.assertEqual(len(self.get_calls("slurp")), 1)
        args = self.get_calls("wf-recorder")[0]
        self.assertIn("--geometry", args)
        self.assertNotIn("-o", args)
        self.stop_capture(process)
        owner = recorder.Recorder(self.runtime)
        owner.mixer_sink = "velora_unique_sink"
        unrelated = "12\tmodule-loopback\tsink=someone_else\t0"
        with patch.object(recorder, "run", return_value=unrelated) as command:
            owner.cleanup_audio()
        self.assertFalse(any("unload-module" in call.args[0] for call in command.call_args_list))

    def test_buffered_container_readiness_uses_encoder_output(self):
        self.options.update(format="mkv", fps=60)
        self.write_config()
        process = self.start(env={**self.env, "FAKE_BUFFERED": "1"})
        state = self.wait_state("recording")
        self.assertEqual(Path(state["file"]).stat().st_size, 0)
        self.assertGreater(state["startedAt"], 0)
        self.stop_capture(process)

    def test_not_ready_is_starting_and_can_be_cancelled(self):
        process = self.start(env={**self.env, "FAKE_NO_READY": "1"})
        deadline = time.monotonic() + 5
        while not self.get_calls("wf-recorder") and time.monotonic() < deadline: time.sleep(.02)
        self.assertEqual(recorder.status(self.runtime)["state"], "starting")
        self.assertEqual(recorder.status(self.runtime)["startedAt"], 0)
        self.stop_capture(process)

    def test_toggle_does_not_stop_unrelated_process_and_restores_after_reload(self):
        external = subprocess.Popen([sys.executable, "-c", "import time;time.sleep(60)"])
        self.children.append(external)
        process = self.start()
        first = self.wait_state("recording")
        polled = json.loads(self.call("status").stdout)
        self.assertEqual(first["startedAt"], polled["startedAt"])
        self.assertEqual(self.call().returncode, 0)  # second click toggles only our owner
        self.assertEqual(process.wait(timeout=6), 0)
        self.assertIsNone(external.poll())
        self.assertEqual(len(self.get_calls("wf-recorder")), 1)

    def test_concurrent_toggles_and_stale_owner_identity(self):
        self.runtime.mkdir()
        old = dict(state="recording", pid=os.getpid(), identity="not-current")
        (self.runtime / "state.json").write_text(json.dumps(old))
        self.assertEqual(recorder.status(self.runtime)["state"], "idle")
        first = self.start()
        second = self.start()
        first.wait(timeout=6)
        second.wait(timeout=6)
        self.assertLessEqual(len(self.get_calls("wf-recorder")), 1)
        self.assertEqual(recorder.status(self.runtime)["state"], "idle")
        with (self.runtime / "owner.lock").open("w+") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            lock.write(json.dumps(dict(pid=os.getpid(), identity="different"))); lock.flush()
            (self.runtime / "state.json").write_text(json.dumps(dict(old, identity=recorder.identity(os.getpid()))))
            with patch.object(os, "pidfd_open") as opened:
                self.assertFalse(recorder.stop(self.runtime))
                opened.assert_not_called()

    def test_both_legacy_flags_mixing_and_reverse_cleanup(self):
        process = self.start("--sound", "--mic")
        self.wait_state("recording")
        calls = self.get_calls("pactl")
        loaded = [call for call in calls if call[1] == "load-module"]
        self.assertEqual(len(loaded), 3)
        self.assertTrue(any("source=output.monitor" in call for call in loaded))
        self.assertTrue(any("source=input" in call for call in loaded))
        self.assertFalse(any(call[1] == "unload-module" for call in calls))
        self.stop_capture(process)
        unloaded = [call[2] for call in self.get_calls("pactl") if call[1] == "unload-module"]
        self.assertEqual(len(unloaded), 3)
        self.assertEqual(unloaded, sorted(unloaded, reverse=True))

    def test_mix_failure_cleanup_and_microphone_only(self):
        self.options.update(audio="both")
        self.write_config()
        result = self.call(env={**self.env, "FAKE_MIX_FAIL": "1"})
        self.assertEqual(result.returncode, 1)
        self.assertEqual(len([c for c in self.get_calls("pactl") if c[1] == "unload-module"]), 1)
        self.assertFalse(self.get_calls("wf-recorder"))
        self.options.update(audio="microphone", microphoneSource="input")
        self.write_config()
        process = self.start()
        self.wait_state("recording")
        self.assertIn("--audio=input", self.get_calls("wf-recorder")[0])
        self.stop_capture(process)

    def test_orphaned_child_recovery_prevents_second_capture(self):
        self.options["audio"] = "both"
        self.write_config()
        process = self.start()
        state = self.wait_state("recording")
        child_pid = state["childPid"]
        process.kill()
        process.wait(timeout=3)
        orphan = recorder.status(self.runtime)
        # PDEATHSIG may already have finalized the encoder. Mixer ownership
        # still makes the next toggle recovery-only, even if the child exited.
        self.assertTrue(orphan["orphaned"])
        self.assertIn(orphan["state"], ("recording", "stopping"))
        # A subsequent toggle adopts stop/finalization/cleanup, never starts another.
        self.assertEqual(self.call().returncode, 0)
        self.assertEqual(recorder.status(self.runtime)["state"], "idle")
        self.assertIsNone(recorder.identity(child_pid))
        self.assertEqual(len(self.get_calls("wf-recorder")), 1)
        self.assertEqual(json.loads(Path(str(self.calls) + ".modules").read_text()), [])
        self.assertEqual(Path(state["file"]).read_bytes(), b"header-finalized")

    def driver(self, setup, env=None):
        code = ("import importlib.util,os,pathlib,time\n"
                f"spec=importlib.util.spec_from_file_location('backend',{str(BACKEND)!r})\n"
                "r=importlib.util.module_from_spec(spec);spec.loader.exec_module(r)\n" + setup +
                "\nraise SystemExit(r.main())\n")
        process = subprocess.Popen([sys.executable, "-c", code], env=env or self.env,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.children.append(process)
        return process

    def wait_file(self, path):
        deadline = time.monotonic() + 5
        while not path.exists() and time.monotonic() < deadline:
            time.sleep(.01)
        self.assertTrue(path.exists(), str(path))
        return path.read_text()

    def wait_dead(self, pid):
        deadline = time.monotonic() + 5
        while recorder.identity(pid) and time.monotonic() < deadline:
            time.sleep(.025)
        self.assertIsNone(recorder.identity(pid))

    def test_parent_death_before_child_publication_leaves_no_hidden_child(self):
        for kind in ("selector", "recorder"):
            with self.subTest(kind=kind):
                self.runtime = self.root / ("runtime-" + kind)
                boundary = self.root / ("boundary-" + kind)
                self.options["mode"] = "region" if kind == "selector" else "screen"
                self.write_config()
                ready = self.root / ("ready-" + kind)
                env = {**self.env, "VELORA_RECORDER_RUNTIME": str(self.runtime), "FAKE_SELECT_WAIT": "1",
                       "FAKE_CHILD_READY": str(ready)}
                name = "slurp" if kind == "selector" else "wf-recorder"
                calls_before = len(self.get_calls(name))
                process = self.driver(
                    "original=r.Recorder.publish\n"
                    "def publish(self, phase, **changes):\n"
                    "    if changes.get('childKind') == " + repr(kind) + ":\n"
                    "        pathlib.Path(" + repr(str(boundary)) + ").write_text(str(changes['childPid']))\n"
                    "        time.sleep(60)\n"
                    "    return original(self,phase,**changes)\n"
                    "r.Recorder.publish=publish\n", {**env, "FAKE_STUBBORN": "1", "FAKE_NO_READY": "1"})
                pid = int(self.wait_file(boundary))
                # The same-PID gate is alive, but even an INT/TERM-ignoring
                # target must not execute before publication/GO.
                self.assertIsNotNone(recorder.identity(pid))
                time.sleep(.1)
                self.assertFalse(ready.exists())
                self.assertEqual(len(self.get_calls(name)), calls_before)
                process.kill(); process.wait(timeout=3)
                self.wait_dead(pid)
                self.assertFalse(ready.exists())
                self.assertEqual(len(self.get_calls(name)), calls_before)
                self.assertNotIn(recorder.status(self.runtime).get("state"), recorder.ACTIVE)
                # Next launch can only have its own child, never a hidden original.
                self.options["mode"] = "screen"
                self.write_config()
                next_process = self.start(env=env)
                state = self.wait_state("recording")
                self.assertNotEqual(state["childPid"], pid)
                self.assertIsNone(recorder.identity(pid))
                self.assertEqual(self.call("stop", env=env).returncode, 0)
                self.assertEqual(next_process.wait(timeout=6), 0)

    def test_gate_release_keeps_published_identity_across_target_exec(self):
        boundary = self.root / "published-gate"
        release = self.root / "release-gate"
        process = self.driver(
            "original=r.Recorder.publish\n"
            "def publish(self, phase, **changes):\n"
            "    result=original(self,phase,**changes)\n"
            "    if changes.get('childKind') == 'recorder':\n"
            "        pathlib.Path(" + repr(str(boundary)) + ").write_text(str(changes['childPid']))\n"
            "        while not pathlib.Path(" + repr(str(release)) + ").exists(): time.sleep(.01)\n"
            "    return result\n"
            "r.Recorder.publish=publish\n")
        pid = int(self.wait_file(boundary))
        published = recorder.read_state(self.runtime)
        self.assertEqual(published["childPid"], pid)
        token = recorder.identity(pid)
        self.assertEqual(published["childIdentity"], token)
        self.assertFalse(self.get_calls("wf-recorder"))
        release.touch()
        state = self.wait_state("recording")
        self.assertEqual(state["childPid"], pid)
        self.assertEqual(state["childIdentity"], token)
        self.assertEqual(recorder.identity(pid), token)
        self.stop_capture(process)

    def test_gate_eof_aborts_target_when_publication_fails(self):
        self.runtime.mkdir()
        owner = recorder.Recorder(self.runtime)
        with patch.dict(os.environ, self.env), patch.object(owner, "publish", side_effect=ValueError("publish failed")):
            with self.assertRaisesRegex(ValueError, "publish failed"):
                owner.launch_child([str(self.bin / "wf-recorder"), "-f", str(self.root / "unused.mp4")],
                                   "recorder", "starting", stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.children.append(owner.child)
        # Parent remains alive: EOF, not the parent's exit, must abort the gate.
        self.assertEqual(owner.child.wait(timeout=3), 1)
        self.assertFalse(self.get_calls("wf-recorder"))

    def test_parent_death_before_prctl_is_caught_by_parent_recheck(self):
        marker = self.root / "pre-prctl"
        release = self.root / "release-prctl"
        process = self.driver(
            "original=r.child_guard\n"
            "def guarded(parent, sig):\n"
            "    guard=original(parent,sig)\n"
            "    def delayed():\n"
            "        pathlib.Path(" + repr(str(marker)) + ").write_text(str(os.getpid()))\n"
            "        while not pathlib.Path(" + repr(str(release)) + ").exists(): time.sleep(.01)\n"
            "        guard()\n"
            "    return delayed\n"
            "r.child_guard=guarded\n")
        pid = int(self.wait_file(marker))
        process.kill(); process.wait(timeout=3)
        release.touch()
        self.wait_dead(pid)
        self.assertFalse(self.get_calls("wf-recorder"))

    def test_locked_and_dpms_off_preflight_never_starts_encoder(self):
        for mode in ("screen", "region"):
            self.options["mode"] = mode
            self.write_config()
            for fields, message in (({"solitaryBlockedBy": ["LOCK"]}, "locked"),
                                    ({"dpmsStatus": False}, "powered off")):
                with self.subTest(mode=mode, fields=fields):
                    monitors = [dict(name="screen", focused=True, **fields)]
                    result = self.call(env={**self.env, "FAKE_MONITORS": json.dumps(monitors)})
                    self.assertEqual(result.returncode, 1)
                    self.assertIn(message, recorder.status(self.runtime)["error"])
        self.assertFalse(self.get_calls("wf-recorder"))
        self.assertFalse(self.get_calls("slurp"))

    def test_lock_after_countdown_is_rechecked_before_encoder_start(self):
        process = self.driver(
            "original=r.monitor_preflight\nchecks=0\n"
            "def preflight(output=None):\n"
            "    global checks\n"
            "    checks+=1\n"
            "    if checks==3: os.environ['FAKE_MONITORS']='[{\"name\":\"screen\",\"focused\":true,\"solitaryBlockedBy\":[\"LOCK\"]}]'\n"
            "    return original(output)\n"
            "r.monitor_preflight=preflight\n")
        self.assertEqual(process.wait(timeout=5), 1)
        self.assertIn("locked", recorder.status(self.runtime)["error"])
        self.assertFalse(self.get_calls("wf-recorder"))
        self.assertEqual(list(Path(self.options["savePath"]).iterdir()), [])

    def test_stubborn_uninitialized_encoder_times_out_and_is_killed(self):
        process = self.driver("r.STARTUP_TIMEOUT=.2\nr.STOP_GRACE=.15\n",
                              {**self.env, "FAKE_NO_READY": "1", "FAKE_STUBBORN": "1"})
        self.assertEqual(process.wait(timeout=5), 1)
        state = self.wait_state("error")
        self.assertIn("did not initialize", state["error"])
        self.assertIsNone(recorder.identity(state["childPid"]))
        self.assertFalse(Path(state["file"]).exists())
        self.assertFalse(any("Recording saved" in call for call in self.get_calls("notify-send")))

    def test_manual_orphan_adoption_and_uncertain_empty_orphan_is_bounded(self):
        self.runtime.mkdir()
        filename = self.root / "orphan.mkv"
        for stubborn in (False, True):
            with self.subTest(stubborn=stubborn):
                filename.write_bytes(b"")
                env = {**self.env, "FAKE_NO_READY": "1"}
                if stubborn:
                    env["FAKE_STUBBORN"] = "1"
                child = subprocess.Popen([str(self.bin / "wf-recorder"), "-f", str(filename)], env=env,
                                         stdout=subprocess.DEVNULL)
                self.children.append(child)
                # Ensure the fake has installed its handlers.
                deadline = time.monotonic() + 3
                expected = 2 if stubborn else 1
                while len(self.get_calls("wf-recorder")) < expected and time.monotonic() < deadline:
                    time.sleep(.02)
                time.sleep(.05)
                previous = dict(state="starting", pid=99999999, identity="dead", childPid=child.pid,
                                childIdentity=recorder.identity(child.pid), childKind="recorder", file=str(filename),
                                mixerSink="velora_test_retained" if stubborn else "")
                (self.runtime / "state.json").write_text(json.dumps(previous))
                process = self.driver("r.STOP_GRACE=.15\n") if stubborn else self.start()
                self.assertEqual(process.wait(timeout=5), 1 if stubborn else 0)
                if stubborn:
                    state = recorder.status(self.runtime)
                    self.assertEqual(state["state"], "stopping")
                    self.assertTrue(state["orphaned"])
                    self.assertIn("initialization is uncertain", state["error"])
                    self.assertIsNone(child.poll())
                    self.assertEqual(state["mixerSink"], "velora_test_retained")
                    retry = self.driver("r.STOP_GRACE=.15\nmain=r.main\nr.main=lambda:main(['stop'])\n")
                    self.assertEqual(retry.wait(timeout=5), 1)
                    self.assertEqual(recorder.status(self.runtime)["childPid"], child.pid)
                    self.assertIsNone(child.poll())
                    # Explicit test cleanup only: production must not force-kill
                    # an orphan whose buffered initialization is unknowable.
                    child.kill(); child.wait(timeout=3)
                    self.assertEqual(self.call("stop").returncode, 0)
                    self.assertEqual(recorder.status(self.runtime)["state"], "idle")
                else:
                    self.assertEqual(child.wait(timeout=3), 0)
                    self.assertEqual(recorder.status(self.runtime)["state"], "idle")
                    self.assertEqual(filename.read_bytes(), b"header-finalized")
        self.assertEqual(len(self.get_calls("wf-recorder")), 2)

    def test_initialized_buffered_encoder_is_retained_not_killed(self):
        process = self.driver("r.STOP_GRACE=.15\n", {**self.env, "FAKE_BUFFERED": "1", "FAKE_STUBBORN": "1"})
        state = self.wait_state("recording")
        self.assertTrue(state["encoderInitialized"])
        self.assertEqual(Path(state["file"]).stat().st_size, 0)
        self.assertEqual(self.call("stop").returncode, 0)
        self.assertEqual(process.wait(timeout=5), 1)
        retained = recorder.status(self.runtime)
        self.assertEqual(retained["state"], "stopping")
        self.assertIn("still finalizing", retained["error"])
        self.assertEqual(recorder.identity(state["childPid"]), state["childIdentity"])
        self.assertTrue(Path(state["file"]).exists())
        os.kill(state["childPid"], signal.SIGKILL)  # test fixture cleanup only
        self.wait_dead(state["childPid"])

    def test_unload_failure_retains_ownership_for_next_stop(self):
        failure = self.root / "unload-fails"
        failure.touch()
        env = {**self.env, "FAKE_UNLOAD_FAIL": str(failure)}
        self.options["audio"] = "both"
        self.write_config()
        process = self.start(env=env)
        self.wait_state("recording")
        self.call("stop", env=env)
        self.assertEqual(process.wait(timeout=6), 1)
        state = recorder.status(self.runtime)
        self.assertEqual(state["state"], "stopping")
        self.assertTrue(state["mixerSink"])
        self.assertIn("cleanup failed", state["error"])
        self.assertIn("Video file retained:", state["error"])
        self.assertFalse(any("Recording saved" in call for call in self.get_calls("notify-send")))
        failure.unlink()
        self.assertEqual(self.call("stop", env=env).returncode, 0)
        self.assertEqual(recorder.status(self.runtime)["state"], "idle")
        self.assertEqual(json.loads(Path(str(self.calls) + ".modules").read_text()), [])

    def test_module_tsv_ids_without_json_ids_and_schema_failure(self):
        native = '1\tlibpipewire-module-rt\t{\n nice.level = -11\n}\t\n'
        with patch.object(recorder, "run", return_value=native + '12\tmodule-loopback\tsink=owned\t0'):
            modules = recorder.audio_modules()
        self.assertEqual(modules[-1], dict(index=12, name="module-loopback", argument="sink=owned"))
        with patch.object(recorder, "run", return_value=native + 'bad\tmodule-loopback\tsink=owned'):
            with self.assertRaises(ValueError):
                recorder.audio_modules()
        self.options["audio"] = "both"
        self.write_config()
        process = self.start(env={**self.env, "FAKE_MODULE_SCHEMA_ERROR": "1"})
        self.wait_state("recording")
        self.call("stop")
        self.assertEqual(process.wait(timeout=6), 1)
        state = recorder.status(self.runtime)
        self.assertIn("cannot safely clean audio mixer", state["error"])
        self.assertTrue(state["mixerSink"])
        self.assertEqual(self.call("stop").returncode, 0)
        self.assertEqual(recorder.status(self.runtime)["state"], "idle")
        self.assertTrue(any(call[1:] == ["list", "short", "modules"] for call in self.get_calls("pactl")))
        self.assertFalse(any(call[1:] == ["--format=json", "list", "modules"] for call in self.get_calls("pactl")))

    def test_selector_diagnostic_is_failure_not_escape(self):
        self.options["mode"] = "region"
        self.write_config()
        self.assertEqual(self.call(env={**self.env, "FAKE_SELECT_ERROR": "1"}).returncode, 1)
        self.assertIn("Wayland connection failed", recorder.status(self.runtime)["error"])

    @unittest.skipUnless(shutil.which("qs"), "Quickshell runtime is not installed")
    def test_qml_service_delayed_selection_survives_overlay_and_can_cancel(self):
        shell = self.root / "qml"
        for relative in ("services", "modules/common/functions"):
            (shell / relative).mkdir(parents=True)
        source = BACKEND.parents[2] / "services/ScreenRecorder.qml"
        shutil.copy2(source, shell / "services/ScreenRecorder.qml")
        (shell / "GlobalStates.qml").write_text(
            'pragma Singleton\nimport QtQuick\nimport Quickshell\nSingleton { property bool regionSelectorOpen: false; property bool overlayOpen: false; function closeSidebars() {} }\n')
        (shell / "modules/common/Config.qml").write_text(
            'pragma Singleton\nimport QtQuick\nimport Quickshell\nSingleton { property var options: ({screenRecord:{savePath:""}}) }\n')
        fake = self.root / "qml-record.sh"
        fake.write_text('#!/bin/sh\necho "$1" >> "' + str(self.root / "qml-calls") + '"\n'
                        'if [ "$1" = status ]; then echo \'{"state":"idle"}\'; fi\n')
        fake.chmod(0o755)
        (shell / "modules/common/Directories.qml").write_text(
            'pragma Singleton\nimport QtQuick\nimport Quickshell\nSingleton { property string recordScriptPath: '
            + json.dumps(str(fake)) + '; property string home: "file:///tmp/home"; property string videos: "file:///tmp/home" }\n')
        (shell / "services/Translation.qml").write_text(
            'pragma Singleton\nimport QtQuick\nimport Quickshell\nSingleton { function tr(text) { return text; } }\n')
        (shell / "modules/common/functions/FileUtils.qml").write_text(
            'pragma Singleton\nimport QtQuick\nimport Quickshell\nSingleton { function trimFileProtocol(text) { return text.replace("file://", ""); } }\n')
        (shell / "shell.qml").write_text('''import QtQuick
import Quickshell
import qs
import qs.services
Scope {
    id: root
    property int requests: 0
    property string failure: ""
    function check(condition, message) { if (!condition) failure += message + ";"; }
    Component.onCompleted: {
        const overlay = Qt.createQmlObject('import QtQuick; Item {}', root);
        ScreenRecorder.selectRegion();
        overlay.destroy();
    }
    Connections {
        target: ScreenRecorder
        function onRegionRequested(sound) {
            root.requests++;
            GlobalStates.regionSelectorOpen = true;
            ScreenRecorder.regionSelecting = true;
        }
    }
    Timer {
        interval: 450; running: true
        onTriggered: {
            root.check(root.requests === 1, "delayed request lost with overlay");
            root.check(ScreenRecorder.active, "custom picker missing from active state");
            ScreenRecorder.toggle("screen", "none");
            root.check(!GlobalStates.regionSelectorOpen && !ScreenRecorder.active, "fullscreen shortcut did not cancel custom picker");
            ScreenRecorder.toggle();
            ScreenRecorder.stop();
            root.check(!ScreenRecorder.active, "pending launch not cancelled");
        }
    }
    Timer {
        interval: 900; running: true
        onTriggered: {
            ScreenRecorder.toggle("region");
        }
    }
    Timer {
        interval: 1300; running: true
        onTriggered: {
            console.log(root.failure ? "RECORDER_QML_FAIL:" + root.failure : "RECORDER_QML_PASS");
            Qt.quit();
        }
    }
}''')
        result = subprocess.run([shutil.which("qs"), "-p", str(shell / "shell.qml"), "--no-color"],
                                env={**self.env, "QT_QPA_PLATFORM": "offscreen"},
                                capture_output=True, text=True, timeout=10)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn("RECORDER_QML_PASS", output)
        calls = (self.root / "qml-calls").read_text().splitlines()
        self.assertTrue(calls)
        self.assertTrue(all(call in ("status", "stop", "--select-region") for call in calls), calls)
        self.assertEqual(calls.count("--select-region"), 1, calls)

    def test_explicit_silent_and_failed_validation(self):
        self.options.update(audio="both")
        self.write_config()
        process = self.start("--fullscreen", "--silent")
        self.wait_state("recording")
        self.assertFalse(self.get_calls("pactl"))
        self.assertFalse(any(arg.startswith("--audio=") for arg in self.get_calls("wf-recorder")[0]))
        self.stop_capture(process)
        process = self.start("--silent", env={**self.env, "FAKE_PROBE_FAIL": "1"})
        self.wait_state("recording")
        self.call("stop")
        self.assertEqual(process.wait(timeout=6), 1)
        self.assertEqual(recorder.status(self.runtime)["state"], "error")


if __name__ == "__main__":
    unittest.main()
