"""Click-to-open links in tmux, verified with real mouse events.

The test starts a private tmux server on its own socket inside a temporary
HOME, feeds it synthetic SGR mouse events through a pseudo terminal and records
openers with a fake `xdg-open`. Nothing here touches the developer's desktop:
no input is injected into an existing client and no real browser is launched.
"""
import fcntl
import json
import os
from pathlib import Path
import pty
import re
import select
import shutil
import struct
import subprocess
import tempfile
import termios
import time
import unittest

PROJECT = Path(__file__).resolve().parents[1]
CONFIG = PROJECT / 'dots/.config/tmux'
# tmux dispatches mouse keys to the copy-mode table only from 3.5; 3.4 handles
# copy-mode mouse events internally, so the bindings there are inert.
COPY_MODE_MOUSE = (3, 5)


def version(tmux):
    match = re.search(r'(\d+)\.(\d+)', subprocess.check_output([tmux, '-V'], text=True))
    return (int(match.group(1)), int(match.group(2))) if match else (0, 0)


class TmuxMouseLinksTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('tmux'), 'tmux is not installed')
    def test_normal_and_copy_mode_clicks_open_one_validated_url(self):
        tmux = shutil.which('tmux')
        fixture = ('import sys,time\n'
                   'sys.stdout.write("\\x1b[2J\\x1b[H\\x1b]8;;https://example.org/pr/12\\x1b\\\\Open PR\\x1b]8;;\\x1b\\\\\\r\\n'
                   'https://example.org/plain\\r\\nordinary text\\r\\n")\n'
                   'sys.stdout.flush();time.sleep(60)\n')
        with tempfile.TemporaryDirectory(prefix='velora-tmux-links-') as name:
            root = Path(name)
            scripts = root / '.config/tmux/scripts'
            scripts.mkdir(parents=True)
            shutil.copy2(CONFIG / 'scripts/open-link.py', scripts / 'open-link.py')
            (root / 'bin').mkdir()
            (root / 'bin/xdg-open').write_text(
                '#!/usr/bin/python3\nimport sys,json,os\n'
                'with open(os.environ["CLICK_LOG"], "a") as stream:\n'
                '    stream.write(json.dumps(sys.argv[1:]) + "\\n")\n')
            (root / 'bin/xdg-open').chmod(0o755)
            (root / 'fixture.py').write_text(fixture)
            (root / 'tmux.conf').write_text('set -g mouse on\nset -g status off\n'
                                            + (CONFIG / 'mouse-links.conf').read_text())
            log = root / 'clicked.jsonl'
            env = {**os.environ, 'HOME': str(root), 'TERM': 'xterm-256color',
                   'PATH': str(root / 'bin') + ':/usr/bin:/bin', 'CLICK_LOG': str(log)}
            env.pop('XDG_CONFIG_HOME', None)
            env.pop('TMUX', None)
            socket = str(root / 'socket')

            def command(*args):
                return subprocess.check_output([tmux, '-S', socket, *args], env=env,
                                               text=True, stderr=subprocess.STDOUT)

            command('-f', str(root / 'tmux.conf'), 'new-session', '-d', '-s', 'test',
                    '-x', '80', '-y', '24', 'python3 ' + str(root / 'fixture.py'))
            master, slave = pty.openpty()
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
            attach = subprocess.Popen([tmux, '-S', socket, 'attach-session', '-t', 'test'],
                                      stdin=slave, stdout=slave, stderr=slave, env=env)
            os.close(slave)
            try:
                def drain(seconds=0.4):
                    end = time.monotonic() + seconds
                    while time.monotonic() < end:
                        ready, _, _ = select.select([master], [], [], 0.05)
                        if ready:
                            os.read(master, 65536)

                def opened():
                    return [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []

                def click(x, y, control=False):
                    before = len(opened())
                    button = 16 if control else 0
                    os.write(master, f'\x1b[<{button};{x};{y}M\x1b[<{button};{x};{y}m'.encode())
                    drain()
                    return opened()[before:]

                drain()
                link = [['https://example.org/pr/12']]
                plain = [['https://example.org/plain']]
                for label, x, y, control, want in (
                        ('OSC 8 ordinary click', 3, 1, False, link),
                        ('OSC 8 ctrl click', 3, 1, True, link),
                        ('visible url ordinary click', 10, 2, False, plain),
                        ('visible url ctrl click', 10, 2, True, plain),
                        ('click without any link', 5, 3, True, [])):
                    with self.subTest(label):
                        self.assertEqual(click(x, y, control), want, command('show-messages'))

                if version(tmux) < COPY_MODE_MOUSE:
                    # Older tmux keeps its own copy-mode mouse selection; the
                    # bindings are inert there, so only assert nothing breaks.
                    command('copy-mode', '-t', 'test')
                    drain()
                    self.assertEqual(click(3, 1), [])
                    self.assertEqual(command('display', '-p', '-t', 'test', '#{pane_in_mode}').strip(), '1')
                else:
                    for control in (False, True):
                        with self.subTest('copy mode ' + str(control)):
                            command('copy-mode', '-t', 'test')
                            drain()
                            self.assertEqual(click(3, 1, control), link, command('show-messages'))
                            command('copy-mode', '-q', '-t', 'test')
            finally:
                subprocess.run([tmux, '-S', socket, 'kill-server'], env=env, capture_output=True)
                attach.wait(timeout=5)
                os.close(master)

    def test_helper_opens_only_http_targets_without_shell_expansion(self):
        helper = CONFIG / 'scripts/open-link.py'
        namespace = {'__name__': 'open_link'}
        exec(compile(helper.read_text(), str(helper), 'exec'), namespace)
        clicked_url, in_line = namespace['clicked_url'], namespace['url_in_line']
        self.assertEqual(clicked_url(['hhttps://example.org/a?x=1&y=2']), 'https://example.org/a?x=1&y=2')
        for unsafe in ('hfile:///tmp/a', 'wjavascript:alert(1)', 'hhttps://example.org/\ntext', 'h'):
            self.assertIsNone(clicked_url([unsafe]), unsafe)
        self.assertEqual(in_line('Привет https://example.org/pr/12 потом', 10), 'https://example.org/pr/12')
        self.assertEqual(in_line('中文 https://example.org/a', 6), 'https://example.org/a')
        self.assertEqual(in_line('See (https://example.org/a).', 10), 'https://example.org/a')
        self.assertEqual(in_line('https://example.org/a  https://example.org/b', 25), 'https://example.org/b')
        self.assertIsNone(in_line('https://example.org/a    none', 25))


if __name__ == '__main__':
    unittest.main()
