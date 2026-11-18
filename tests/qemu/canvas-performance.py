"""Run via in-session.py with the test-only canvas-frames plugin loaded. Measures real output frames."""

import json
from pathlib import Path
import statistics
import subprocess
import tempfile
import time

if not Path("/var/lib/velora-qemu-ready").exists():
    raise SystemExit("Requires the disposable QEMU desktop")
here = Path(__file__).resolve().parent


def ctl(*args):
    return subprocess.check_output(["hyprctl", *args], text=True).strip()


def lua(code):
    return ctl("repl", code)


def data(name):
    return json.loads(ctl("-j", name))


def selected():
    return {
        int(w["title"].split()[-1]): w for w in data("clients") if w["class"] == "org.velora.CanvasFixture"
    }


def wait_count(n):
    for _ in range(120):
        found = selected()
        if len(found) == n:
            return found
        time.sleep(0.1)
    raise RuntimeError(f"Expected {n} windows, found {len(found)}")


def frames():
    count, *stats = lua("return hl.plugin.velora_test.frames()").split()
    return [int(count), *map(float, stats)]


def measure(directory, monitor, duration=3):
    (directory / "command").write_text(f"animate {duration + 0.6} 0")
    time.sleep(0.25)
    lua(f'hl.plugin.velora_test.frames("{monitor}")')
    time.sleep(duration)
    result = frames()
    time.sleep(0.5)
    return result


def place(address, box, canvas):
    a = json.dumps(address)
    x, y, w, h = box
    if canvas:
        assert lua(f"return hl.plugin.velora.place({a},{x},{y},{w},{h})") == "true"
    else:
        lua(
            f'local t="address:"..{a};hl.dispatch(hl.dsp.window.resize({{x={w},y={h},window=t}}));'
            f"hl.dispatch(hl.dsp.window.move({{x={x},y={y},window=t}}))"
        )


prefs = Path.home() / ".config/hypr/custom/shell_settings.json"
original = prefs.read_bytes()


def set_mode(mode):
    values = json.loads(original)
    values["shell:windowMode"] = mode
    prefs.write_text(json.dumps(values))
    ctl("reload")
    time.sleep(0.7)
    assert lua("return hl.plugin.velora.active()") == str(mode == "canvas").lower()


outputs = data("monitors")
primary = next(m for m in outputs if m["name"] == "Virtual-1")
secondary = next(m for m in outputs if m["name"] == "Canvas-2")
ctl("dispatch", "hl.dsp.cursor.move({x=640,y=400})")
set_mode("floating")
hidden = []
with tempfile.TemporaryDirectory(prefix="velora-frame-sample-") as tmp:
    directory = Path(tmp)
    fixture = None
    try:
        for w in data("clients"):
            if w["workspace"]["type"] != "special" and not w["pinned"]:
                lua(f'require("hyprland.window_actions").minimize("{w["address"]}")')
                hidden.append(w["address"])
        lua('hl.dispatch(hl.dsp.focus({monitor="Virtual-1"}))')
        fixture = subprocess.Popen(
            ["python", str(here / "canvas-client.py"), tmp, "--count", "4"], stdout=subprocess.DEVNULL
        )
        found = wait_count(4)
        boxes = [(100, 65, 420, 300), (720, 65, 420, 300), (100, 435, 420, 300), (720, 435, 420, 300)]
        for i, w in found.items():
            place(w["address"], boxes[i], False)
        time.sleep(0.75)
        baseline = [measure(directory, primary["name"]) for _ in range(3)]
        set_mode("canvas")
        lua('hl.plugin.velora.camera("reset")')
        ctl("dispatch", f"hl.dsp.cursor.move({{x={secondary['x'] + 450},y=320}})")
        lua('hl.plugin.velora.camera("pan",150000,140000)')
        ctl("dispatch", "hl.dsp.cursor.move({x=640,y=400})")
        for i, w in found.items():
            place(w["address"], boxes[i], True)
        time.sleep(1.4)
        four = [measure(directory, primary["name"]) for _ in range(3)]
        (directory / "command").write_text("more 50")
        for i, w in wait_count(54).items():
            if i >= 4:
                place(w["address"], (15000 + i * 470, 6000, 420, 300), True)
        # A camera with no visible surfaces should stay idle while another output animates.
        ctl("dispatch", f"hl.dsp.cursor.move({{x={secondary['x'] + 450},y=320}})")
        lua('hl.plugin.velora.camera("pan",150000,140000)')
        ctl("dispatch", "hl.dsp.cursor.move({x=640,y=400})")
        time.sleep(1.7)
        fifty_four = [measure(directory, primary["name"]) for _ in range(3)]
        idle = measure(directory, secondary["name"], 2)
        print(
            json.dumps(
                {
                    "floating": baseline,
                    "canvas_4": four,
                    "canvas_4_plus_50": fifty_four,
                    "empty_camera_during_primary_animation": idle,
                }
            ),
            flush=True,
        )
        assert min(sample[0] for sample in baseline + four + fifty_four) >= 30, (
            "Insufficient presented frames"
        )
        assert all(3.8 <= sample[3] <= 4.2 for sample in baseline + four + fifty_four), (
            "Four windows must actually be drawn"
        )
        assert idle[0] == 0, "Empty camera kept rendering"
        loaded_p95 = statistics.median(sample[1] for sample in fifty_four)
        for name, runs in (("four canvas windows", four), ("four free windows", baseline)):
            reference_p95 = statistics.median(sample[1] for sample in runs)
            assert loaded_p95 <= reference_p95 * 1.15, f"Canvas exceeded the 15% p95 budget against {name}"
    finally:
        if fixture:
            (directory / "command").write_text("quit")
            try:
                fixture.wait(timeout=8)
            except subprocess.TimeoutExpired:
                fixture.terminate()
                fixture.wait()
        prefs.write_bytes(original)
        ctl("reload")
        for address in hidden:
            lua(f'require("hyprland.window_actions").restore("{address}")')
