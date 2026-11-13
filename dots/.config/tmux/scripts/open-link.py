#!/usr/bin/env python3
"""Open one clicked HTTP(S) link. tmux passes shell-quoted values, not code.

Each argument has a one-character tag so an empty format cannot disappear as
an empty shell argument. No tmux buffers, clipboard or adjacent-line guessing.
"""
import subprocess
import sys
import re
import unicodedata
from urllib.parse import urlsplit


def clicked_url(values):
    for value in values:
        value = value[1:]  # h = OSC 8 hyperlink, w = visible mouse word
        if not value or any(ord(char) < 32 or ord(char) == 127 for char in value):
            continue
        try:
            parsed = urlsplit(value)
            if parsed.scheme in ('http', 'https') and parsed.hostname:
                return value
        except ValueError:
            continue
    return None


def url_in_line(line, column):
    # mouse_x is window-relative; subtract pane_left. Combining and wide
    # characters before a URL must not shift the hit test's terminal columns.
    def cells(text):
        return sum(0 if unicodedata.combining(c) else
                   2 if unicodedata.east_asian_width(c) in ('W', 'F') else 1 for c in text)
    for match in re.finditer(r'https?://[^\s<>\"\x00-\x1f]+', line):
        url = match.group().rstrip('.,;!)]}')
        left = cells(line[:match.start()])
        if left <= column < left + cells(url):
            return clicked_url(['h' + url])
    return None


def main():
    args = {value[0]: value[1:] for value in sys.argv[1:] if value}
    url = clicked_url([key + args.get(key, '') for key in ('h', 'w')])
    if url is None:
        try:
            url = url_in_line(args.get('l', ''), int(args.get('x', '')) - int(args.get('p', '0')))
        except ValueError:
            pass
    if url is None:
        return 1
    try:
        subprocess.Popen(['xdg-open', url], stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
        # A recognized URL consumed the click even if the desktop opener failed.
        return 0
    except OSError:
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
