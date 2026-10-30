"""Offline state machine and real libnm vfunc ABI tests; never activate a device."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch

# Ubuntu CI does not provide libnm's GI typelib. Exercise the real adapter on
# systems that have it; the snapshot and UI tests still run without libnm.
try:
    import gi
    gi.require_version('NM', '1.0')
    gi.require_version('GLibUnix', '2.0')
except (ImportError, ValueError):
    raise unittest.SkipTest('libnm/GObject introspection unavailable')

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'dots/.config/quickshell/ii/scripts/network/wifi_agent.py'
spec = importlib.util.spec_from_file_location('wifi_agent', SCRIPT)
wifi = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wifi)
NM, GLib, Gio = wifi.NM, wifi.GLib, wifi.Gio
SENTINEL = ' private-юникод-credential '


def profile(flags=0):
    connection = NM.SimpleConnection.new()
    setting = NM.SettingConnection.new()
    setting.props.id = 'offline'
    setting.props.uuid = '728c12c7-40bf-4024-a9ce-a4f40b825354'
    setting.props.type = '802-11-wireless'
    connection.add_setting(setting)
    wireless = NM.SettingWireless.new()
    wireless.props.ssid = GLib.Bytes.new(b'offline')
    connection.add_setting(wireless)
    security = NM.SettingWirelessSecurity.new()
    security.props.key_mgmt = 'wpa-psk'
    security.props.psk_flags = flags
    connection.add_setting(security)
    connection.set_path('/org/freedesktop/NetworkManager/Settings/99999')
    return connection


class FakeNM:
    def __init__(self):
        self.locked = False
        self.replies = []
        self.deactivated = []
        self.saved = []
        self.saved_ok = True

    def acquire(self):
        if self.locked:
            return False
        self.locked = True
        return True

    def prepare(self, op, message):
        op.uuid, op.path, op.mode = 'owned', '/owned', 'wpa-psk'
        op.previous = SimpleNamespace(state='activated')

    def activate(self, op, done):
        self.started = done

    def watch(self, op, done):
        self.changed = done
        if op.active.state == 'activated':
            done('activated')

    def cancel_activation(self, op):
        # Cancel the local request, never tear down an established connection.
        self.cancelled = True

    def persist(self, op, done):
        self.saved.append(op.secret)
        done(self.saved_ok)

    def release(self, op):
        self.locked = False

    error_code = staticmethod(lambda error: getattr(error, 'code', 'connection'))


class AgentStateTests(unittest.TestCase):
    def setUp(self):
        self.nm = FakeNM()
        self.events = []
        self.c = wifi.Controller(self.nm, self.events.append)
        self.connect()

    def connect(self, token='one'):
        self.c.command(dict(command='connect', operation=token, ssid='offline'))
        return self.c.op

    def request(self, flags=1, path='/owned', uuid='owned'):
        results = []
        self.c.request_secret(uuid, path, 'wpa-psk', flags, lambda secret, error: results.append((secret, error)))
        return results

    def submit(self, password=SENTINEL, request=None, token='one'):
        self.c.command(dict(command='submit', operation=token, request=request or str(self.c.op.request), password=password))

    def test_request_new_never_reuses_rejected_password_and_none_flags_never_prompt(self):
        replies = self.request()
        self.submit()
        self.assertEqual(replies, [(SENTINEL, None)])
        cached = self.request(0)
        self.assertEqual(cached, [(SENTINEL, None)])
        retry = self.request(2)
        self.assertIsNone(self.c.op.secret)
        self.assertEqual(self.events[-1]['code'], 'retry')
        self.assertEqual(retry, [])
        self.submit('replacement-password')
        self.assertEqual(retry, [('replacement-password', None)])
        self.assertNotIn(SENTINEL, json.dumps(self.events))

    def test_flags_none_user_requested_and_unrelated_requests(self):
        for flags in (0, 4):
            self.assertEqual(self.request(flags), [(None, 'NOSECRETS')])
        self.assertEqual(self.request(uuid='unrelated'), [(None, 'NOSECRETS')])
        self.assertEqual(self.request(path='/unrelated'), [(None, 'NOSECRETS')])
        self.assertEqual(len(self.events), 1)

    def test_new_path_claimed_only_by_owned_uuid(self):
        self.c.op.path = None
        self.assertEqual(self.request(path='/unrelated', uuid='other'), [(None, 'NOSECRETS')])
        self.request(path='/new')
        self.assertEqual(self.c.op.path, '/new')
        self.assertEqual(self.request(path='/old'), [(None, 'NOSECRETS')])

    def test_stale_request_operation_and_duplicate_requests(self):
        replies = self.request()
        self.assertEqual(self.request(), [(None, 'NOSECRETS')])
        self.submit(request='99')
        self.submit(token='old')
        self.assertEqual(replies, [])
        self.c.cancel_request('/owned')
        self.assertEqual(replies, [(None, 'AGENTCANCELED')])
        second = self.request(2)
        self.submit(request='1')
        self.assertEqual(second, [])
        self.submit()
        self.assertEqual(len(second), 1)

    def test_saved_success_inspects_immediate_state_and_clears(self):
        op = self.c.op
        self.nm.started(SimpleNamespace(state='activated'))
        self.assertEqual(self.events[-1]['event'], 'connected')
        self.assertEqual(self.nm.saved, [None])
        self.assertIsNone(self.c.op)
        self.assertIsNone(op.secret)
        self.nm.started(SimpleNamespace(state='activating'))
        self.assertEqual(self.nm.deactivated, [])

    def test_cancel_before_late_activation_callback(self):
        op = self.c.op
        pending = self.request()
        self.c.command(dict(command='cancel', operation='one'))
        self.assertEqual(pending, [(None, 'USERCANCELED')])
        self.assertTrue(self.nm.locked)
        self.connect('two')
        self.assertEqual(self.events[-1]['code'], 'busy')
        active = SimpleNamespace(state='activating')
        self.nm.started(active)
        self.assertEqual(self.nm.deactivated, [])
        self.assertTrue(self.nm.cancelled)
        self.assertIsNone(self.c.op)
        self.c.state(op, 'activated')
        self.assertEqual(self.nm.saved, [])

    def test_cancel_after_callback_and_success_race(self):
        active = SimpleNamespace(state='activating')
        self.nm.started(active)
        self.c.command(dict(command='cancel', operation='one'))
        self.assertEqual(self.nm.deactivated, [])
        self.connect('two')
        active = SimpleNamespace(state='activated')
        self.c.command(dict(command='cancel', operation='two'))
        self.nm.started(active)
        self.assertEqual(self.nm.deactivated, [])
        self.assertEqual(active.state, 'activated')
        self.assertEqual(self.nm.saved, [])

    def test_timeout_paused_while_waiting_and_tombstone_retains_lock(self):
        self.request()
        self.c.tick(10**20)
        self.assertIsNotNone(self.c.op)
        self.submit()
        self.c.tick(10**20)
        self.assertEqual(self.events[-1]['code'], 'timeout')
        self.assertTrue(self.nm.locked)
        self.nm.started(None, wifi.BackendError('unavailable'))
        self.assertFalse(self.nm.locked)

    def test_typed_failure_and_save_denied_not_failed(self):
        self.nm.started(SimpleNamespace(state='activating'))
        self.nm.changed('deactivated', 'ip')
        self.assertEqual(self.events[-1]['code'], 'ip')
        self.connect('two')
        self.nm.saved_ok = False
        self.nm.started(SimpleNamespace(state='activated'))
        self.assertEqual(self.events[-1], dict(event='connected', operation='two', code='not-saved'))
        self.assertEqual(self.nm.deactivated, [])

    def test_persistence_timeout_and_late_result(self):
        callbacks = []
        self.nm.persist = lambda op, done: callbacks.append(done)
        self.nm.started(SimpleNamespace(state='activated'))
        self.c.tick(10**20)
        self.assertEqual(self.events[-1]['code'], 'not-saved')
        callbacks[0](True)
        self.assertEqual(self.events[-1]['code'], 'not-saved')


class NativeAdapterTests(unittest.TestCase):
    def test_delayed_real_gi_get_secret_vfunc_and_error_callback_abi(self):
        events = []
        transport = FakeNM()
        c = wifi.Controller(transport, events.append)
        c.command(dict(command='connect', operation='one', ssid='offline'))
        connection = profile()
        c.op.uuid, c.op.path = connection.get_uuid(), connection.get_path()
        agent = wifi.Agent(identifier='org.velora.OfflineAbiTest', auto_register=False)
        agent.controller = c
        results = []
        def complete(agent, connection, secrets, error, data):
            results.append((secrets.unpack() if secrets else None, error))
        agent.get_secrets(connection, wifi.SECURITY, [], NM.SecretAgentGetSecretsFlags.ALLOW_INTERACTION, complete, None)
        self.assertEqual(results, [])
        c.command(dict(command='submit', operation='one', request='1', password=SENTINEL))
        self.assertEqual(results[0][0][wifi.SECURITY]['psk'], SENTINEL)
        self.assertIsNone(results[0][1])
        c.op.uuid = 'other'
        agent.get_secrets(connection, wifi.SECURITY, [], NM.SecretAgentGetSecretsFlags.NONE, complete, None)
        self.assertTrue(results[-1][1].matches(NM.secret_agent_error_quark(), NM.SecretAgentError.NOSECRETS))
        for method in (agent.save_secrets, agent.delete_secrets):
            errors = []
            method(connection, lambda agent, conn, error, data: errors.append(error), None)
            self.assertTrue(errors[0].matches(NM.secret_agent_error_quark(), NM.SecretAgentError.NOSECRETS))
        self.assertNotIn(SENTINEL, json.dumps(events))

    def test_typed_auth_ip_permission_and_other_errors(self):
        self.assertEqual(wifi.Runtime.reason_code(NM.ActiveConnectionStateReason.NO_SECRETS, NM.DeviceStateReason.NONE), 'auth')
        self.assertEqual(wifi.Runtime.reason_code(NM.ActiveConnectionStateReason.UNKNOWN, NM.DeviceStateReason.DHCP_FAILED), 'ip')
        error = GLib.Error.new_literal(NM.manager_error_quark(), 'opaque', NM.ManagerError.PERMISSIONDENIED)
        self.assertEqual(wifi.Runtime.error_code(error), 'permission')
        self.assertEqual(wifi.Runtime.error_code(Exception(SENTINEL)), 'connection')

    def test_cancel_only_local_request_never_deactivates_connection(self):
        runtime = wifi.Runtime.__new__(wifi.Runtime)
        runtime.client = Mock()
        cancellable = Gio.Cancellable.new()
        op = SimpleNamespace(active=Mock(), cancellable=cancellable)
        runtime.cancel_activation(op)
        self.assertTrue(cancellable.is_cancelled())
        runtime.client.deactivate_connection_async.assert_not_called()

    def test_persist_preserves_uuid_settings_other_secrets_and_flags(self):
        for flags, expected in ((0, True), (1, False), (2, False)):
            with self.subTest(flags=flags):
                connection = profile(flags)
                connection.get_setting_connection().props.zone = 'original-zone'
                secrets = GLib.Variant('a{sa{sv}}', {wifi.SECURITY: {'psk': GLib.Variant('s', 'old-secret'), 'wep-key0': GLib.Variant('s', 'untouched-secret')}})
                remote = Mock()
                remote.get_setting_wireless_security.return_value = connection.get_setting_wireless_security()
                remote.get_version_id.return_value = 42
                remote.to_dbus.return_value = connection.to_dbus(NM.ConnectionSerializationFlags.NO_SECRETS)
                remote.get_settings.return_value = connection.get_settings()
                remote.get_secrets_finish.return_value = secrets
                remote.get_secrets_async.side_effect = lambda name, cancel, cb, data: cb(remote, None, data)
                remote.update2.side_effect = lambda settings, flags, args, cancel, cb, data: cb(remote, None, data)
                runtime = wifi.Runtime.__new__(wifi.Runtime)
                runtime.client = Mock()
                runtime.client.get_connection_by_uuid.return_value = remote
                op = SimpleNamespace(uuid=connection.get_uuid(), secret=SENTINEL, new=False)
                runtime.controller = SimpleNamespace(op=op)
                results = []
                runtime.persist(op, results.append)
                self.assertEqual(results, [expected])
                if expected:
                    settings, update_flags, args, *_ = remote.update2.call_args.args
                    values = settings.unpack()
                    self.assertEqual(values['connection']['uuid'], connection.get_uuid())
                    self.assertEqual(values['connection']['zone'], 'original-zone')
                    self.assertEqual(values[wifi.SECURITY]['psk'], SENTINEL)
                    self.assertEqual(values[wifi.SECURITY]['wep-key0'], 'untouched-secret')
                    self.assertEqual(args.unpack()['version-id'], 42)
                    self.assertTrue(update_flags & NM.SettingsUpdate2Flags.TO_DISK)
                else:
                    remote.update2.assert_not_called()

    def test_save_failure_and_concurrent_modification_never_report_saved(self):
        for kind in ('denied-read', 'denied-write', 'conflict'):
            with self.subTest(kind=kind):
                connection = profile()
                remote = Mock()
                remote.get_setting_wireless_security.return_value = connection.get_setting_wireless_security()
                remote.get_version_id.side_effect = [42, 43] if kind == 'conflict' else None
                if kind != 'conflict':
                    remote.get_version_id.return_value = 42
                remote.get_settings.return_value = connection.get_settings()
                remote.to_dbus.return_value = connection.to_dbus(NM.ConnectionSerializationFlags.NO_SECRETS)
                remote.get_secrets_async.side_effect = lambda name, cancel, cb, data: cb(remote, None, data)
                remote.get_secrets_finish.return_value = GLib.Variant('a{sa{sv}}', {})
                if kind == 'denied-read':
                    remote.get_secrets_finish.side_effect = Exception('denied')
                remote.update2.side_effect = lambda settings, flags, args, cancel, cb, data: cb(remote, None, data)
                remote.update2_finish.side_effect = Exception('denied')
                runtime = wifi.Runtime.__new__(wifi.Runtime)
                runtime.client = Mock()
                runtime.client.get_connection_by_uuid.return_value = remote
                op = SimpleNamespace(uuid=connection.get_uuid(), secret=SENTINEL, new=False)
                runtime.controller = SimpleNamespace(op=op)
                results = []
                runtime.persist(op, results.append)
                self.assertEqual(results, [False])
                if kind != 'denied-write':
                    remote.update2.assert_not_called()

    def test_prepare_supports_personal_hidden_and_refuses_enterprise_wep(self):
        flags_type = getattr(NM, '80211ApSecurityFlags')
        class Device:
            def get_managed(self): return True
            def connection_valid(self, connection): return True
            def get_access_points(self): return [ap]
            def get_active_connection(self): return None
        device = Device()
        ap = SimpleNamespace(get_ssid=lambda: GLib.Bytes.new(b'offline'), get_bssid=lambda: 'aa',
                             get_path=lambda: '/ap', get_flags=lambda: 1,
                             connection_valid=lambda connection: True)
        runtime = wifi.Runtime.__new__(wifi.Runtime)
        runtime.client = Mock()
        runtime.client.get_devices.return_value = [device]
        for mode, flags in (('wpa-psk', flags_type.KEY_MGMT_PSK), ('sae', flags_type.KEY_MGMT_SAE),
                            ('unsupported', flags_type.KEY_MGMT_802_1X), ('unsupported', 0)):
            ap.get_wpa_flags = lambda: 0
            ap.get_rsn_flags = lambda: flags
            op = wifi.Operation('one')
            with patch.object(wifi.NM, 'DeviceWifi', Device):
                if mode == 'unsupported':
                    with self.assertRaises(wifi.BackendError) as error:
                        runtime.prepare(op, dict(ssid='offline', bssid='aa'))
                    self.assertEqual(error.exception.code, 'unsupported')
                else:
                    runtime.prepare(op, dict(ssid='offline', bssid='aa'))
                    self.assertEqual(op.mode, mode)
                    self.assertIsNone(op.profile.get_setting_wireless_security().get_psk())
                    self.assertFalse(op.profile.get_setting_connection().props.autoconnect)
        for mode in ('open', 'wpa-psk', 'sae', 'wpa-eap', 'none'):
            op = wifi.Operation('hidden')
            with patch.object(wifi.NM, 'DeviceWifi', Device):
                if mode in ('wpa-eap', 'none'):
                    with self.assertRaises(wifi.BackendError):
                        runtime.prepare(op, dict(ssid='hidden', hidden=True, security=mode))
                else:
                    runtime.prepare(op, dict(ssid='hidden', hidden=True, security=mode))
                    self.assertTrue(op.profile.get_setting_wireless().props.hidden)
                    self.assertEqual(op.mode, mode)

    def test_existing_prepare_keeps_original_settings_even_with_zero_timestamp(self):
        original = profile()
        original.get_setting_connection().props.zone = 'do-not-change'
        original.get_setting_connection().add_permission('user', 'offline-user', None)
        before = original.to_dbus(NM.ConnectionSerializationFlags.ALL).unpack()
        class Device:
            def get_managed(self): return True
            def connection_valid(self, connection): return True
            def get_access_points(self): return []
            def get_active_connection(self): return None
        runtime = wifi.Runtime.__new__(wifi.Runtime)
        runtime.client = Mock()
        runtime.client.get_connection_by_uuid.return_value = original
        runtime.client.get_devices.return_value = [Device()]
        op = wifi.Operation('one')
        with patch.object(wifi.NM, 'DeviceWifi', Device):
            runtime.prepare(op, dict(ssid='offline', uuid=original.get_uuid(), hidden=True))
        self.assertEqual(op.uuid, original.get_uuid())
        self.assertEqual(original.to_dbus(NM.ConnectionSerializationFlags.ALL).unpack(), before)
        self.assertFalse(op.new)

    def test_new_activation_is_memory_only_not_bound_to_client(self):
        runtime = wifi.Runtime.__new__(wifi.Runtime)
        runtime.client = Mock()
        op = SimpleNamespace(new=True, profile=profile(), device=object(), specific='/ap')
        runtime.activate(op, Mock())
        args = runtime.client.add_and_activate_connection2.call_args.args
        self.assertEqual(args[3].unpack(), {'persist': 'memory'})
        self.assertIsInstance(args[4], Gio.Cancellable)

    def test_new_success_persists_psk_with_nm_ownership_only_after_success(self):
        connection = profile()
        connection.get_setting_connection().props.autoconnect = False
        remote = Mock()
        remote.get_setting_wireless_security.return_value = connection.get_setting_wireless_security()
        remote.get_version_id.return_value = 42
        remote.to_dbus.return_value = connection.to_dbus(NM.ConnectionSerializationFlags.NO_SECRETS)
        remote.update2.side_effect = lambda settings, flags, args, cancel, cb, data: cb(remote, None, data)
        runtime = wifi.Runtime.__new__(wifi.Runtime)
        runtime.client = Mock()
        runtime.client.get_connection_by_uuid.return_value = remote
        op = SimpleNamespace(uuid=connection.get_uuid(), secret=SENTINEL, new=True)
        runtime.controller = SimpleNamespace(op=op)
        results = []
        runtime.persist(op, results.append)
        self.assertEqual(results, [True])
        settings = remote.update2.call_args.args[0].unpack()
        self.assertEqual(settings[wifi.SECURITY]['psk'], SENTINEL)
        self.assertEqual(settings[wifi.SECURITY].get('psk-flags', 0), 0)
        self.assertTrue(settings['connection']['autoconnect'])
        self.assertFalse(connection.get_setting_connection().props.autoconnect)
        remote.get_secrets_async.assert_not_called()

    def test_external_agent_ordinary_success_does_not_claim_save_failure(self):
        runtime = wifi.Runtime.__new__(wifi.Runtime)
        remote = Mock()
        runtime.client = Mock()
        runtime.client.get_connection_by_uuid.return_value = remote
        op = SimpleNamespace(uuid='owned', new=False, secret=None)
        result = []
        runtime.persist(op, result.append)
        self.assertEqual(result, [True])
        remote.get_secrets_async.assert_not_called()
        remote.update2.assert_not_called()

    def test_lock_prevents_competing_ui_operations_and_can_be_released(self):
        a = wifi.Runtime.__new__(wifi.Runtime)
        b = wifi.Runtime.__new__(wifi.Runtime)
        for runtime in (a, b):
            runtime.ready = True
            runtime.agent = SimpleNamespace(get_registered=lambda: True)
            runtime.lock = None
        try:
            self.assertTrue(a.acquire())
            self.assertFalse(b.acquire())
            a.release(SimpleNamespace())
            self.assertTrue(b.acquire())
        finally:
            a.release(SimpleNamespace())
            b.release(SimpleNamespace())

    def test_validation_whitespace_unicode_raw_psk_and_sae(self):
        self.assertTrue(wifi.valid_password('        ', 'wpa-psk'))
        self.assertTrue(wifi.valid_password('я' * 31, 'wpa-psk'))
        self.assertFalse(wifi.valid_password('я' * 32, 'wpa-psk'))
        self.assertTrue(wifi.valid_password('A' * 64, 'wpa-psk'))
        self.assertFalse(wifi.valid_password('g' * 64, 'wpa-psk'))
        self.assertTrue(wifi.valid_password('я', 'sae'))
        self.assertFalse(wifi.valid_password('A' * 64, 'sae'))
        self.assertFalse(wifi.valid_password('a\x00' * 10, 'wpa-psk'))

    def test_broken_stdout_still_exits_on_eof_without_traceback(self):
        process = subprocess.Popen([sys.executable, str(ROOT / 'tests/fixtures/wifi_core_peer.py')],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        process.stdout.close()
        process.stdin.write(json.dumps(dict(command='connect', operation='one', ssid='late')) + '\n')
        process.stdin.close()
        try:
            self.assertEqual(process.wait(timeout=7), 0)
            self.assertEqual(process.stderr.read(), '')
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            process.stderr.close()

    def test_real_glib_eof_cleans_late_activation_but_never_healthy_connection(self):
        for ssid, local_cancels in (('late', 1), ('healthy', 0)):
            with self.subTest(ssid=ssid):
                result = subprocess.run([sys.executable, str(ROOT / 'tests/fixtures/wifi_core_peer.py')],
                    input=json.dumps(dict(command='connect', operation='one', ssid=ssid)) + '\n',
                    text=True, capture_output=True, timeout=7)
                self.assertEqual(result.returncode, 0, result.stderr)
                events = [json.loads(line)['event'] for line in result.stdout.splitlines()]
                if local_cancels:
                    self.assertGreaterEqual(events.count('test-cancelled-local-request'), 1)
                else:
                    self.assertNotIn('test-cancelled-local-request', events)
                self.assertNotIn('test-deactivated-owned', events)
                self.assertEqual(events.count('test-released'), 1)
                self.assertIn('connected' if ssid == 'healthy' else 'cancelled', events)
                self.assertEqual(result.stderr, '')

    def test_jsonl_partial_unicode_malformed_bounded_and_sentinel_not_echoed(self):
        output = []
        frames = wifi.Frames(output.append)
        wire = (json.dumps({'password': SENTINEL}, ensure_ascii=False) + '\n').encode()
        for char in wire:
            frames.feed(bytes([char]))
        self.assertEqual(output, [{'password': SENTINEL}])
        for malformed in (b'[]\n', b'{\n', b'\xff\n', b'x' * (wifi.MAX_FRAME + 1)):
            with self.assertRaises((ValueError, UnicodeError)):
                wifi.Frames(output.append).feed(malformed)
        # Production GLib input loop, with a fake transport: malformed input
        # cannot echo itself or emit a traceback, with no system bus access.
        result = subprocess.run([sys.executable, str(ROOT / 'tests/fixtures/wifi_core_peer.py')], input=SENTINEL + '\n', text=True,
                                capture_output=True, timeout=8)
        self.assertNotIn(SENTINEL, result.stdout + result.stderr)
        self.assertNotIn('Traceback', result.stdout + result.stderr)
        self.assertNotIn(SENTINEL, ' '.join(result.args))


if __name__ == '__main__':
    unittest.main()
