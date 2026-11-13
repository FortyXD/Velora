import json
import os
from pathlib import Path
import subprocess
from unittest.mock import patch

from test_velora import IsolatedTest, velora

gui = velora.update_gui


class GuiUpdateTests(IsolatedTest):
    def test_worker_records_progress_and_success_without_a_terminal(self):
        binary = self.base / 'fake-velora'
        binary.write_text('#!/bin/sh\nprintf "::velora-phase installing\\nInstalled\\n"\n')
        binary.chmod(0o700)
        with patch.dict(os.environ, XDG_RUNTIME_DIR=str(self.base)):
            self.assertEqual(gui.worker(binary), 0)
        status = gui.status()
        self.assertEqual(status['status'], 'succeeded')
        self.assertEqual(status['phase'], 'installing')
        self.assertEqual(status['tail'], ['Installed'])
        self.assertEqual(Path(status['log']).stat().st_mode & 0o777, 0o600)
        self.assertFalse(list(self.base.glob('velora-update-*')))

    def test_failed_worker_can_be_retried_and_cleans_helpers(self):
        binary = self.base / 'fake-velora'
        binary.write_text('#!/bin/sh\nprintf "authorization cancelled\\n"\nexit 1\n')
        binary.chmod(0o700)
        with patch.dict(os.environ, XDG_RUNTIME_DIR=str(self.base)):
            self.assertEqual(gui.worker(binary), 1)
            self.assertEqual(gui.status()['status'], 'failed')
            binary.write_text('#!/bin/sh\nexit 0\n')
            self.assertEqual(gui.worker(binary), 0)
        self.assertEqual(gui.status()['status'], 'succeeded')
        self.assertFalse(list(self.base.glob('velora-update-*')))

    def test_interrupted_service_is_reported_instead_of_spinning_forever(self):
        gui.write_status({'status': 'running'})
        with patch.object(gui.time, 'time', return_value=10**12), patch.object(gui, 'active', return_value=False):
            self.assertEqual(gui.status()['status'], 'failed')

    def test_running_service_is_not_started_twice(self):
        with patch.dict(os.environ, XDG_RUNTIME_DIR=str(self.base)), patch.object(gui, 'active', return_value=True), \
                patch.object(gui.subprocess, 'run') as run:
            gui.start(self.base / 'velora')
        run.assert_not_called()

    def test_gui_package_commands_do_not_wait_for_terminal_input(self):
        result = subprocess.CompletedProcess([], 0, stdout='', stderr='')
        with patch.dict(os.environ, VELORA_GUI_UPDATE='1'), patch.object(velora.subprocess, 'run', return_value=result) as run:
            for command in (['sudo', 'pacman', '-Syu', '--needed', '--', 'dolphin-plugins'],
                            ['makepkg', '-si', '--needed'], ['yay', '-S', '--needed', '--', 'example']):
                velora.run(command)
                self.assertIn('--noconfirm', run.call_args.args[0])
            self.assertIn('--sudoflags=-A', run.call_args.args[0])

    def test_gui_reconciles_dependencies_but_preserves_component_choices(self):
        velora.write_json(velora.state_dir() / 'installation.json',
                          {'skip_packages': True, 'skip_aur': True, 'without': ['toolbox'], 'login_theme': 'velora'})
        with patch.dict(os.environ, VELORA_GUI_UPDATE='1'), patch.object(velora, 'run') as run:
            velora.install_updated_tree()
        command = run.call_args.args[0]
        self.assertNotIn('--skip-packages', command)
        for option in ('--yes', '--no-reload', '--skip-aur', 'toolbox', '--login-theme', 'velora'):
            self.assertIn(option, command)
