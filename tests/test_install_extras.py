"""Installer outcomes without contacting sudo or a package manager."""
import contextlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'dots/.config/quickshell/ii/scripts/maintenance/install_extras.py'
spec = importlib.util.spec_from_file_location('install_extras', SCRIPT)
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class ExtrasInstallerTests(unittest.TestCase):
    def invoke(self, arguments, verdict='ok', run_result=0):
        with tempfile.TemporaryDirectory(prefix='velora-extra-test-') as directory:
            secret_folder = Path(directory) / 'askpass'
            secret_folder.mkdir()
            output = io.StringIO()
            with patch.object(installer.sys, 'argv', [str(SCRIPT), *arguments]), \
                    patch.object(installer.sys, 'stdin', io.StringIO('dummy-secret\n')), \
                    patch.object(installer, 'check_password', return_value=verdict), \
                    patch.object(installer, 'askpass', return_value=(secret_folder, secret_folder / 'helper')), \
                    patch.object(installer, 'run', return_value=run_result) as run, \
                    patch.object(installer.signal, 'signal'), contextlib.redirect_stdout(output):
                result = installer.main()
            return result, run.call_args_list, output.getvalue(), secret_folder.exists()

    def test_authentication_failure_never_runs_package_tools(self):
        for verdict, code in [('wrong', 3), ('denied', 5)]:
            result, calls, output, _ = self.invoke(['--repo', 'sample'], verdict=verdict)
            self.assertEqual(result, code)
            self.assertFalse(calls)
            self.assertNotIn('dummy-secret', output)

    def test_success_installs_and_records_selection_then_cleans_secret(self):
        result, calls, output, secret_exists = self.invoke(['--repo', 'sample', '--components', 'toolbox'])
        self.assertEqual(result, 0)
        self.assertEqual(calls[0].args[0], ['sudo', '-A', 'pacman', '-S', '--needed', '--noconfirm', '--', 'sample'])
        self.assertEqual(calls[1].args[0][-4:], ['deps', '--add', 'toolbox', '--skip-packages'])
        self.assertIn('::phase record', output)
        self.assertFalse(secret_exists)

    def test_record_failure_is_reported_and_cleans_secret(self):
        result, _, _, secret_exists = self.invoke(['--components', 'toolbox'], run_result=1)
        self.assertEqual(result, 1)
        self.assertFalse(secret_exists)
