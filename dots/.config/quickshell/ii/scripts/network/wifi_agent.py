#!/usr/bin/env python3
"""Owned, interactive Wi-Fi activation. JSONL stdin is the only credential input.

No custom secret storage. The agent declines all requests outside its current
UUID/path. stdout contains only the small, non-secret event protocol.
"""
import fcntl
import json
import os
from pathlib import Path
import re
import signal
import stat
import sys
import time
import uuid


SECURITY = "802-11-wireless-security"
MAX_FRAME = 16384


def valid_password(value, mode):
    if not isinstance(value, str) or "\x00" in value:
        return False
    try:
        size = len(value.encode("utf-8"))
    except UnicodeError:
        return False
    # SAE passwords are not WPA's raw 256-bit PSKs.
    return (1 <= size <= 63) if mode == "sae" else (
        8 <= size <= 63 or re.fullmatch(r"[0-9a-fA-F]{64}", value) is not None)


class Frames:
    """Bounded incremental UTF-8 JSONL; no blocking readline in the GLib loop."""
    def __init__(self, receive):
        self.buffer = bytearray()
        self.receive = receive

    def feed(self, data):
        for chunk in data.splitlines(keepends=True):
            self.buffer.extend(chunk)
            if len(self.buffer) > MAX_FRAME:
                raise ValueError("frame too large")
            if self.buffer.endswith(b"\n"):
                raw = bytes(self.buffer)
                self.buffer.clear()
                item = json.loads(raw)
                if not isinstance(item, dict):
                    raise ValueError("expected object")
                self.receive(item)


class Operation:
    def __init__(self, token):
        self.token = token
        self.uuid = ""
        self.path = None
        self.mode = ""
        self.pending = None
        self.secret = None
        self.request = 0
        self.cancelled = False
        self.done = False
        self.callback_pending = True
        self.active = None
        self.deadline = time.monotonic() + 60


