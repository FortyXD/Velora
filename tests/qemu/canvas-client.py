"""GTK Wayland fixtures: real header buttons, independently colored content and frame feedback."""

import argparse
import json
from pathlib import Path
import time

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
gi.require_version("Graphene", "1.0")
from gi.repository import Gdk, GLib, Graphene, Gtk  # noqa: E402 (select the GTK ABI before importing)

parser = argparse.ArgumentParser()
parser.add_argument("directory", type=Path)
parser.add_argument("--count", type=int, default=1)
parser.add_argument("--app-id", default="org.velora.CanvasFixture")
args = parser.parse_args()
app = Gtk.Application(application_id=args.app_id)
windows = []
colors = [(28, 168, 128), (177, 69, 127), (67, 114, 211), (213, 135, 52)]


def record(index, kind, *args_):
    with (args.directory / f"{index}.{kind}").open("a") as log:
        log.write(json.dumps(args_) + "\n")


def create(index):
    w = Gtk.ApplicationWindow(application=app)
    windows.append(w)
    w.set_title(f"Velora canvas fixture {index}")
    w.set_default_size(420, 300)
    bar = Gtk.HeaderBar()
    bar.set_decoration_layout(":minimize,maximize,close")
    w.set_titlebar(bar)
    area = Gtk.DrawingArea()
    area.add_css_class(f"fixture-{index % len(colors)}")
    click = Gtk.GestureClick()
    click.connect("pressed", lambda _, count, x, y: record(index, "click", x, y))
    area.add_controller(click)
    keyboard = Gtk.EventControllerKey()
    keyboard.connect(
        "key-pressed", lambda _, key, code, mods: record(index, "key", Gdk.keyval_name(key)) or False
    )
    w.add_controller(keyboard)
    scroll = Gtk.EventControllerScroll.new(
        Gtk.EventControllerScrollFlags.BOTH_AXES | Gtk.EventControllerScrollFlags.DISCRETE
    )
    scroll.connect("scroll", lambda _, dx, dy: record(index, "scroll", dx, dy) or True)
    scroll.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
    w.add_controller(scroll)
    w.set_child(area)
    w.present()

    def geometry():
        if not w.get_mapped():
            return True
        points = {}

        def visit(widget):
            classes = widget.get_css_classes()
            for role in ("minimize", "maximize", "close"):
                if role in classes and widget.get_visible() and widget.get_width() > 0:
                    point = Graphene.Point()
                    point.init(widget.get_width() / 2, widget.get_height() / 2)
                    ok, pos = widget.compute_point(w, point)
                    if ok:
                        points[role] = [pos.x, pos.y]
            child = widget.get_first_child()
            while child:
                visit(child)
                child = child.get_next_sibling()

        visit(w)
        point = Graphene.Point()
        point.init(0, 0)
        ok, pos = area.compute_point(w, point)
        if ok:
            points.update(area=[pos.x, pos.y, area.get_width(), area.get_height()])
        record(index, "geometry", points)
        return not points.get("close")

    GLib.timeout_add(120, geometry)
    return False


def start(_):
    css = Gtk.CssProvider()
    css.load_from_string(
        "".join(
            f".fixture-{i} {{ background-color: rgb({r},{g},{b}); }}" for i, (r, g, b) in enumerate(colors)
        )
    )
    Gtk.StyleContext.add_provider_for_display(
        Gdk.Display.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
    )
    for index in range(args.count):
        create(index)

    def command():
        path = args.directory / "command"
        if not path.exists():
            return True
        message = path.read_text().split()
        path.unlink()
        if not message:
            return True
        if message[0] == "more":
            for index in range(len(windows), len(windows) + int(message[1])):
                create(index)
        elif message[0] == "animate":
            deadline = time.monotonic() + float(message[1])
            w = windows[int(message[2])]

            def frame(win, clock):
                record(0, "frames", clock.get_frame_time())
                win.get_child().set_opacity(0.98 if win.get_child().get_opacity() > 0.99 else 1.0)
                return time.monotonic() < deadline

            w.add_tick_callback(frame)
        elif message[0] == "quit":
            app.quit()
        else:
            w = windows[int(message[1])]
            {
                "minimize": w.minimize,
                "maximize": w.maximize,
                "restore": w.unmaximize,
                "fullscreen": w.fullscreen,
                "unfullscreen": w.unfullscreen,
            }[message[0]]()
        return True

    GLib.timeout_add(60, command)


app.connect("activate", start)
app.run([])
