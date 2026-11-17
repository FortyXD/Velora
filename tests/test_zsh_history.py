"""Real interactive zsh, private HOME/history, pipes instead of terminal emulation.

Only the history block is copied into the temporary .zshrc. No desktop tools,
user startup files, user history, PTY, or shell plugins are needed. zsh -d skips
global startup files (except zsh's unavoidable system zshenv).
"""
import os
from pathlib import Path
import select
import shutil
import subprocess
import tempfile
import time
import unittest
import uuid

PROJECT = Path(__file__).resolve().parents[1]
ZSH = shutil.which('zsh')
CONFIG = PROJECT / 'home/.zshrc'
START = '# --- History '
END = '# --- End history '
OPTIONS = ('extendedhistory', 'sharehistory', 'histexpiredupsfirst',
           'histignoredups', 'histignorespace', 'histreduceblanks', 'histverify')


def history_block():
    text = CONFIG.read_text()
    start = text.index(START)
    end = text.index('\n', text.index(END, start))
    return text[start:end + 1]


class Shell:
    """Synchronize on stdout markers, not prompts, sleeps, or terminal bytes."""
    def __init__(self, home):
        self.errors = tempfile.TemporaryFile()
        self.process = subprocess.Popen(
            [ZSH, '-d', '-i'], cwd=home,
            env={'HOME': str(home), 'ZDOTDIR': str(home), 'PATH': '/usr/bin:/bin',
                 'TERM': 'dumb', 'LANG': 'C', 'LC_ALL': 'C'},
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self.errors)
        self.pending = b''
        self.exchange(' : ready')

    def stderr(self):
        self.errors.seek(0)
        return self.errors.read().decode(errors='replace')

    def exchange(self, command):
        marker = ('__velora_history_' + uuid.uuid4().hex + '__').encode()
        self.process.stdin.write(command.encode() + b'\n print -r -- ' + marker + b'\n')
        self.process.stdin.flush()
        deadline = time.monotonic() + 5
        while marker + b'\n' not in self.pending:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not select.select([self.process.stdout], [], [], max(0, remaining))[0]:
                raise AssertionError('zsh response timed out: ' + self.stderr())
            chunk = os.read(self.process.stdout.fileno(), 65536)
            if not chunk:
                raise AssertionError(f'zsh exited ({self.process.poll()}): {self.stderr()}')
            self.pending += chunk
        result, self.pending = self.pending.split(marker + b'\n', 1)
        return result.decode()

    def history(self):
        # Leading space excludes the inspection command itself.
        return self.exchange(' fc -ln 1')

    def close(self):
        try:
            if self.process.poll() is None:
                self.process.stdin.write(b' exit\n')
                self.process.stdin.flush()
            self.process.wait(timeout=5)
            if self.process.returncode != 0:
                raise AssertionError(f'zsh exit code {self.process.returncode}: {self.stderr()}')
        finally:
            if self.process.poll() is None:
                self.process.kill()
                self.process.wait(timeout=5)
            self.process.stdin.close()
            self.process.stdout.close()
            self.errors.close()


@unittest.skipUnless(ZSH, 'zsh is not installed; real-shell history tests require zsh')
class ZshHistoryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='velora-zsh-history-')
        self.addCleanup(self.temporary.cleanup)
        self.home = Path(self.temporary.name)
        # No inherited environment, system rc files, or non-history config.
        (self.home / '.zshrc').write_text(
            'unsetopt ZLE BEEP\nPS1=\nPS2=\nRPS1=\numask 077\n' + history_block())

    def shell(self):
        shell = Shell(self.home)
        self.addCleanup(lambda: shell.close() if not shell.errors.closed else None)
        return shell

    def test_settings(self):
        shell = self.shell()
        self.assertEqual(shell.exchange(' print -r -- "$HISTFILE|$HISTSIZE|$SAVEHIST"').strip(),
                         f'{self.home}/.zsh_history|100000|100000')
        for option in OPTIONS:
            with self.subTest(option=option):
                self.assertEqual(shell.exchange(f' print -r -- $options[{option}]').strip(), 'on')

    def test_persistence_across_two_processes_and_extended_format(self):
        first = self.shell()
        first.exchange(': velora_persist_first')
        first.close()
        second = self.shell()
        self.assertIn(': velora_persist_first', second.history())
        second.exchange(': velora_persist_second')
        second.close()
        saved = (self.home / '.zsh_history').read_text()
        for command in ('velora_persist_first', 'velora_persist_second'):
            self.assertRegex(saved, rf'(?m)^: [0-9]+:[0-9]+;: {command}$')

    def test_live_shells_share_without_exit_or_manual_fc_import(self):
        first, second = self.shell(), self.shell()
        first.exchange(': velora_live_first')
        # A normal command boundary triggers SHARE_HISTORY import.
        second.exchange(': velora_live_second')
        self.assertIsNone(first.process.poll())
        self.assertIsNone(second.process.poll())
        self.assertIn(': velora_live_first', second.history())
        first.exchange(': velora_live_boundary')
        self.assertIn(': velora_live_second', first.history())
        saved = (self.home / '.zsh_history').read_text()
        self.assertIn('velora_live_first', saved)
        self.assertIn('velora_live_second', saved)

    def test_privacy_duplicates_and_blank_reduction(self):
        shell = self.shell()
        # Harmless fake secret: leading space must keep it out of durable history.
        shell.exchange(' : velora_fake_secret_not_for_history')
        shell.exchange(': velora_duplicate')
        shell.exchange(': velora_duplicate')
        shell.exchange(':     velora_reduced_blanks')
        shell.exchange(': velora_after_private_command')
        current = shell.history()
        self.assertNotIn('velora_fake_secret_not_for_history', current)
        self.assertEqual(current.count(': velora_duplicate'), 1)
        self.assertIn(': velora_reduced_blanks', current)
        self.assertNotIn(':     velora_reduced_blanks', current)
        self.assertNotIn('velora_fake_secret_not_for_history',
                         (self.home / '.zsh_history').read_text())
        shell.close()
        saved = (self.home / '.zsh_history').read_text()
        self.assertNotIn('velora_fake_secret_not_for_history', saved)
        self.assertEqual(saved.count(': velora_duplicate'), 1)
        self.assertRegex(saved, r';: velora_reduced_blanks\n')


if __name__ == '__main__':
    unittest.main()
