#!/usr/bin/env python3
"""Private durable write-ahead undo journal. No model input is executable here."""
import ctypes
import codecs
from collections import deque
import difflib
import fcntl
import hashlib
import heapq
from functools import lru_cache
import json
import os
from pathlib import Path
import re
import shutil
import resource
import subprocess
import tempfile
import stat
import sys
import time
import uuid

DEFAULT_BUDGET = 2 * 1024 ** 3
FORBIDDEN = {'.ssh', '.gnupg', '.aws', '.kube', '.docker', '.git', '.password-store', '.mozilla', '.pki', 'keyrings', 'kwalletd', 'kwalletd5', 'kwalletd6', 'chromium', 'google-chrome', 'BraveSoftware', 'firefox', 'credentials', 'credentials.json', '.netrc', '.npmrc', '.pypirc', '.git-credentials', 'auth.json', 'id_rsa', 'id_ed25519'}
SYSTEM = ('/etc', '/usr', '/bin', '/sbin', '/lib', '/lib64', '/proc', '/sys', '/dev', '/run', '/var', '/root', '/boot')


def secret(name):
    return name in FORBIDDEN or name == '.env' or name.startswith('.env.') or name.endswith(('.pem', '.key', '.p12', '.pfx', '.kdbx'))


@lru_cache(maxsize=1)
def protection_roots():
    """Immutable enforcement code and its launch/import configuration, never model supplied."""
    home = Path.home()
    crate = Path(__file__).resolve().parents[1]
    checkout = crate.parent.parent
    config = Path(os.environ.get('XDG_CONFIG_HOME', str(home / '.config')))
    journal = Path(os.environ.get('XDG_STATE_HOME', str(home / '.local/state'))) / 'velora/transactions'
    roots = [crate, journal, checkout / 'tools/target/debug/velora-agentd',
             checkout / 'tools/target/release/velora-agentd', checkout / 'tools/Cargo.toml',
             checkout / 'tools/Cargo.lock', checkout / '.cargo',
             checkout / 'dots/.config/quickshell',
             home / '.local/bin', home / 'bin/velora-agentd',
             config / 'quickshell', home / '.config/quickshell']
    for name in ('velora', 'illogical-impulse'):
        roots.extend([checkout / 'dots/.config' / name / 'config.json',
                      checkout / 'dots/.config' / name / 'config.example.json',
                      config / name / 'config.json', home / '.config' / name / 'config.json'])
    try:
        roots.append(Path(os.readlink('/proc/' + str(os.getppid()) + '/exe')))
    except OSError:
        pass
    # Prevent PATH shadowing of the programs that enforce isolation or run providers.
    for directory in os.environ.get('PATH', '').split(os.pathsep):
        directory = os.path.abspath(directory or '.')
        for executable in ('velora-agentd', 'python3', 'bwrap', 'bash', 'curl', 'ollama', 'hyprctl', 'grim', 'kdialog', 'xdg-user-dir'):
            roots.append(Path(directory) / executable)
    resolved = []
    for root in roots:
        root = Path(os.path.abspath(root))
        resolved.append(root)
        try:
            canonical = root.resolve()
            if canonical != root:
                resolved.append(canonical)
        except (OSError, RuntimeError):
            pass
    return frozenset(resolved)


def protected_path(path):
    p = Path(os.path.abspath(path))
    roots = protection_roots()
    return p in roots or any(parent in roots for parent in p.parents)


def safe_path(value, root=False):
    p = Path(os.path.abspath(value))
    home = Path.home()
    if p == Path('/') or p == home or any(p == Path(x) or Path(x) in p.parents for x in SYSTEM):
        raise ValueError('Protected filesystem scope')
    if protected_path(p):
        raise ValueError('Protected executor or security policy path')
    if any(secret(part) for part in p.parts):
        raise ValueError('Protected credential or application data path')
    journal = Path(os.environ.get('XDG_STATE_HOME', str(home / '.local/state'))) / 'velora/transactions'
    if p == journal or journal in p.parents:
        raise ValueError('The rollback journal cannot be accessed by agent tools')
    for part in [*reversed(p.parents), p]:
        if part.is_symlink():
            raise ValueError('Symbolic links are not permitted')
    if not (p == home or home in p.parents or Path('/tmp') in p.parents):
        raise ValueError('Select a folder in your home directory or temporary workspace')
    if root and not p.is_dir():
        raise ValueError('Select an existing folder')
    return p


def sync_dir(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def save(path, obj):
    temp = path.with_name(path.name + '.new')
    fd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'w') as out:
        json.dump(obj, out, ensure_ascii=False)
        out.flush()
        os.fsync(out.fileno())
    os.replace(temp, path)
    sync_dir(path.parent)


def read(path):
    with path.open() as inp:
        return json.load(inp)


