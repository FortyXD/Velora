#!/usr/bin/env python3
"""Bounded filesystem and accessibility helpers. Requests arrive on stdin, never argv."""
import ctypes
import json
import os
from pathlib import Path
import shutil
import stat
import sys
import zipfile


def archive(paths, output):
    output = Path(output).resolve()
    count = 0
    used = set()
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED, compresslevel=3, allowZip64=True) as result:
        def add(path, name):
            nonlocal count
            if path.absolute() == output:
                return
            count += 1
            if count > 100000:
                raise ValueError('Archive exceeds 100000 entries')
            info = path.lstat()
            if stat.S_ISLNK(info.st_mode):
                entry = zipfile.ZipInfo(name)
                entry.create_system = 3
                entry.external_attr = (stat.S_IFLNK | 0o777) << 16
                result.writestr(entry, os.readlink(path))
            elif stat.S_ISDIR(info.st_mode):
                result.writestr(name + '/', b'')
                for child in sorted(path.iterdir()):
                    add(child, name + '/' + child.name)
            elif stat.S_ISREG(info.st_mode):
                # Do not follow a symlink substituted after discovery.
                fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
                with os.fdopen(fd, 'rb') as source:
                    actual = os.fstat(source.fileno())
                    if (actual.st_dev, actual.st_ino) != (info.st_dev, info.st_ino):
                        raise ValueError('A source changed while archiving')
                    with result.open(name, 'w', force_zip64=True) as target:
                        shutil.copyfileobj(source, target, 1024 * 1024)
            else:
                raise ValueError('Archives support ordinary files and folders only')
        for value in paths:
            path = Path(value)
            if path.name in used:
                raise ValueError('Source names collide inside the archive; rename or archive separately')
            used.add(path.name)
            add(path, path.name)
    with zipfile.ZipFile(output) as result:
        if result.testzip() is not None:
            raise ValueError('Archive verification failed')
    return {'entries': count, 'verified': True}


def move(source, target):
    # Linux renameat2 avoids the check-then-overwrite race of shutil.move/rename.
    libc = ctypes.CDLL(None, use_errno=True)
    fn = libc.renameat2
    fn.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    if fn(-100, os.fsencode(source), -100, os.fsencode(target), 1) != 0:
        code = ctypes.get_errno()
        raise OSError(code, os.strerror(code))
    return {'verified': os.path.lexists(target) and not os.path.lexists(source)}


def copy(source, target):
    source, target = Path(source), Path(target)
    if source.is_dir():
        # Reserve the destination; never merge into an existing folder.
        target.mkdir()
        try:
            shutil.copytree(source, target, symlinks=True, dirs_exist_ok=True)
        except BaseException:
            shutil.rmtree(target)
            raise
    else:
        fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        try:
            with os.fdopen(fd, 'wb') as out, source.open('rb') as inp:
                shutil.copyfileobj(inp, out, 1024 * 1024)
                out.flush()
                os.fsync(out.fileno())
        except BaseException:
            target.unlink(missing_ok=True)
            raise
    return {'verified': target.exists()}


def accessibility(request):
    import gi
    gi.require_version('Atspi', '2.0')
    from gi.repository import Atspi
    desktop = Atspi.get_desktop(0)
    apps = [desktop.get_child_at_index(i) for i in range(desktop.get_child_count())]
    app = next((a for a in apps if a.get_process_id() == int(request['pid'])), None)
    if app is None:
        return {'nodes': []}
    nodes = []
    windows = [app.get_child_at_index(i) for i in range(app.get_child_count())]
    windows = [w for w in windows if w and w.get_name() == request.get('title')]
    if len(windows) != 1:
        return {'nodes': []}
    pending = [(windows[0], '0', 0)]
    target = request.get('node')
    while pending and len(nodes) < 200:
        element, identifier, depth = pending.pop(0)
        label = element.get_name() or ''
        role = element.get_role_name() or ''
        actions = element.get_action_iface()
        action_names = [actions.get_action_name(i) for i in range(actions.get_n_actions())] if actions else []
        if target and identifier == target['id']:
            if label != target['name'] or role != target['role'] or not action_names:
                raise ValueError('The accessible element changed')
            if not actions.do_action(0):
                raise ValueError('Application rejected the accessibility action')
            return {'accepted': True}
        nodes.append({'id': identifier, 'name': label[:300], 'role': role, 'actions': action_names})
        if depth < 8:
            for i in range(min(40, element.get_child_count())):
                child = element.get_child_at_index(i)
                if child:
                    pending.append((child, identifier + '.' + str(i), depth + 1))
    if target:
        raise ValueError('The accessible element no longer exists')
    return {'nodes': nodes, 'untrusted': True}


def execute(request):
    operation = request['operation']
    if operation == 'zip':
        return archive(request['paths'], request['output'])
    if operation == 'move':
        return move(request['source'], request['target'])
    if operation == 'copy':
        return copy(request['source'], request['target'])
    if operation in ('inspect', 'action'):
        return accessibility(request)
    raise ValueError('Unknown operation')


if __name__ == '__main__':
    try:
        data = sys.stdin.buffer.read(1024 * 1024 + 1)
        if len(data) > 1024 * 1024:
            raise ValueError('Request is too large')
        print(json.dumps(execute(json.loads(data)), ensure_ascii=False))
    except Exception as error:
        # stdout is machine-readable; no personal paths or contents in diagnostics.
        messages = {28: 'Not enough disk space', 17: 'Destination already exists', 13: 'Access denied', 18: 'Cross-filesystem move requires copy then confirmed trash'}
        print(json.dumps({'error': messages.get(getattr(error, 'errno', None), type(error).__name__)}))
