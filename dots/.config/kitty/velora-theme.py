"""Kitty runs Python genincludes in-process at startup and on config reload."""
import os
from pathlib import Path
import re

from kitty.options.types import all_colors

state = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")
try:
    with (state / "quickshell/user/generated/terminal/kitty-theme.conf").open() as theme:
        for line in theme:
            fields = line.split()
            if len(fields) == 2 and fields[0] in all_colors and re.fullmatch(r"#[0-9a-fA-F]{6}", fields[1]):
                print(*fields)
except FileNotFoundError:
    pass