def identity(path):
    try:
        st = path.lstat()
    except FileNotFoundError:
        return None
    if stat.S_ISLNK(st.st_mode) or not (stat.S_ISREG(st.st_mode) or stat.S_ISDIR(st.st_mode)):
        raise ValueError('Only ordinary files and folders are supported')
    if st.st_mode & (stat.S_ISUID | stat.S_ISGID) or (stat.S_ISREG(st.st_mode) and st.st_nlink != 1):
        raise ValueError('Privileged or hard-linked files are not supported')
    if st.st_uid != os.getuid() or st.st_gid not in [os.getgid(), *os.getgroups()]:
        raise ValueError('Only files owned by this user with supported ownership can be changed')
    if stat.S_ISDIR(st.st_mode) and os.listxattr(path, follow_symlinks=False):
        raise ValueError('Folders with extended attributes require a dedicated rollback adapter')
    result = {'kind': 'dir' if stat.S_ISDIR(st.st_mode) else 'file', 'mode': stat.S_IMODE(st.st_mode), 'gid': st.st_gid}
    if result['kind'] == 'file':
        digest = hashlib.sha256()
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        with os.fdopen(fd, 'rb') as inp:
            actual = os.fstat(inp.fileno())
            if (st.st_dev, st.st_ino) != (actual.st_dev, actual.st_ino):
                raise ValueError('File changed while reading')
            for block in iter(lambda: inp.read(1024 * 1024), b''):
                digest.update(block)
            end = os.fstat(inp.fileno())
            if (actual.st_size, actual.st_mtime_ns, actual.st_ctime_ns) != (end.st_size, end.st_mtime_ns, end.st_ctime_ns):
                raise ValueError('File changed while reading')
        result.update(size=st.st_size, sha256=digest.hexdigest(), mtime_ns=st.st_mtime_ns, xattrs={k: os.getxattr(path, k, follow_symlinks=False).hex() for k in os.listxattr(path, follow_symlinks=False)})
    return result


def manifest(root, skip_secrets=False):
    result = {}
    def walk(path):
        if skip_secrets and (any(secret(p) for p in path.relative_to(root).parts) or protected_path(path)):
            return
        safe_path(path)
        item = identity(path)
        if item is None:
            return
        result[str(path.relative_to(root))] = item
        if item['kind'] == 'dir':
            for child in sorted(path.iterdir()):
                walk(child)
    walk(root)
    return result


def version(path):
    try:
        st = path.lstat()
        return [st.st_dev, st.st_ino, 0 if stat.S_ISDIR(st.st_mode) else st.st_ctime_ns]
    except FileNotFoundError:
        return None


def private_dir(path):
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    st = path.lstat()
    if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid() or stat.S_IMODE(st.st_mode) & 0o077:
        raise ValueError('Journal directory must be private and owned by this user')


def store():
    base = Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state')))
    # An alternate state root is used by isolated tests, never supplied by a model.
    parent = base / 'velora'
    parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    info = parent.lstat()
    # Other Velora components share this parent and may have created it as 0755.
    # Keep its existing mode; only the transaction journal must be private.
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) & 0o022:
        raise ValueError('Shared Velora state directory must be owned by this user and not writable by other users')
    root = parent / 'transactions'
    private_dir(root)
    return root


def identifier(value):
    if not isinstance(value, str) or not 1 <= len(value) <= 128 or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-' for c in value):
        raise ValueError('A stable ASCII submission/conversation identifier is required')
    return value


def summary(j):
    return {k: j[k] for k in ('transaction_id', 'submission_id', 'conversation_id', 'state', 'rollback_available', 'conflicts')}


def usage(root):
    return sum(p.stat().st_size for p in root.rglob('*') if p.is_file() and not p.is_symlink())


def budget(root, limit, extra=0):
    if usage(root) + extra > limit:
        raise ValueError('Rollback storage budget exceeded; explicitly delete old checkpoints or increase the budget')


def copied(source, target):
    fd = os.open(source, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, 'rb') as inp, target.open('xb') as out:
        os.chmod(target, 0o600)
        try:
            fcntl.ioctl(out.fileno(), 0x40049409, inp.fileno())  # FICLONE: copy-on-write when available
        except OSError:
            shutil.copyfileobj(inp, out, 1024 * 1024)
        out.flush()
        os.fsync(out.fileno())
    shutil.copystat(source, target, follow_symlinks=False)
    os.chown(target, -1, os.stat(source, follow_symlinks=False).st_gid)
    os.chmod(target, 0o600)
    return target


