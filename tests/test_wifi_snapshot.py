"""Read-only discovery separates identity/history from secret availability."""
import importlib.util
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'dots/.config/quickshell/ii/scripts/network/wifi_snapshot.py'
spec = importlib.util.spec_from_file_location('wifi_snapshot', SCRIPT)
snapshot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(snapshot)


def result(stdout='', stderr='', returncode=0):
    return SimpleNamespace(stdout=stdout, stderr=stderr, returncode=returncode)


class WifiSnapshotTests(unittest.TestCase):
    def test_zero_timestamp_does_not_claim_password_state_and_names_preserve_spaces(self):
        calls = []
        def nmcli(*args):
            calls.append(args)
            if args[-1] == 'show':
                return result('uuid-personal:wifi:0\nuuid-enterprise:wifi:99\n')
            return result(' spaced name \n' + ('wpa-psk' if args[-1] == 'uuid-personal' else 'wpa-eap') + '\n')
        with patch.object(snapshot, 'nmcli', nmcli):
            profiles = snapshot.saved_profiles()
        self.assertEqual(profiles[(' spaced name ', 'personal')], dict(uuid='uuid-personal', joinedBefore=False))
        self.assertEqual(profiles[(' spaced name ', 'advanced')], dict(uuid='uuid-enterprise', joinedBefore=True))
        self.assertTrue(all('--show-secrets' not in call for call in calls))

    def test_same_name_different_security_keeps_distinct_identities(self):
        profiles = {('same', 'personal'): dict(uuid='personal', joinedBefore=True),
                    ('same', 'advanced'): dict(uuid='enterprise', joinedBefore=False)}
        with patch.object(snapshot, 'nmcli', return_value=result(':70:2412:same:aa:WPA2\n:80:2412:same:bb:WPA2 802.1X\n:90:2412:same:cc:WPA2\n')):
            networks, error = snapshot.visible_networks(profiles)
        self.assertEqual(error, '')
        self.assertEqual(len(networks), 2)
        self.assertEqual({n['savedUuid'] for n in networks}, {'personal', 'enterprise'})
        self.assertEqual({n['key'] for n in networks}, {'same\npersonal', 'same\nadvanced'})
        self.assertNotIn('hasCredentials', str(networks))
        self.assertNotIn('neverUsed', str(networks))
        self.assertEqual(snapshot.security_kind('WEP'), 'advanced')
        self.assertEqual(snapshot.security_kind('OWE'), 'advanced')
        self.assertEqual(snapshot.security_kind('--'), 'open')

    def test_errors_never_forward_raw_nmcli_stderr(self):
        with patch.object(snapshot, 'nmcli', return_value=result(stderr='credential-sentinel-private', returncode=1)):
            networks, error = snapshot.visible_networks({})
        self.assertEqual(networks, [])
        self.assertEqual(error, 'NetworkManager unavailable')


if __name__ == '__main__':
    unittest.main()
