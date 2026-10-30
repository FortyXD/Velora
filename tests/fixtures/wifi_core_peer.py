"""Exercise production GLib input/EOF handling with no NM client or agent."""
import importlib.util
from pathlib import Path
from types import SimpleNamespace
import sys
import time

script = Path(__file__).resolve().parents[2] / 'dots/.config/quickshell/ii/scripts/network/wifi_agent.py'
spec = importlib.util.spec_from_file_location('wifi_agent', script)
wifi = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wifi)


class OfflineRuntime:
    def __init__(self, emit):
        self.ready = True
        self.emit = emit
        self.startup_deadline = time.monotonic() + 10
        self.controller = wifi.Controller(self, emit)
        self.locked = False
        emit(dict(event='ready'))

    def acquire(self):
        self.locked = True
        return True

    def prepare(self, op, message):
        op.uuid, op.path, op.mode = 'owned', '/owned', 'wpa-psk'
        op.healthy = message.get('ssid') == 'healthy'

    def activate(self, op, done):
        active = SimpleNamespace(state='activated' if op.healthy else 'activating')
        if op.healthy:
            done(active)
        else:
            wifi.GLib.timeout_add(100, lambda: (done(active), False)[1])

    def watch(self, op, changed):
        if op.active.state == 'activated':
            changed('activated')

    def persist(self, op, done):
        done(True)

    def cancel_activation(self, op):
        # Cancelling the client's request cannot safely deactivate a daemon-side link.
        self.emit(dict(event='test-cancelled-local-request'))

    def release(self, op):
        self.locked = False
        self.emit(dict(event='test-released'))

    error_code = staticmethod(lambda error: 'connection')


wifi.Runtime = OfflineRuntime
wifi.main()
