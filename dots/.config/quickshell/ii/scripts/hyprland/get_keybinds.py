#!/usr/bin/env python3
"""Read annotated Lua keybinds for the existing Quickshell cheatsheet."""

import argparse
import json
import re
from pathlib import Path

BIND = re.compile(r'^\s*bind\("([^"]*)",\s*"([^"]*)",')
HEADING = re.compile(r'^\s*--\s*([\w /+()-]+)\.\s*$')
INLINE_COMMENT = re.compile(r'\)\s*--\s*(.+)$')
DESCRIPTION = re.compile(r'description\s*=\s*"([^"]+)"')


def read_bindings(path):
    lines = path.read_text().splitlines()
    sections = []
    name = "Keybinds"
    bindings = []
    seen = set()

    def finish_section():
        nonlocal bindings
        if bindings:
            sections.append({"name": name, "keybinds": bindings})
            bindings = []

    for index, line in enumerate(lines):
        heading = HEADING.match(line)
        if heading:
            finish_section()
            name = heading.group(1)
            continue
        match = BIND.match(line)
        if not match:
            continue
        mods, key = match.groups()
        comment = INLINE_COMMENT.search(line)
        description = comment.group(1).strip() if comment else ""
        if not description:
            for next_line in lines[index + 1:index + 9]:
                if BIND.match(next_line):
                    break
                option = DESCRIPTION.search(next_line)
                if option:
                    description = option.group(1)
                    break
                comment = INLINE_COMMENT.search(next_line)
                if comment and "[hidden]" in comment.group(1):
                    description = "[hidden]"
                    break
        if not description or "[hidden]" in description:
            continue
        modifiers = [part.strip().capitalize() for part in mods.split("+") if part.strip()]
        identity = (tuple(modifiers), key, description)
        if identity in seen:
            continue
        seen.add(identity)
        bindings.append({"mods": modifiers, "key": key, "dispatcher": "", "params": "", "comment": description})

    finish_section()
    columns = [{"children": []} for _ in range(min(4, len(sections)))]
    for index, section in enumerate(sections):
        columns[index % len(columns)]["children"].append(section)
    return {"children": columns}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--path", required=True)
    args = parser.parse_args()
    path = Path(args.path).expanduser()
    result = read_bindings(path) if path.is_file() else {"children": []}
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
