#!/usr/bin/env python3
"""Bounded, local-only preview metadata/rendering for the standalone Quick Look UI."""
import argparse
import json
import mimetypes
import os
from pathlib import Path
import resource
import signal
import sys
import subprocess
import tempfile

TEXT_LIMIT = 256 * 1024
ARCHIVES = ('.zip', '.tar', '.tgz', '.gz', '.bz2', '.xz', '.7z', '.rar', '.zst')


def limits():
    resource.setrlimit(resource.RLIMIT_AS, (1024**3, 1024**3))
    resource.setrlimit(resource.RLIMIT_FSIZE, (32 * 1024**2, 32 * 1024**2))


def command(argv, limit=TEXT_LIMIT, timeout=12):
    # A file bounds memory even when a decoder produces an enormous diagnostic/list.
    with tempfile.TemporaryFile() as output:
        process = subprocess.Popen(argv, stdout=output, stderr=subprocess.DEVNULL, preexec_fn=limits)
        try:
            process.wait(timeout=timeout)
            if process.returncode:
                raise ValueError('The file could not be decoded')
            output.seek(0)
            data = output.read(limit + 1)
            return data[:limit].decode('utf-8', errors='replace'), len(data) > limit
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()


def describe(path, directory, page=1):
    path = Path(path).absolute()
    info = {'name': path.name, 'path': str(path), 'url': path.as_uri(), 'kind': 'other'}
    try:
        stat = path.stat()
        info.update(size=stat.st_size, modified=stat.st_mtime)
        if path.is_dir():
            info['kind'] = 'text'
            with os.scandir(path) as entries:
                names = []
                for entry in entries:
                    names.append(entry.name + ('/' if entry.is_dir(follow_symlinks=False) else ''))
                    if len(names) == 1000:
                        info['truncated'] = True
                        break
            info['text'] = '\n'.join(sorted(names))
            return info
        if not path.is_file():
            raise ValueError('Only regular files can be previewed')
        mime, _ = command(['file', '--brief', '--mime-type', '--', str(path)], 256)
        mime = mime.strip()
        info['mime'] = mime
        if mime == 'application/pdf':
            metadata, _ = command(['pdfinfo', str(path)], 16384)
            pages = next((int(line.split(':')[1]) for line in metadata.splitlines() if line.startswith('Pages:')), 1)
            page = max(1, min(page, pages))
            output = Path(directory) / f'page-{page}'
            command(['pdftoppm', '-f', str(page), '-l', str(page), '-scale-to', '1600', '-singlefile', '-png', str(path), str(output)])
            info.update(kind='pdf', pages=pages, page=page, preview=output.with_suffix('.png').as_uri())
        elif mime.startswith('image/'):
            from PIL import Image
            # Inspect dimensions before Qt allocates a decoded frame.
            with Image.open(path) as picture:
                if picture.width * picture.height > 32_000_000:
                    raise ValueError('Image is too large for Quick Look')
                info.update(width=picture.width, height=picture.height)
            info['kind'] = 'gif' if mime == 'image/gif' else 'image'
        elif mime.startswith('video/') or mime.startswith('audio/'):
            info['kind'] = mime.split('/')[0]
        elif path.name.lower().endswith(ARCHIVES):
            listing, truncated = command(['bsdtar', '-tf', str(path)])
            lines = listing.splitlines()
            info.update(kind='text', text='\n'.join(lines[:1000]), truncated=truncated or len(lines) > 1000)
        elif mime.startswith('text/') or mime in ('application/json', 'application/xml', 'application/javascript', 'application/x-shellscript'):
            with path.open('rb') as source:
                data = source.read(TEXT_LIMIT + 1)
            info.update(kind='text', text=data[:TEXT_LIMIT].decode('utf-8', errors='replace'), truncated=len(data) > TEXT_LIMIT)
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        info.update(kind='other', error=str(error))
    return info


def main():
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    parser = argparse.ArgumentParser()
    parser.add_argument('path')
    parser.add_argument('--directory', required=True)
    parser.add_argument('--page', type=int, default=1)
    parser.add_argument('--request-id', type=int, default=0)
    args = parser.parse_args()
    result = describe(args.path, args.directory, args.page)
    result["requestId"] = args.request_id
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