def parent_fd(path):
    # Hold descriptors through publication; a swapped parent symlink cannot redirect writes.
    fd = os.open('/', os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in path.parent.parts[1:]:
            nxt = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = nxt
        return fd
    except BaseException:
        os.close(fd)
        raise


def checked_descriptor(value, expected_device=None, expected_inode=None, allow_directory=False):
    path = safe_path(value)
    parent = parent_fd(path)
    try:
        fd = os.open(path.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent)
    finally:
        os.close(parent)
    try:
        info = os.fstat(fd)
        ordinary = stat.S_ISREG(info.st_mode) or (allow_directory and stat.S_ISDIR(info.st_mode))
        if not ordinary or info.st_uid != os.getuid() or info.st_mode & (stat.S_ISUID | stat.S_ISGID):
            raise ValueError('Only an ordinary file owned by this user may be read')
        if stat.S_ISREG(info.st_mode) and info.st_nlink != 1:
            raise ValueError('Hard-linked files cannot be read')
        if expected_device is not None and (info.st_dev, info.st_ino) != (expected_device, expected_inode):
            raise ValueError('File was replaced; select it again')
        return fd, info
    except BaseException:
        os.close(fd)
        raise


def open_directory(path):
    parent = parent_fd(path)
    try:
        return os.open(path.name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
    finally:
        os.close(parent)


def list_directory(req):
    path = safe_path(req['path'], True)
    fd, _ = checked_descriptor(path, req['device'], req['inode'], allow_directory=True)
    def visible(children):
        for child in children:
            if child.name <= req.get('after', '') or secret(child.name) or protected_path(path / child.name):
                continue
            try:
                info = child.stat(follow_symlinks=False)
            except FileNotFoundError:
                continue
            if info.st_uid == os.getuid() and not info.st_mode & (stat.S_ISUID | stat.S_ISGID):
                if stat.S_ISDIR(info.st_mode) or (stat.S_ISREG(info.st_mode) and info.st_nlink == 1):
                    yield child.name
    try:
        with os.scandir(fd) as children:
            entries = heapq.nsmallest(65, visible(children))
    finally:
        os.close(fd)
    return {'entries': entries[:64], 'next_cursor': entries[63] if len(entries) > 64 else None}


class MetadataScan:
    """Walk by name and inode without opening file contents or following links."""
    def __init__(self, root, fd, lookup):
        self.root, self.fd, self.lookup = root, fd, lookup
        self.partial = False

    def entries(self):
        initial = os.fstat(self.fd)
        pending = deque([(self.root, initial.st_ino, 0)])
        remaining = 40000 if self.lookup else 250000
        deadline = time.monotonic() + (3 if self.lookup else 12)
        blocked = protection_roots()
        while pending:
            if time.monotonic() >= deadline:
                self.partial = True
                return
            path, inode, depth = pending.popleft()
            try:
                fd = os.dup(self.fd) if depth == 0 else open_directory(path)
                try:
                    current = os.fstat(fd)
                    if (current.st_dev, current.st_ino, current.st_uid) != (initial.st_dev, inode, os.getuid()):
                        self.partial = True
                        continue
                    with os.scandir(fd) as children:
                        for child in children:
                            remaining -= 1
                            if remaining < 0 or time.monotonic() >= deadline:
                                self.partial = True
                                return
                            if self.lookup and child.name.startswith('.'):
                                continue
                            location = path / child.name
                            if secret(child.name) or location in blocked:
                                self.partial = True
                                continue
                            try:
                                info = child.stat(follow_symlinks=False)
                            except OSError:
                                self.partial = True
                                continue
                            directory = stat.S_ISDIR(info.st_mode)
                            if not directory and not stat.S_ISREG(info.st_mode):
                                continue
                            if info.st_uid != os.getuid() or info.st_dev != initial.st_dev or info.st_mode & (stat.S_ISUID | stat.S_ISGID):
                                self.partial = True
                                continue
                            yield location, info
                            if directory:
                                if depth >= (5 if self.lookup else 64):
                                    self.partial = True
                                elif not self.lookup or child.name not in ('node_modules', 'target', '__pycache__'):
                                    pending.append((location, info.st_ino, depth + 1))
                finally:
                    os.close(fd)
            except OSError:
                self.partial = True


# Match names such as «велора» and Velora in either script.
_LATIN = str.maketrans(dict(zip('абвгдеёжзийклмнопрстуфхцчшщъыьэюя',
                                ('a','b','v','g','d','e','e','zh','z','i','y','k','l','m','n','o',
                                 'p','r','s','t','u','f','kh','ts','ch','sh','sch','','y','','e','yu','ya'))))


def lookup_name(request):
    def folded(text):
        return text.casefold().translate(_LATIN)

    query = folded(request['query'].strip().rstrip('/').rsplit('/', 1)[-1][:512])
    words = set(re.findall(r'[\w.-]+', query))
    if not words:
        return {'results': [], 'partial': False}
    home = safe_path(request['root'], root=True) if 'root' in request else Path.home()
    fd = open_directory(home)
    matches = [(0, len(home.parts), str(home))] if 'root' in request and folded(home.name) == query else []
    try:
        scan = MetadataScan(home, fd, lookup=True)
        for path, info in scan.entries():
            directory = stat.S_ISDIR(info.st_mode)
            if request.get('kind') == 'folder' and not directory:
                continue
            if not directory and info.st_nlink != 1:
                continue
            name = folded(path.name)
            if name == query:
                rank = 0
            elif name in words and len(name) >= 3:
                rank = 1
            elif query in name:
                rank = 2
            else:
                continue
            matches.append((rank, len(path.parts), str(path)))
    finally:
        os.close(fd)
    return {'results': [{'path': path} for _, _, path in sorted(matches)[:12]], 'partial': scan.partial}


def folder_usage(request):
    path = Path(request['path'])
    fd, info = checked_descriptor(path, request['device'], request['inode'], allow_directory=True)
    try:
        if not stat.S_ISDIR(info.st_mode):
            raise ValueError('Select a folder to measure')
        total = info.st_blocks * 512
        sizes = {}
        links = set()
        scan = MetadataScan(path, fd, lookup=False)
        for child, entry in scan.entries():
            if stat.S_ISREG(entry.st_mode) and entry.st_nlink > 1:
                if entry.st_ino in links:
                    continue
                links.add(entry.st_ino)
            size = entry.st_blocks * 512
            total += size
            name = child.relative_to(path).parts[0]
            sizes[name] = sizes.get(name, 0) + size
        largest = sorted(sizes.items(), key=lambda item: (-item[1], item[0]))[:10]
        return {'path': str(path), 'allocated_bytes': total, 'partial': scan.partial,
                'largest': [{'name': name, 'allocated_bytes': size} for name, size in largest], 'untrusted': True}
    finally:
        os.close(fd)


def pdf_excerpt(source, page=None):
    # The only user file supplied to the parser is the already verified descriptor on stdin.
    command = ['/usr/bin/bwrap', '--unshare-all', '--die-with-parent', '--new-session', '--clearenv',
               '--ro-bind', '/usr', '/usr', '--symlink', 'usr/lib', '/lib', '--symlink', 'usr/lib', '/lib64',
               '--dev', '/dev', '--tmpfs', '/tmp', '--chdir', '/tmp',
               '--', '/usr/bin/pdftotext', '-f', str(page or 1), '-l', str(page or 12), '-enc', 'UTF-8', '-', '-']

    def limits():
        resource.setrlimit(resource.RLIMIT_CPU, (4, 4))
        resource.setrlimit(resource.RLIMIT_AS, (512 << 20, 512 << 20))
        resource.setrlimit(resource.RLIMIT_FSIZE, (1 << 20, 1 << 20))

    with tempfile.TemporaryFile() as output:
        try:
            result = subprocess.run(command, stdin=source, stdout=output, stderr=subprocess.DEVNULL,
                                    timeout=6, preexec_fn=limits)
        except (OSError, subprocess.TimeoutExpired) as error:
            raise ValueError('PDF text extraction is unavailable') from error
        if result.returncode != 0:
            raise ValueError('Could not extract text from this PDF')
        output.seek(0)
        text = output.read(32 * 1024).decode('utf-8', 'ignore').strip()
    if not text:
        raise ValueError('This PDF has no readable text in its first 12 pages')
    return {'text': text[:2500], 'truncated': True, 'untrusted': True}


def guarded_read(request, script=False):
    if not isinstance(request.get('device'), int) or not isinstance(request.get('inode'), int):
        raise ValueError('A remembered file identity is required')
    fd, before = checked_descriptor(request['path'], request['device'], request['inode'])
    with os.fdopen(fd, 'rb') as source:
        if script:
            data = source.read(32769)
            if len(data) > 32768:
                raise ValueError('Script exceeds the 32 KiB execution preview')
            result = {'code': data.decode('utf-8')}
        elif source.peek(5)[:5] == b'%PDF-':
            page = request.get('page')
            if request.get('offset') or (page is not None and (type(page) is not int or not 1 <= page <= 100000)):
                raise ValueError('Use a PDF page number starting at 1')
            if before.st_size > 32 * 1024 * 1024:
                raise ValueError('Select a smaller PDF (32 MiB maximum)')
            # peek() may have filled the Python buffer. Rewind the underlying descriptor for the child.
            os.lseek(source.fileno(), 0, os.SEEK_SET)
            result = pdf_excerpt(source, page)
        else:
            offset = request.get('offset', 0)
            if request.get('page') is not None or type(offset) is not int or not 0 <= offset <= before.st_size:
                raise ValueError('Use a byte offset returned by files_read')
            source.seek(offset)
            data = source.read(10000)
            try:
                text = codecs.getincrementaldecoder('utf-8')().decode(data, final=source.tell() == before.st_size)[:2500]
            except UnicodeDecodeError:
                raise ValueError('This file is not UTF-8 text')
            next_offset = offset + len(text.encode('utf-8'))
            more = next_offset < before.st_size
            result = {'text': text, 'truncated': more, 'next_offset': next_offset if more else None, 'untrusted': True}
        after = os.fstat(source.fileno())
        if (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns, before.st_ctime_ns, before.st_nlink) != (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns, after.st_ctime_ns, after.st_nlink):
            raise ValueError('File changed while reading')
    return result


def rename_at(fd, source, target, flags):
    libc = ctypes.CDLL(None, use_errno=True)
    fn = libc.renameat2
    fn.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    if fn(fd, os.fsencode(source), fd, os.fsencode(target), flags) != 0:
        raise OSError(ctypes.get_errno(), 'Atomic publication failed')


def install(path, wanted, source, expected, expected_version=None, entry=None, checkpoint=None):
    safe_path(path)
    fd = parent_fd(path)
    try:
        # The descriptor path pins the checked parent; final leaf reads do not follow symlinks.
        pinned = Path('/proc/self/fd') / str(fd) / path.name
        if identity(pinned) != expected or (expected_version is not None and version(pinned) != expected_version):
            raise ValueError('A file changed since the plan was prepared')
        if wanted is None:
            if expected['kind'] == 'dir':
                os.rmdir(path.name, dir_fd=fd)
            else:
                temp = entry.get('scratch') if entry else '.velora-write-' + uuid.uuid4().hex
                rename_at(fd, path.name, temp, 1)
                displaced = Path('/proc/self/fd') / str(fd) / temp
                if identity(displaced) != expected or (expected_version is not None and version(displaced)[:2] != expected_version[:2]):
                    raise ValueError('Concurrent replacement preserved for conflict recovery')
                os.unlink(temp, dir_fd=fd)
        elif wanted['kind'] == 'dir':
            if expected is None:
                os.mkdir(path.name, wanted['mode'], dir_fd=fd)
                if 'gid' in wanted: os.chown(path.name, -1, wanted['gid'], dir_fd=fd, follow_symlinks=False)
                os.chmod(path.name, wanted['mode'], dir_fd=fd, follow_symlinks=False)
            elif expected['kind'] != 'dir':
                raise ValueError('File/folder type changes are not supported')
            else:
                if 'gid' in wanted: os.chown(path.name, -1, wanted['gid'], dir_fd=fd, follow_symlinks=False)
                os.chmod(path.name, wanted['mode'], dir_fd=fd, follow_symlinks=False)
        else:
            if expected is not None and expected['kind'] != 'file':
                raise ValueError('File/folder type changes are not supported')
            temp = entry.get('scratch') if entry else '.velora-write-' + uuid.uuid4().hex
            preserve_temp = False
            outfd = os.open(temp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, wanted['mode'], dir_fd=fd)
            try:
                if entry is not None:
                    entry['scratch_inode'] = version(Path('/proc/self/fd') / str(fd) / temp)[:2]
                    checkpoint()
                with os.fdopen(outfd, 'wb') as out, source.open('rb') as inp:
                    shutil.copyfileobj(inp, out, 1024 * 1024)
                    if 'gid' in wanted: os.fchown(out.fileno(), -1, wanted['gid'])
                    os.fchmod(out.fileno(), wanted['mode'])
                    out.flush()
                    if 'mtime_ns' in wanted: os.utime(out.fileno(), ns=(wanted['mtime_ns'], wanted['mtime_ns']))
                    for key, value in wanted.get('xattrs', {}).items(): os.setxattr(out.fileno(), key, bytes.fromhex(value))
                    os.fsync(out.fileno())
                if identity(pinned) != expected or (expected_version is not None and version(pinned) != expected_version):
                    raise ValueError('A file changed before publication')
                if entry is not None:
                    entry['after_inode'] = version(Path('/proc/self/fd') / str(fd) / temp)[:2]
                    checkpoint()
                # A single no-replace rename has no transient hard-link crash window.
                if expected is None:
                    rename_at(fd, temp, path.name, 1)
                else:
                    # Exchange retains the replaced object until its identity is checked.
                    # A concurrent writer can never have its bytes silently discarded.
                    rename_at(fd, temp, path.name, 2)
                    preserve_temp = True
                    displaced = Path('/proc/self/fd') / str(fd) / temp
                    if identity(displaced) != expected or (expected_version is not None and version(displaced)[:2] != expected_version[:2]):
                        preserve_temp = True
                        raise ValueError('Concurrent replacement preserved for conflict recovery')
                    os.unlink(temp, dir_fd=fd)
                    preserve_temp = False
            finally:
                if not preserve_temp:
                    try:
                        os.unlink(temp, dir_fd=fd)
                    except FileNotFoundError:
                        pass
        os.fsync(fd)
    finally:
        os.close(fd)


def rollback(root, folder, j):
    conflicts = []
    j['state'] = 'rolling_back'
    save(folder / 'journal.json', j)
    for entry in reversed(j['entries']):
        if entry.get('restored') or not entry.get('started'):
            continue
        path = Path(entry['path'])
        try:
            safe_path(path)
            scratch = path.with_name(entry['scratch']) if entry.get('scratch') else None
            if scratch and scratch.exists():
                displaced = identity(scratch)
                owned_scratch = entry.get('scratch_inode') == version(scratch)[:2]
                if not owned_scratch and displaced not in (entry['before'], entry['after']):
                    conflicts.append(str(scratch))
                    raise ValueError('Concurrent replacement preserved beside the original path')
                scratch.unlink()
                sync_dir(path.parent)
            current = identity(path)
            if current == entry['before']:
                pass
            elif current == entry['after'] and (not entry.get('after_version') or version(path) == entry['after_version']) and (not entry.get('after_inode') or version(path)[:2] == entry['after_inode']):
                install(path, entry['before'], folder / entry['backup'] if entry.get('backup') else None, current)
            else:
                raise ValueError('Newer user changes must be preserved')
            for earlier in j['entries'][:j['entries'].index(entry)]:
                if earlier['path'] == entry['path'] and earlier['after'] == entry['before']:
                    earlier['after_version'] = version(path)
                    earlier['after_inode'] = version(path)[:2] if version(path) else None
            entry['restored'] = True
            save(folder / 'journal.json', j)
        except (OSError, ValueError):
            conflicts.append(str(path))
    for staging in folder.glob('stage-*'):
        shutil.rmtree(staging)
    j['conflicts'] = conflicts
    j['state'] = 'rollback_conflict' if conflicts else 'rolled_back'
    j['rollback_available'] = bool(conflicts)
    save(folder / 'journal.json', j)
    return summary(j)


def prepare(root, folder, j, changes):
    if j['state'] not in ('running', 'preparing'):
        raise ValueError('Transaction is not active')
    if len(changes) > 10000:
        raise ValueError('Change exceeds the 10000-file transaction limit')
    extra = sum((c['before'] or {}).get('size', 0) + (c['after'] or {}).get('size', 0) for c in changes)
    budget(root, j['budget'], extra)
    plan = uuid.uuid4().hex
    entries = []
    for change in changes:
        path = safe_path(change['path'])
        if identity(path) != change['before']:
            raise ValueError('A file changed while preparing the transaction')
        entry = {k: change[k] for k in ('path', 'before', 'after')}
        entry.update(plan=plan, started=False, restored=False, before_version=version(path), scratch='.velora-write-' + uuid.uuid4().hex)
        if change['before'] and change['before']['kind'] == 'file':
            entry['backup'] = 'backup-' + uuid.uuid4().hex
            copied(path, folder / entry['backup'])
            if identity(path) != change['before']:
                raise ValueError('A file changed while creating its checkpoint')
        if change['after'] and change['after']['kind'] == 'file':
            entry['desired'] = 'desired-' + uuid.uuid4().hex
            copied(Path(change['source']), folder / entry['desired'])
            desired = identity(folder / entry['desired'])
            if desired['sha256'] != change['after']['sha256'] or desired['size'] != change['after']['size']:
                raise ValueError('Prepared content changed')
        entries.append(entry)
    sync_dir(folder)
    j['entries'].extend(entries)
    save(folder / 'journal.json', j)
    diff = []
    remaining = 128 * 1024
    for entry in entries:
        item = {'path': entry['path'], 'change': 'create' if entry['before'] is None else 'delete' if entry['after'] is None else 'modify', 'before_bytes': (entry['before'] or {}).get('size', 0), 'after_bytes': (entry['after'] or {}).get('size', 0)}
        try:
            large = max(item['before_bytes'], item['after_bytes']) > 64 * 1024
            before = (folder / entry['backup']).read_bytes() if entry.get('backup') and not large else b''
            after = (folder / entry['desired']).read_bytes() if entry.get('desired') and not large else b''
            if large or b'\0' in before or b'\0' in after:
                item['preview'] = 'Binary or large file; see sizes and exact path'
            else:
                text = ''.join(difflib.unified_diff(before.decode('utf-8').splitlines(keepends=True), after.decode('utf-8').splitlines(keepends=True), fromfile=entry['path'] + ' (before)', tofile=entry['path'] + ' (after)'))
                item['diff'] = text[:max(0, remaining)]
                item['truncated'] = len(text) > remaining
                remaining -= len(item['diff'])
        except UnicodeDecodeError:
            item['preview'] = 'Binary file; see sizes and exact path'
        diff.append(item)
    return {'plan': plan, 'diff': diff, 'transaction_id': j['transaction_id']}


def file_changes(operation, args):
    changes = []
    def add(path, after, source=None):
        path = safe_path(path)
        changes.append({'path': str(path), 'before': identity(path), 'after': after, 'source': str(source) if source else None})
    if operation == 'mkdir':
        target = safe_path(args['target'])
        if target.exists():
            raise ValueError('Destination already exists')
        add(target, {'kind': 'dir', 'mode': 0o755, 'gid': target.parent.stat().st_gid})
    elif operation in ('copy', 'move', 'trash'):
        source = safe_path(args['source'])
        tree = manifest(source)
        if not tree:
            raise ValueError('Source does not exist')
        if operation != 'trash':
            target = safe_path(args['target'])
            if target.exists() or target == source or source in target.parents:
                raise ValueError('Destination must be a new path outside the source')
            for rel, item in tree.items():
                add(target if rel == '.' else target / rel, item, source if rel == '.' else source / rel)
        if operation in ('move', 'trash'):
            for rel in reversed(tree):
                add(source if rel == '.' else source / rel, None)
    elif operation == 'publish':
        target = safe_path(args['target'])
        if target.exists():
            raise ValueError('Destination already exists')
        add(target, identity(Path(args['source'])), Path(args['source']))
    else:
        raise ValueError('Unsupported transactional file action')
    return changes


def execute(req):
    if req['operation'] == 'list_directory':
        return list_directory(req)
    if req['operation'] == 'lookup_name':
        return lookup_name(req)
    if req['operation'] == 'folder_usage':
        return folder_usage(req)
    if req['operation'] == 'read_script':
        return guarded_read(req, script=True)
    root = store()
    lock = root / '.lock'
    fd = os.open(lock, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'w') as lease:
        fcntl.flock(lease, fcntl.LOCK_EX)
        op = req['operation']
        if op == 'initialize':
            return {'root': str(root)}
        if op == 'validate_tree':
            manifest(safe_path(req['path']))
            return {'valid': True}
        if op == 'read_file':
            return guarded_read(req)
        if op == 'check_paths':
            allowed = []
            for value in req.get('paths', [])[:100]:
                try:
                    fd, _ = checked_descriptor(value, allow_directory=True)
                    os.close(fd)
                    allowed.append(str(safe_path(value)))
                except (ValueError, OSError): pass
            return {'paths': allowed}
        if op == 'check':
            return {'path': str(safe_path(req['path'], req.get('directory', False)))}
        if op in ('list', 'recover'):
            results = []
            for folder in sorted(root.iterdir()):
                if not folder.is_dir() or folder.is_symlink():
                    continue
                if not (folder / 'journal.json').exists():
                    continue
                j = read(folder / 'journal.json')
                if op == 'recover' and j['state'] in ('running', 'preparing', 'rolling_back'):
                    results.append(rollback(root, folder, j))
                else:
                    results.append(summary(j))
            return {'transactions': results}
        tid = identifier(req.get('transaction_id', req.get('submission_id')))
        folder = root / tid
        if op == 'begin':
            cid = identifier(req['conversation_id'])
            if folder.exists():
                raise ValueError('Submission was already recorded; it will not execute again')
            limit = req.get('budget', DEFAULT_BUDGET)
            if not isinstance(limit, int) or not 1024 * 1024 <= limit <= 1024 ** 4:
                raise ValueError('Invalid rollback storage budget')
            budget(root, limit)
            private_dir(folder)
            j = dict(transaction_id=tid, submission_id=tid, conversation_id=cid, state='running', rollback_available=False, conflicts=[], entries=[], budget=limit)
            save(folder / 'journal.json', j)
            sync_dir(root)
            return summary(j)
        j = read(folder / 'journal.json')
        if op == 'budget':
            budget(root, j['budget'])
            return {'ok': True}
        if op == 'status':
            return summary(j)
        if op == 'rollback':
            if j['state'] == 'checkpoint_deleted':
                raise ValueError('Checkpoint was explicitly deleted')
            return rollback(root, folder, j)
        if op == 'delete':
            if req.get('confirmed') is not True or j['state'] in ('running', 'preparing', 'rolling_back', 'rollback_conflict'):
                raise ValueError('Stop the task and resolve rollback conflicts before explicitly deleting its checkpoint')
            for p in folder.iterdir():
                if p.name == 'journal.json':
                    continue
                if p.is_dir(): shutil.rmtree(p)
                else: p.unlink()
            j.update(state='checkpoint_deleted', rollback_available=False, entries=[])
            save(folder / 'journal.json', j)
            return summary(j)
        if op == 'commit':
            j.update(state='committed', rollback_available=any(e.get('started') for e in j['entries']))
            save(folder / 'journal.json', j)
            # Discard disposable staging, keep durable before/after content until explicit deletion.
            for p in folder.glob('stage-*'):
                shutil.rmtree(p)
            return summary(j)
        if op == 'prepare_write':
            file = req['file']
            target = safe_path(file['target'])
            before = identity(target)
            if 'inode' in file:
                fd, _ = checked_descriptor(target, file['device'], file['inode'])
                os.close(fd)
            elif before is not None:
                raise ValueError('File already exists. List it and use its ref to edit it')
            content = req['text'].encode('utf-8')
            if len(content) > 32768:
                raise ValueError('Text exceeds the 32 KiB write limit')
            with tempfile.NamedTemporaryFile(dir=folder) as staged:
                staged.write(content)
                staged.flush()
                source = Path(staged.name)
                after = identity(source)
                if before:
                    after.update({key: before[key] for key in ('mode', 'gid', 'xattrs')})
                return prepare(root, folder, j, [{'path': str(target), 'before': before, 'after': after, 'source': str(source)}])
        if op == 'prepare_files':
            return prepare(root, folder, j, file_changes(req['kind'], req['args']))
        if op == 'snapshot_inputs':
            items = req['inputs']
            if not isinstance(items, list) or not 1 <= len(items) <= 32:
                raise ValueError('Choose up to 32 input files')
            stage = folder / ('stage-inputs-' + uuid.uuid4().hex)
            private_dir(stage)
            try:
                for i, item in enumerate(items, 1):
                    fd, info = checked_descriptor(item['path'], item['device'], item['inode'])
                    with os.fdopen(fd, 'rb') as source:
                        input_version = (info.st_size, info.st_mtime_ns, info.st_ctime_ns)
                        if input_version[1:] != (item['mtime_ns'], item['ctime_ns']):
                            raise ValueError('Input file changed while awaiting approval')
                        budget(root, j['budget'], info.st_size)
                        with (stage / str(i)).open('xb') as target:
                            remaining = info.st_size
                            while remaining:
                                block = source.read(min(remaining, 1024 * 1024))
                                if not block: raise ValueError('Input file changed during staging')
                                target.write(block)
                                remaining -= len(block)
                        end = os.fstat(fd)
                        if input_version != (end.st_size, end.st_mtime_ns, end.st_ctime_ns) or end.st_nlink != 1:
                            raise ValueError('Input file changed during staging')
                return {'stage':stage.name,'path':str(stage)}
            except BaseException:
                shutil.rmtree(stage)
                raise
        if op == 'stage':
            cwd = safe_path(req['cwd'], True)
            before = manifest(cwd, skip_secrets=True)
            budget(root, j['budget'], sum(x.get('size', 0) for x in before.values()))
            sid = 'stage-' + uuid.uuid4().hex
            staging = folder / sid
            private_dir(staging)
            work = staging / 'work'
            work.mkdir(mode=0o700)
            for rel, item in before.items():
                if rel == '.': continue
                dest = work / rel
                if item['kind'] == 'dir':
                    dest.mkdir(mode=item['mode'])
                    os.chown(dest, -1, item['gid'])
                    dest.chmod(item['mode'])
                else:
                    copied(cwd / rel, dest)
                    dest.chmod(item['mode'])
            os.chown(work, -1, before['.']['gid'])
            work.chmod(before['.']['mode'])
            save(staging / 'before.json', {'cwd': str(cwd), 'manifest': before})
            return {'stage': sid, 'path': str(work), 'cwd': str(cwd)}
        if op in ('prepare_stage', 'discard_stage'):
            sid = req['stage']
            if not sid.startswith('stage-') or '/' in sid or '..' in sid:
                raise ValueError('Invalid staging reference')
            staging = folder / sid
            if op == 'discard_stage':
                shutil.rmtree(staging)
                return {'discarded': True}
            recorded = read(staging / 'before.json')
            cwd = safe_path(recorded['cwd'], True)
            before = recorded['manifest']
            if manifest(cwd, skip_secrets=True) != before:
                raise ValueError('Working folder changed while the command ran')
            work = staging / 'work'
            # Staging is private journal data, so scan without applying host path policy.
            after = {}
            def walk(p):
                rel = str(p.relative_to(work))
                if rel != '.' and any(secret(x) for x in Path(rel).parts):
                    raise ValueError('Command attempted to create protected data')
                item = identity(p)
                after[rel] = item
                if item['kind'] == 'dir':
                    for child in sorted(p.iterdir()): walk(child)
            walk(work)
            changes = []
            # Remove children before parents, create parents before children.
            for rel in sorted(set(before) - set(after), key=lambda x: (-len(Path(x).parts), x)):
                if rel != '.': changes.append({'path': str(cwd / rel), 'before': before[rel], 'after': None})
            for rel in sorted(after, key=lambda x: (len(Path(x).parts), x)):
                if rel == '.' or before.get(rel) == after[rel]: continue
                if before.get(rel) and before[rel]['kind'] != after[rel]['kind']:
                    raise ValueError('Command changed a file/folder type; apply manually')
                changes.append({'path': str(cwd / rel), 'before': before.get(rel), 'after': after[rel], 'source': str(work / rel)})
            return prepare(root, folder, j, changes)
        if op == 'apply':
            if j['state'] != 'running':
                raise ValueError('Transaction is not active')
            entries = [e for e in j['entries'] if e['plan'] == req['plan']]
            if any(e['started'] for e in entries):
                raise ValueError('Prepared changes cannot be applied twice')
            for e in entries:
                safe_path(e['path'])
                if identity(Path(e['path'])) != e['before'] or version(Path(e['path'])) != e['before_version']:
                    raise ValueError('A file changed after confirmation was requested')
            for e in entries:
                e['started'] = True
                save(folder / 'journal.json', j)
                install(Path(e['path']), e['after'], folder / e['desired'] if e.get('desired') else None, e['before'], e['before_version'], e, lambda: save(folder / 'journal.json', j))
                e['after_version'] = version(Path(e['path']))
                e['applied'] = True
                j['rollback_available'] = True
                save(folder / 'journal.json', j)
            return {'changed': len(entries), 'transaction_id': tid}
        raise ValueError('Unknown journal operation')


if __name__ == '__main__':
    try:
        data = sys.stdin.buffer.read(1024 * 1024 + 1)
        if len(data) > 1024 * 1024:
            raise ValueError('Journal request is too large')
        print(json.dumps(execute(json.loads(data)), ensure_ascii=False))
    except Exception as error:
        message = str(error) if isinstance(error, ValueError) else {28: 'Not enough disk space for a rollback checkpoint', 13: 'Access denied', 39: 'Folder contains newer files; rollback preserved them'}.get(getattr(error, 'errno', None), type(error).__name__)
        print(json.dumps({'error': message}))
