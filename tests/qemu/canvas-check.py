"""Exercise real Wayland buttons, two camera projections and pointer coordinates in the QEMU guest."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

from PIL import Image, ImageChops

if not Path("/var/lib/velora-qemu-ready").exists():
    raise SystemExit("Run via in-session.py inside the disposable test guest")
parser = argparse.ArgumentParser()
parser.add_argument("--touchpad", type=Path)
options = parser.parse_args()
here = Path(__file__).resolve().parent
prefs = Path.home() / ".config/hypr/custom/shell_settings.json"
old = prefs.read_bytes()
app = "org.velora.CanvasFunctional"
pointer_env = dict(os.environ, YDOTOOL_SOCKET=f"/run/user/{os.getuid()}/ydotool.sock")


def ctl(*args):
    return subprocess.check_output(["hyprctl", *args], text=True).strip()


def lua(code):
    return ctl("repl", code)


def dispatch(code):
    return ctl("dispatch", code)


def wait(probe, label):
    until = time.monotonic() + 5
    while time.monotonic() < until:
        result = probe()
        if result:
            return result
        time.sleep(0.06)
    raise AssertionError(label)


def modes(mode):
    values = json.loads(old)
    values["shell:windowMode"] = mode
    prefs.write_text(json.dumps(values))
    ctl("reload")
    wait(
        lambda: (
            lua("return hl.plugin.velora and hl.plugin.velora.active() or false")
            == str(mode == "canvas").lower()
        ),
        mode,
    )
    errors = ctl("configerrors")
    assert not errors, errors


def windows():
    return {int(w["title"].split()[-1]): w for w in json.loads(ctl("-j", "clients")) if w["class"] == app}


def move(x, y):
    dispatch(f"hl.dsp.cursor.move({{x={int(x)},y={int(y)}}})")


def click(x, y):
    move(x, y)
    subprocess.run(["ydotool", "click", "0xC0"], env=pointer_env, stdout=subprocess.DEVNULL, check=True)


def readlog(path):
    return json.loads(path.read_text().splitlines()[-1])


def open_apps(directory):
    client = subprocess.Popen(
        ["python", str(here / "canvas-client.py"), str(directory), "--app-id", app, "--count", "2"]
    )
    wait(lambda: len(windows()) == 2 and (directory / "0.geometry").exists(), "launch two GTK windows")
    return client


def close_apps(directory, client):
    (directory / "command").write_text("quit")
    client.wait(timeout=5)
    wait(lambda: len(windows()) == 0, "close fixtures")


def color_box(output, directory, *, visible=True):
    path = directory / (output + ".png")
    ctl_proc = subprocess.run(["grim", "-o", output, str(path)], capture_output=True)
    assert ctl_proc.returncode == 0, ctl_proc.stderr
    im = Image.open(path).convert("RGB")
    channels = im.split()
    masks = [ch.point(lambda v, c=c: 255 if v == c else 0) for ch, c in zip(channels, (28, 168, 128))]
    box = ImageChops.multiply(ImageChops.multiply(masks[0], masks[1]), masks[2]).getbbox()
    if visible:
        assert box and box[2] - box[0] > 45 and box[3] - box[1] > 35, (output, box)
    else:
        assert box is None, (output, box)
    return box, im


def geometry(addr):
    return tuple(
        map(float, lua(f'local b=hl.plugin.velora.geometry("{addr}"); return b.x,b.y,b.w,b.h').split())
    )


with tempfile.TemporaryDirectory(prefix="velora-canvas-functional-") as tmp:
    directory = Path(tmp)
    client = None
    created = False
    try:
        modes("floating")
        if not any(m["name"] == "Canvas-2" for m in json.loads(ctl("-j", "monitors"))):
            ctl("output", "create", "headless", "Canvas-2")
            created = True

        def position_outputs():
            lua('hl.monitor({output="Canvas-2",mode="1280x800@60",position="1280x0",scale=1})')
            move(640, 400)
            dispatch('hl.dsp.focus({monitor="Virtual-1"})')

        position_outputs()
        client = open_apps(directory)
        w = windows()[0]
        addr = w["address"]
        restore = f'require("hyprland.window_actions").restore("{addr}")'
        other = windows()[1]["address"]
        dispatch(f'hl.dsp.window.move({{x=820,y=350,window="address:{other}"}})')
        dispatch(f'hl.dsp.window.move({{x=200,y=175,window="address:{addr}"}})')
        move(360, 285)
        lua(restore)
        wait(
            lambda: json.loads(ctl("-j", "activewindow")).get("address") == addr,
            f"focus native fixture {addr}; clients {[(i, v['at'], v['size'], v['workspace'], v['floating']) for i, v in windows().items()]}",
        )
        w = windows()[0]
        controls = readlog(directory / "0.geometry")[0]
        assert {"minimize", "maximize", "close"} <= controls.keys(), controls

        def press(role):
            x, y = windows()[0]["at"]
            dx, dy = controls[role]
            click(x + dx, y + dy)

        before = (w["at"], w["size"])
        press("maximize")
        wait(lambda: windows()[0]["fullscreen"] == 1, "native GTK maximize")
        assert windows()[0]["size"][0] > before[1][0]
        (directory / "command").write_text("restore 0")
        wait(
            lambda: windows()[0]["fullscreen"] == 0 and windows()[0]["size"] == before[1], "restore geometry"
        )
        press("minimize")
        wait(
            lambda: windows()[0]["workspace"]["address"].startswith("special:velora-min-"),
            "native GTK minimize",
        )
        ctl("reload")
        lua(restore)
        wait(lambda: windows()[0]["workspace"]["address"] == "1", "restore after config reload")
        assert "Velora title bar" not in ctl("decorations", "address:" + addr)
        term = subprocess.Popen(
            ["foot", "-o", "csd.preferred=server", "--app-id=org.velora.SSDTest", "sleep", "30"]
        )
        try:

            def terminal(pid=term.pid):
                return next(
                    (v for v in json.loads(ctl("-j", "clients")) if v["pid"] == pid), None
                )

            tw = wait(terminal, "Wayland SSD terminal")
            ta = tw["address"]
            wait(lambda: "Velora title bar" in ctl("decorations", "address:" + ta), "server-side caption")
            csd = subprocess.Popen(["foot", "-o", "csd.preferred=client", "--app-id=org.velora.SSDTest", "sleep", "30"])
            try:
                own = wait(lambda: terminal(csd.pid), "Wayland CSD terminal with the same app ID")
                assert "Velora title bar" not in ctl("decorations", "address:" + own["address"])
                assert "Velora title bar" in ctl("decorations", "address:" + ta)
            finally:
                csd.terminate()
                csd.wait(timeout=5)
            wait(lambda: terminal(csd.pid) is None, "close the CSD terminal")
            x, y = tw["at"]
            width = tw["size"][0]
            click(x + width - 57, y - 16)
            wait(lambda: terminal()["fullscreen"] == 1, "Velora maximize button")
            lua(f'require("hyprland.window_actions").toggle_maximize("{ta}")')
            wait(lambda: terminal()["fullscreen"] == 0, "restore Velora frame")
            click(x + width - 95, y - 16)
            wait(lambda: terminal()["workspace"]["type"] == "special", "Velora minimize button")
            lua(f'require("hyprland.window_actions").restore("{ta}")')
            lua(f'hl.plugin.velora.caption("{ta}","off")')
            assert "Velora title bar" not in ctl("decorations", "address:" + ta)
            lua(f'hl.plugin.velora.caption("{ta}","auto")')
            assert "Velora title bar" in ctl("decorations", "address:" + ta)
        finally:
            term.terminate()
            term.wait(timeout=5)
        print("PASS native SSD minimize, maximize and per-app override", flush=True)
        print("PASS native GTK controls and reload", flush=True)
        modes("canvas")
        position_outputs()
        lua('hl.plugin.velora.camera("reset")')
        windows0 = windows()
        for index, x in ((0, 200), (1, 780)):
            a = windows0[index]["address"]
            assert lua(f'return hl.plugin.velora.place("{a}",{x},175,420,300)') == "true"
        home_boxes = sorted(geometry(w["address"]) for w in windows0.values())
        for factor in (0.5, 1.0, 1.6):
            move(280, 320)
            lua(f'hl.plugin.velora.camera("zoom",{factor})')
            move(1220, 45)  # QEMU composites its software cursor into capture buffers.
            time.sleep(0.15)
            box, im = color_box("Virtual-1", directory)
            x = (box[0] + box[2]) // 2
            y = (box[1] + box[3]) // 2
            if im.getpixel((x, y)) != (28, 168, 128):
                im.save(Path.home() / "evidence" / "canvas-pixel-check.png")
                raise AssertionError(("client color at center", factor, box, (x, y), im.getpixel((x, y))))
            assert abs(box[2] - box[0] - 420 * factor) < 5, (factor, box)
            log = directory / "0.click"
            count = len(log.read_text().splitlines()) if log.exists() else 0
            click(x, y)
            wait(
                lambda: log.exists() and len(log.read_text().splitlines()) > count, "client pointer delivery"
            )
            local = readlog(log)
            assert abs(local[0] - (x - box[0]) / factor) < 3 and abs(local[1] - (y - box[1]) / factor) < 3, (
                factor,
                local,
                box,
            )
            assert windows()[0]["size"] == [420, 300]
        subprocess.run(["wtype", "k"], check=True)
        wait(
            lambda: (directory / "0.key").exists() and readlog(directory / "0.key") == ["k"],
            "keyboard reaches the projected client",
        )
        subprocess.run(["ydotool", "mousemove", "-w", "--", "0", "-1"], env=pointer_env, check=True)
        wait(lambda: (directory / "0.scroll").exists(), "ordinary wheel reaches GTK")
        move(300, 325)
        subprocess.run(["ydotool", "key", "125:1"], env=pointer_env, check=True)
        try:
            subprocess.run(["ydotool", "click", "0x42"], env=pointer_env, check=True)
            move(350, 350)
            subprocess.run(["ydotool", "click", "0x82"], env=pointer_env, check=True)
            time.sleep(0.15)
            shifted, _ = color_box("Virtual-1", directory)
            assert abs(shifted[0] - box[0] - 50) < 4, (shifted, box)
            subprocess.run(["ydotool", "mousemove", "-w", "--", "0", "1"], env=pointer_env, check=True)
            time.sleep(0.15)
            scaled, _ = color_box("Virtual-1", directory)
            assert abs((scaled[2] - scaled[0]) - (shifted[2] - shifted[0])) > 20
        finally:
            subprocess.run(["ydotool", "key", "125:0"], env=pointer_env, check=True)
        if options.touchpad:
            state = Path.home() / ".local/state/velora/windows.json"

            def camera_state():
                time.sleep(0.5)
                return json.loads(state.read_text())["cameras"]["Virtual-1/1"]

            start = camera_state()
            subprocess.run(["ydotool", "key", "125:1"], env=pointer_env, check=True)
            try:
                subprocess.run([options.touchpad, "pinch"], check=True)
                pinched = camera_state()
                assert pinched[2] > start[2] * 1.1, (start, pinched)
                subprocess.run([options.touchpad, "scroll"], check=True)
                panned = camera_state()
                assert abs(panned[1] - pinched[1]) > 4 and panned[2] == pinched[2]
            finally:
                subprocess.run(["ydotool", "key", "125:0"], env=pointer_env, check=True)
            print("PASS libinput two-finger pinch and scroll", flush=True)
        lua('hl.plugin.velora.camera("zoom",1.6)')
        print("PASS keyboard, client wheel, Super + middle drag and wheel", flush=True)
        print("PASS projected buffers and actual pointer coordinates at 50%, 100%, 160%", flush=True)
        move(1920, 400)
        lua('hl.plugin.velora.camera("fit")')
        # The benchmark may have many remembered slots. Only live windows participate in fit.
        box, im = color_box("Canvas-2", directory)
        px = (box[0] + box[2]) // 2
        py = (box[1] + box[3]) // 2
        previous = len(log.read_text().splitlines())
        click(1280 + px, py)
        wait(lambda: len(log.read_text().splitlines()) > previous, "click second projection")
        wait(lambda: windows()[0]["workspace"]["address"] == "2", "focus stays on second output")
        primary_box, _ = color_box("Virtual-1", directory)
        assert abs(primary_box[2] - primary_box[0] - 420 * 1.6) < 5
        (directory / "command").write_text("maximize 0")
        wait(lambda: windows()[0]["fullscreen"] == 1 and windows()[0]["monitor"] == 1, "local maximize")
        second_box, _ = color_box("Canvas-2", directory)
        first_box, _ = color_box("Virtual-1", directory)
        assert second_box[2] - second_box[0] > 1100 and first_box[2] - first_box[0] < 800
        (directory / "command").write_text("restore 0")
        wait(lambda: windows()[0]["fullscreen"] == 0, "unmaximize on second output")
        lua("hl.plugin.velora.desktop()")
        time.sleep(0.15)
        color_box("Canvas-2", directory, visible=False)
        color_box("Virtual-1", directory)
        lua("hl.plugin.velora.desktop()")
        color_box("Canvas-2", directory)
        print("PASS independent cameras, local maximize and show desktop", flush=True)
        close_apps(directory, client)
        client = None
        client = open_apps(directory)
        restored = sorted(geometry(w["address"]) for w in windows().values())
        assert restored == home_boxes, (home_boxes, restored)
        print("PASS two independent geometry slots on manual relaunch", flush=True)
        modes("tiling")
        wait(lambda: all(not w["floating"] for w in windows().values()), "retile existing clients")
        print("PASS return to tiling", flush=True)
    finally:
        if client is not None:
            close_apps(directory, client)
        prefs.write_bytes(old)
        ctl("reload")
        if created:
            ctl("output", "remove", "Canvas-2")