class Controller:
    """Single-operation state machine, also exercised with a fake NM transport."""
    def __init__(self, transport, emit):
        self.transport = transport
        self.emit = emit
        self.op = None

    def event(self, op, event, **extra):
        self.emit(dict(event=event, operation=op.token, **extra))

    def command(self, message):
        command = message.get("command")
        token = message.get("operation")
        if not isinstance(token, str) or not 0 < len(token) <= 128:
            return
        if command == "connect":
            if self.op or not self.transport.acquire():
                self.emit(dict(event="failed", operation=token, code="busy"))
                return
            op = self.op = Operation(token)
            try:
                self.transport.prepare(op, message)
                self.event(op, "connecting")
                self.transport.activate(op, lambda active, error=None: self.started(op, active, error))
            except Exception as error:
                op.callback_pending = False
                self.finish(op, "failed", code=self.transport.error_code(error))
        elif self.op and token == self.op.token:
            op = self.op
            if command == "cancel":
                self.cancel(op)
            elif command == "submit" and not op.cancelled and op.pending and message.get("request") == str(op.request):
                value = message.get("password")
                if not valid_password(value, op.mode):
                    self.event(op, "secret-required", request=str(op.request), code="invalid-password")
                    return
                reply, op.pending = op.pending, None
                op.secret = value
                op.deadline = time.monotonic() + 60
                self.event(op, "connecting")
                reply(value, None)

    def request_secret(self, connection_uuid, path, mode, flags, reply):
        op = self.op
        if (not op or op.done or op.cancelled or connection_uuid != op.uuid
                or (op.path is not None and path != op.path) or mode != op.mode):
            reply(None, "NOSECRETS")
            return
        # A new in-memory connection acquires its NM path at the first request.
        if op.path is None:
            op.path = path
        if op.pending:
            reply(None, "NOSECRETS")
            return
        if flags & 2:  # REQUEST_NEW invalidates our previous answer, including retry caches.
            op.secret = None
        elif op.secret is not None:
            reply(op.secret, None)
            return
        if not flags & 3:  # USER_REQUESTED alone does not authorize a prompt.
            reply(None, "NOSECRETS")
            return
        op.pending = reply
        op.request += 1
        op.deadline = None  # User think-time is intentionally unbounded.
        self.event(op, "secret-required", request=str(op.request), code="retry" if flags & 2 else "")

    def cancel_request(self, path):
        op = self.op
        if op and op.path == path and op.pending:
            reply, op.pending = op.pending, None
            reply(None, "AGENTCANCELED")
            op.deadline = time.monotonic() + 60
            self.event(op, "connecting")  # Invalidate the UI's old request token.

    def started(self, op, active, error=None):
        if not op.callback_pending:  # Duplicate callback cannot reattach or disconnect anything.
            return
        op.callback_pending = False
        op.active = active
        if self.op is not op:
            return
        if op.cancelled:
            try:
                self.transport.cancel_activation(op)
            finally:
                self.release(op)
        elif error:
            self.finish(op, "failed", code=self.transport.error_code(error))
        elif active is None:
            self.finish(op, "failed", code="unavailable")
        else:
            self.transport.watch(op, lambda state, code="connection": self.state(op, state, code))

    def state(self, op, state, code="connection"):
        if self.op is not op or op.done or op.cancelled:
            return
        if state == "activated":
            # Mark successful before saving: cancellation must never tear this link down.
            op.done = True
            if op.pending:
                reply, op.pending = op.pending, None
                reply(None, "AGENTCANCELED")
            self.event(op, "saving")
            op.deadline = time.monotonic() + 15
            try:
                self.transport.persist(op, lambda saved: self.saved(op, saved))
            except Exception:
                self.saved(op, False)
        elif state == "deactivated":
            self.finish(op, "failed", code=code)

    def saved(self, op, saved):
        if self.op is op and op.done and not op.cancelled:
            self.event(op, "connected", code="" if saved else "not-saved")
            self.release(op)

    def finish(self, op, event, **extra):
        if self.op is not op or op.done:
            return
        op.done = True
        if op.pending:
            reply, op.pending = op.pending, None
            reply(None, "USERCANCELED")
        op.secret = None
        self.event(op, event, **extra)
        if not op.callback_pending:
            self.release(op)

    def cancel(self, op, code=None):
        if op.done or op.cancelled:
            return
        op.cancelled = True
        try:
            self.transport.cancel_activation(op)
        finally:
            self.finish(op, "failed" if code else "cancelled", **({"code": code} if code else {}))

    def tick(self, now=None):
        op = self.op
        if op and op.deadline and (now or time.monotonic()) >= op.deadline:
            if op.done and not op.cancelled:
                self.saved(op, False)  # Connected but persistence did not finish.
            elif not op.done:
                self.cancel(op, "timeout")

    def release(self, op):
        if self.op is op:
            op.secret = None
            self.transport.release(op)
            self.op = None


# GI is intentionally below the protocol/state machine, so it can be tested
# without a running daemon or any privileged system fixture.
try:
    import gi
    gi.require_version("NM", "1.0")
    gi.require_version("GLibUnix", "2.0")
    from gi.repository import Gio, GLib, GLibUnix, NM
except (ImportError, ValueError):
    if __name__ == "__main__":
        print('{"event":"unavailable"}', flush=True)
        sys.exit(1)
    raise


def agent_error(name):
    return GLib.Error.new_literal(NM.secret_agent_error_quark(), "Wi-Fi credential request declined", int(getattr(NM.SecretAgentError, name)))


