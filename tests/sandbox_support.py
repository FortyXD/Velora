"""Probe host isolation support independently of the production sandbox code."""
import functools
import os
import shutil
import subprocess


@functools.lru_cache(maxsize=1)
def unavailable_reason():
    if not shutil.which('bwrap'):
        return 'bubblewrap is not installed'
    probe = subprocess.run(['bwrap', '--die-with-parent', '--unshare-all', '--cap-drop', 'ALL',
                            '--ro-bind', '/', '/', '--proc', '/proc', '--dev', '/dev', '/usr/bin/true'],
                           capture_output=True, text=True, timeout=10)
    if probe.returncode:
        return probe.stderr.strip() or f'bubblewrap exited {probe.returncode}'
    return ''


def require_sandbox(case):
    reason = unavailable_reason()
    if not reason:
        return
    if os.environ.get('VELORA_REQUIRE_SANDBOX_TESTS') == '1':
        case.fail('Required sandbox unavailable: ' + reason)
    case.skipTest('Host cannot create the sandbox (required in QEMU release checks): ' + reason)
