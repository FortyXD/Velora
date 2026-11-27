"""Use a real GTK application on a private Broadway display and accessibility bus."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import unittest

import test_agent


@unittest.skipUnless(os.environ.get("VELORA_TEST_PREBUILT") and os.environ.get("DBUS_SESSION_BUS_ADDRESS")
                     and shutil.which("broadwayd"), "needs an isolated session bus and GTK Broadway")
class AccessibleWorkflow(unittest.TestCase):
    def test_observe_edit_activate_and_check_a_real_form(self):
        fixture = test_agent.AgentTests()
        fixture.setUp()
        self.addCleanup(fixture.tearDown)
        env = dict(fixture.env, GDK_BACKEND="broadway", BROADWAY_DISPLAY=":9", NO_AT_BRIDGE="0")
        def start(*argv):
            proc = subprocess.Popen(argv, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.addCleanup(lambda: (proc.terminate(), proc.wait(timeout=5)) if proc.poll() is None else None)
            return proc
        start("/usr/bin/broadwayd", "-a", "127.0.0.1", ":9")
        socket = Path(env["XDG_RUNTIME_DIR"])/"broadway10.socket"
        for _ in range(100):
            if socket.exists(): break
            time.sleep(.02)
        gui = start("/usr/bin/python3", "-c", """
import gi, os
from pathlib import Path
gi.require_version('Gtk','3.0')
from gi.repository import Gtk
window = Gtk.Window(title='Velora test form')
box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
field = Gtk.Entry()
field.get_accessible().set_name('Meeting title')
save = Gtk.Button(label='Save meeting')
save.connect('clicked', lambda *_: (Path(os.environ['TEST_ROOT'])/'saved').write_text(field.get_text()))
box.add(field); box.add(save); window.add(box); window.show_all()
Gtk.main()
""")
        hypr = {"address":"0xabc","pid":gui.pid,"title":"Velora test form","at":[0,0],"size":[400,200]}
        fixture.fake("hyprctl", "print(" + repr(json.dumps(hypr)) + " if sys.argv[-1]=='activewindow' else '[]')")
        helper = Path(__file__).resolve().parents[1]/"tools/velora-agentd/python/tools.py"
        inspect = dict(operation="inspect", pid=gui.pid, title=hypr["title"])
        for _ in range(50):
            output = subprocess.run(["/usr/bin/python3", "-I", str(helper)], env=env, input=json.dumps(inspect),
                                    capture_output=True, text=True, timeout=8)
            nodes = json.loads(output.stdout).get("nodes", [])
            names = {n["name"]:n for n in nodes}
            if names.get("Meeting title", {}).get("editable") and names.get("Save meeting", {}).get("actions"): break
            self.assertIsNone(gui.poll(), "GTK fixture exited")
            time.sleep(.1)
        else:
            self.fail(f"Form did not appear on the private accessibility bus: {nodes}")
        edit = names["Meeting title"]["id"]
        save = names["Save meeting"]
        fixture.configure(profile={"provider":"ollama","endpoint":"http://127.0.0.1:1","model":"fixture"})
        fixture.local_model([["ui_inspect",{}], ["ui_set_text",{"node":edit,"text":"Budget review"}],
                             ["ui_inspect",{}], ["ui_action",{"node":save["id"],"action":save["actions"][0]}],
                             ["ui_inspect",{}], "Form checked"])
        fixture.send("submit", {"text":"Rellena el formulario y guarda la reunión.", "desktop_agent":True})
        _, events = fixture.until(lambda e:e["type"]=="finished", seconds=45)
        self.assertFalse(any(e["type"]=="error" for e in events), events)
        self.assertEqual((fixture.root/"saved").read_text(), "Budget review")
        self.assertEqual([e["tool"] for e in events if e["type"]=="approval"],
                         ["ui_inspect","ui_set_text","ui_inspect","ui_action","ui_inspect"])
