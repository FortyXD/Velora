"""Guest-only local Git update fixture; run after syncing the source. Use a fresh snapshot."""
from pathlib import Path
import json
import subprocess

assert Path('/var/lib/velora-qemu-ready').exists()
home = Path.home()
repo = home / 'Velora'
def git(path, *args):
    return subprocess.check_output(['git', '-c', 'user.name=QEMU', '-c', 'user.email=qemu@example.invalid', *args], cwd=path, text=True).strip()
git(repo, 'add', '-A')
git(repo, 'commit', '--allow-empty', '-m', 'QEMU GUI update baseline')
branch = git(repo, 'branch', '--show-current')
remote = home / 'gui-update-remote.git'
author = home / 'gui-update-author'
git(home, 'clone', '--bare', str(repo), str(remote))
if 'origin' in git(repo, 'remote').splitlines():
    git(repo, 'remote', 'remove', 'origin')
git(repo, 'remote', 'add', 'origin', str(remote))
git(repo, 'fetch', 'origin')
git(repo, 'branch', '--set-upstream-to=origin/' + branch)
git(home, 'clone', str(remote), str(author))
(author / 'VERSION').write_text('0.0.0-qemu.gui.1\n')
git(author, 'add', 'VERSION')
git(author, 'commit', '-m', 'QEMU GUI update release')
git(author, 'push', 'origin', branch)
state = home / '.local/state/velora'
(state / 'update-settings.json').write_text(json.dumps({'channel':'branch', 'automatic_checks':False}))
page = home / '.local/state/quickshell/user/settings_page.txt'
page.parent.mkdir(parents=True, exist_ok=True)
page.write_text('updates')
subprocess.run([str(repo / 'velora'), 'update', '--check'], check=True)
print('Local update ready. Existing packages and authorization policy are unchanged.')