class Agent(NM.SecretAgentOld):
    controller = None

    def do_get_secrets(self, connection, path, setting, hints, flags, callback, data):
        security = connection.get_setting_wireless_security()
        def reply(secret, error):
            values = GLib.Variant("a{sa{sv}}", {SECURITY: {"psk": GLib.Variant("s", secret)}}) if secret is not None else None
            # GI closes over user_data; passing it here is an ABI error.
            callback(self, connection, values, agent_error(error) if error else None)
        if setting != SECURITY or security is None or security.get_key_mgmt() not in ("wpa-psk", "sae") or self.controller is None:
            reply(None, "NOSECRETS")
            return
        self.controller.request_secret(connection.get_uuid(), path, security.get_key_mgmt(), int(flags), reply)

    def do_cancel_get_secrets(self, path, setting):
        if self.controller and setting == SECURITY:
            self.controller.cancel_request(path)

    def do_save_secrets(self, connection, path, callback, data):
        # We are not a durable agent/keyring. Never falsely acknowledge a save.
        callback(self, connection, agent_error("NOSECRETS"))

    def do_delete_secrets(self, connection, path, callback, data):
        callback(self, connection, agent_error("NOSECRETS"))


class BackendError(Exception):
    def __init__(self, code):
        self.code = code


class Runtime:
    def __init__(self, emit):
        self.emit = emit
        self.client = None
        self.agent = Agent(identifier="org.velora.Wifi.p" + str(os.getpid()) + "." + uuid.uuid4().hex, auto_register=False)
        self.controller = Controller(self, emit)
        self.agent.controller = self.controller
        self.lock = None
        self.ready = False
        self.agent.connect("notify::registered", self.registration_changed)
        self.startup_deadline = time.monotonic() + 10
        self.agent.init_async(GLib.PRIORITY_DEFAULT, None, self.initialized, None)

    def initialized(self, agent, result, data):
        try:
            agent.init_finish(result)
            agent.register_async(None, self.registered, None)
        except Exception:
            self.emit(dict(event="unavailable"))

    def registered(self, agent, result, data):
        try:
            agent.register_finish(result)
            NM.Client.new_async(None, self.client_ready, None)
        except Exception:
            self.emit(dict(event="unavailable"))

    def client_ready(self, source, result, data):
        try:
            self.client = NM.Client.new_finish(result)
            if not self.client.get_nm_running() or not self.agent.get_registered():
                raise BackendError("unavailable")
            self.client.connect("notify::nm-running", self.daemon_changed)
            self.ready = True
            self.emit(dict(event="ready"))
        except Exception:
            self.emit(dict(event="unavailable"))

    def registration_changed(self, *_):
        if self.ready and not self.agent.get_registered():
            self.ready = False
            self.emit(dict(event="unavailable"))

    def daemon_changed(self, *_):
        if not self.client.get_nm_running():
            op = self.controller.op
            if op:
                self.controller.cancel(op, "unavailable")
            self.ready = False
            self.emit(dict(event="unavailable"))

    def acquire(self):
        if not self.ready or not self.agent.get_registered():
            return False
        # Canonical per-UID location, even if the two UI processes have different environments.
        runtime_dir = Path("/run/user") / str(os.getuid())
        directory = (runtime_dir if runtime_dir.is_dir() else Path("/tmp")) / ("velora-wifi-" + str(os.getuid()))
        directory.mkdir(mode=0o700, exist_ok=True)
        info = directory.lstat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            return False
        fd = os.open(directory / "operation.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
        try:
            info = os.fstat(fd)
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
                raise OSError()
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            os.close(fd)
            return False
        self.lock = fd
        return True

    def release(self, op):
        for obj, handler in getattr(op, "handlers", []):
            obj.disconnect(handler)
        if self.lock is not None:
            os.close(self.lock)
            self.lock = None

    def prepare(self, op, message):
        ssid = message.get("ssid")
        if not isinstance(ssid, str) or not 1 <= len(ssid.encode("utf-8")) <= 32 or "\x00" in ssid:
            raise BackendError("invalid-name")
        profile_uuid = message.get("uuid")
        op.profile = self.client.get_connection_by_uuid(profile_uuid) if profile_uuid else None
        if profile_uuid and op.profile is None:
            raise BackendError("unavailable")
        op.new = op.profile is None
        hidden = message.get("hidden") is True
        bssid = message.get("bssid", "")
        devices = [d for d in self.client.get_devices() if isinstance(d, NM.DeviceWifi) and d.get_managed()]
        ap = None
        op.device = None
        for device in devices:
            if op.profile and not device.connection_valid(op.profile):
                continue
            for candidate in device.get_access_points():
                raw = candidate.get_ssid()
                if raw and bytes(raw.get_data()) == ssid.encode("utf-8") and (not bssid or candidate.get_bssid() == bssid) and (not op.profile or candidate.connection_valid(op.profile)):
                    op.device, ap = device, candidate
                    break
            if op.device:
                break
        if not op.device and hidden and devices:
            op.device = next((d for d in devices if not op.profile or d.connection_valid(op.profile)), None)
        if not op.device:
            raise BackendError("unavailable")
        op.previous = op.device.get_active_connection()
        if op.previous and op.previous.get_state() == NM.ActiveConnectionState.ACTIVATING:
            raise BackendError("busy")
        if op.previous and op.profile and op.previous.get_uuid() == op.profile.get_uuid() and op.previous.get_state() == NM.ActiveConnectionState.ACTIVATED:
            raise BackendError("already-connected")
        if op.profile:
            wifi = op.profile.get_setting_wireless()
            security = op.profile.get_setting_wireless_security()
            if not wifi or bytes(wifi.get_ssid().get_data()) != ssid.encode("utf-8"):
                raise BackendError("unsupported")
            op.mode = security.get_key_mgmt() if security else "open"
            op.uuid = op.profile.get_uuid()
            op.path = op.profile.get_path()
        else:
            op.uuid = str(uuid.uuid4())
            if hidden:
                op.mode = message.get("security", "wpa-psk")
            else:
                flags = int(ap.get_wpa_flags() | ap.get_rsn_flags())
                if flags & int(getattr(NM, "80211ApSecurityFlags").KEY_MGMT_802_1X):
                    raise BackendError("unsupported")
                op.mode = "wpa-psk" if flags & int(getattr(NM, "80211ApSecurityFlags").KEY_MGMT_PSK) else "sae" if flags & int(getattr(NM, "80211ApSecurityFlags").KEY_MGMT_SAE) else "unsupported" if int(ap.get_flags()) & int(getattr(NM, "80211ApFlags").PRIVACY) else "open"
            op.profile = NM.SimpleConnection.new()
            connection = NM.SettingConnection.new()
            connection.props.id = ssid
            connection.props.uuid = op.uuid
            connection.props.type = "802-11-wireless"
            connection.props.autoconnect = False
            op.profile.add_setting(connection)
            wifi = NM.SettingWireless.new()
            wifi.props.ssid = GLib.Bytes.new(ssid.encode("utf-8"))
            wifi.props.mode = "infrastructure"
            wifi.props.hidden = hidden
            op.profile.add_setting(wifi)
            if op.mode in ("wpa-psk", "sae"):
                security = NM.SettingWirelessSecurity.new()
                security.props.key_mgmt = op.mode
                security.props.psk_flags = NM.SettingSecretFlags.NONE
                if op.mode == "sae":
                    security.props.pmf = NM.SettingWirelessSecurityPmf.REQUIRED
                op.profile.add_setting(security)
        if op.mode not in ("open", "wpa-psk", "sae"):
            raise BackendError("unsupported")
        op.specific = ap.get_path() if ap else None
        op.handlers = []
        if op.new:
            op.profile.normalize()

    def activate(self, op, done):
        def completed(client, result, data):
            try:
                if op.new:
                    active, _ = client.add_and_activate_connection2_finish(result)
                else:
                    active = client.activate_connection_finish(result)
            except Exception as error:
                done(None, error)
                return
            done(active)
        # Cancellation stops this client request, not an established link. Do not
        # bind activation to our bus lifetime: a crashed UI must leave success intact.
        op.cancellable = Gio.Cancellable.new()
        if op.new:
            self.client.add_and_activate_connection2(op.profile, op.device, op.specific,
                GLib.Variant("a{sv}", {"persist": GLib.Variant("s", "memory")}), op.cancellable, completed, None)
        else:
            self.client.activate_connection_async(op.profile, op.device, op.specific, op.cancellable, completed, None)

    def watch(self, op, changed):
        def state(active, value, reason):
            if value == NM.ActiveConnectionState.ACTIVATED:
                changed("activated")
            elif value == NM.ActiveConnectionState.DEACTIVATED:
                changed("deactivated", self.reason_code(reason, op.device.get_state_reason()))
        op.handlers.append((op.active, op.active.connect("state-changed", state)))
        state(op.active, op.active.get_state(), NM.ActiveConnectionStateReason.UNKNOWN)

    def cancel_activation(self, op):
        # DeactivateConnection has no atomic 'only if ACTIVATING' condition.
        # Even checking the exact object can race a successful activation. Never
        # send it: cancel our request and let the daemon-side attempt settle.
        cancellable = getattr(op, "cancellable", None)
        if cancellable:
            cancellable.cancel()

    @staticmethod
    def error_code(error):
        if isinstance(error, BackendError):
            return error.code
        if isinstance(error, GLib.Error):
            if (error.matches(NM.manager_error_quark(), NM.ManagerError.PERMISSIONDENIED)
                    or error.matches(NM.settings_error_quark(), NM.SettingsError.PERMISSIONDENIED)
                    or error.matches(Gio.dbus_error_quark(), Gio.DBusError.ACCESS_DENIED)):
                return "permission"
            if error.matches(NM.client_error_quark(), NM.ClientError.MANAGER_NOT_RUNNING):
                return "unavailable"
            if error.matches(NM.device_error_quark(), NM.DeviceError.NOTACTIVE):
                return "unavailable"
            if error.matches(Gio.io_error_quark(), Gio.IOErrorEnum.PERMISSION_DENIED):
                return "permission"
        return "connection"

    @staticmethod
    def reason_code(reason, device_reason):
        if reason in (NM.ActiveConnectionStateReason.NO_SECRETS, NM.ActiveConnectionStateReason.LOGIN_FAILED) or device_reason == NM.DeviceStateReason.NO_SECRETS:
            return "auth"
        if reason == NM.ActiveConnectionStateReason.IP_CONFIG_INVALID or device_reason in (
                NM.DeviceStateReason.IP_CONFIG_UNAVAILABLE, NM.DeviceStateReason.IP_CONFIG_EXPIRED,
                NM.DeviceStateReason.DHCP_START_FAILED, NM.DeviceStateReason.DHCP_ERROR, NM.DeviceStateReason.DHCP_FAILED):
            return "ip"
        if reason == NM.ActiveConnectionStateReason.CONNECT_TIMEOUT:
            return "timeout"
        if reason == NM.ActiveConnectionStateReason.DEVICE_REMOVED:
            return "unavailable"
        return "connection"

    def persist(self, op, done):
        remote = self.client.get_connection_by_uuid(op.uuid)
        if not remote:
            done(False)
            return
        if op.secret is None and not op.new:
            done(True)  # Existing NM/keyring credentials; nothing to overwrite.
            return
        security = remote.get_setting_wireless_security()
        if security and int(security.props.psk_flags) != int(NM.SettingSecretFlags.NONE):
            done(False)  # Preserve AGENT_OWNED and NOT_SAVED; no silent migration.
            return
        version = remote.get_version_id()
        if not version:
            done(False)  # Cannot safely merge on a daemon without version checks.
            return
        def update(secrets=None):
            if self.controller.op is not op or remote.get_version_id() != version:
                done(False)
                return
            settings = remote.to_dbus(NM.ConnectionSerializationFlags.NO_SECRETS)
            # Preserve typed variants, including settings and any other secrets.
            merged = {name: {key: values.lookup_value(key, None)
                            for key in values.keys()}
                      for name, values in ((key, settings.lookup_value(key, None)) for key in settings.keys())}
            if secrets:
                for name in secrets.keys():
                    values = secrets.lookup_value(name, None)
                    merged.setdefault(name, {}).update({key: values.lookup_value(key, None) for key in values.keys()})
            if op.secret is not None:
                merged.setdefault(SECURITY, {})["psk"] = GLib.Variant("s", op.secret)
            if op.new:
                merged["connection"]["autoconnect"] = GLib.Variant("b", True)
            def saved(connection, result, data):
                try:
                    connection.update2_finish(result)
                except Exception:
                    done(False)
                else:
                    done(True)
            remote.update2(GLib.Variant("a{sa{sv}}", merged), NM.SettingsUpdate2Flags.TO_DISK | NM.SettingsUpdate2Flags.NO_REAPPLY,
                           GLib.Variant("a{sv}", {"version-id": GLib.Variant("t", version)}), None, saved, None)
        if op.new:
            update()
        else:
            # GetSettings omits all secrets. Fetch only this owned profile's
            # secret-bearing settings before replacing the dictionary.
            names = [setting.get_name() for setting in remote.get_settings()
                     if any(int(prop.flags) & NM.SETTING_PARAM_SECRET for prop in setting.list_properties())]
            collected = {}
            def next_setting():
                if not names:
                    update(GLib.Variant("a{sa{sv}}", collected))
                    return
                name = names.pop()
                def got_secrets(connection, result, data):
                    try:
                        secrets = connection.get_secrets_finish(result)
                        for key in secrets.keys():
                            values = secrets.lookup_value(key, None)
                            collected[key] = {key: values.lookup_value(key, None) for key in values.keys()}
                        next_setting()
                    except Exception:
                        done(False)
                remote.get_secrets_async(name, None, got_secrets, None)
            next_setting()



def main():
    def emit(event):
        try:
            os.write(1, (json.dumps(event, separators=(",", ":")) + "\n").encode("utf-8"))
        except BrokenPipeError:
            pass  # Still run the EOF/late-callback cleanup when the reader dies.
    # GI's callback exception hook must not format exceptions/arguments containing a PSK.
    def callback_error(*_):
        try:
            emit(dict(event="unavailable"))
        except BrokenPipeError:
            pass
    sys.excepthook = callback_error
    loop = GLib.MainLoop()
    runtime = Runtime(emit)
    def command(message):
        if not runtime.ready:
            emit(dict(event="failed", operation=message.get("operation", ""), code="unavailable"))
            return
        runtime.controller.command(message)
    frames = Frames(command)
    os.set_blocking(0, False)
    closing = False
    def close():
        nonlocal closing
        if closing:
            return
        closing = True
        if runtime.controller.op:
            runtime.controller.cancel(runtime.controller.op)
        # Wait for a late activation result instead of guessing ownership by UUID.
        # The daemon's async request is normally much shorter than this bound.
        GLib.timeout_add_seconds(65, lambda: (loop.quit(), False)[1])
    def read_input(fd, condition):
        try:
            # Bounded work per dispatch, even for a malicious/broken writer.
            data = os.read(0, 4096)
            if not data:
                close()
                return False
            frames.feed(data)
        except BlockingIOError:
            pass
        except Exception:
            emit(dict(event="unavailable"))
            close()
            return False
        return True
    GLib.io_add_watch(0, GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR, read_input)
    GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, lambda: (close(), False)[1])
    def tick():
        if closing and runtime.controller.op is None:
            loop.quit()
            return False
        if not runtime.ready and time.monotonic() > runtime.startup_deadline:
            emit(dict(event="unavailable"))
            loop.quit()
            return False
        runtime.controller.tick()
        return True
    GLib.timeout_add(500, tick)
    loop.run()


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # No raw GLib exceptions, request bodies or tracebacks on either stream.
        try:
            print('{"event":"unavailable"}', flush=True)
        except BrokenPipeError:
            pass
