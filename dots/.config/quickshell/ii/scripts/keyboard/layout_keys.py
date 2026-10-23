#!/usr/bin/env python3
# Prints what each key of a keyboard layout types, as JSON, for the drawn keyboard in Settings → Keyboard:
#   {"keys": {"AD01": {"code": 24, "levels": ["й", "Й"]}, ...}}
# "code" is the XKB keycode (what Qt reports as a key event's nativeScanCode on Wayland).
# Usage: layout_keys.py <layout> [variant]. Results are cached in ~/.cache/quickshell/keyboard/.
import json
import os
import re
import subprocess
import sys

layout = sys.argv[1] if len(sys.argv) > 1 else "us"
variant = sys.argv[2] if len(sys.argv) > 2 else ""
if not re.fullmatch(r"[A-Za-z0-9_()-]+", layout) or (variant and not re.fullmatch(r"[A-Za-z0-9_()-]+", variant)):
    sys.exit("bad layout name")

cache_dir = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "quickshell", "keyboard")
cache = os.path.join(cache_dir, f"{layout}-{variant or 'standard'}.json")
if os.path.exists(cache):
    print(open(cache).read())
    sys.exit(0)

# The system's own tool; an `xkbcli` earlier in PATH (e.g. from conda) may lack compile-keymap
compiler = "/usr/lib/xkbcommon/xkbcli-compile-keymap"
command = [compiler] if os.path.exists(compiler) else ["xkbcli", "compile-keymap"]
command += ["--layout", layout] + (["--variant", variant] if variant else [])
keymap = subprocess.run(command, capture_output=True, text=True, check=True).stdout

# Keysym name -> character, from the comments in xkbcommon's header ("/* U+0439 CYRILLIC ... */")
symbols = {}
for line in open("/usr/include/xkbcommon/xkbcommon-keysyms.h", encoding="utf-8", errors="replace"):
    match = re.match(r"#define XKB_KEY_(\w+)\s+0x[0-9a-fA-F]+\s+/\*\s*U\+([0-9A-Fa-f]{4,6})", line)
    if match:
        symbols.setdefault(match.group(1), chr(int(match.group(2), 16)))

# Dead keys combine with the next key; show the accent they add
dead = {"dead_grave": "`", "dead_acute": "´", "dead_circumflex": "^", "dead_tilde": "~", "dead_diaeresis": "¨",
        "dead_cedilla": "¸", "dead_caron": "ˇ", "dead_breve": "˘", "dead_abovering": "˚", "dead_macron": "¯",
        "dead_doubleacute": "˝", "dead_ogonek": "˛", "dead_abovedot": "˙"}

def character(keysym):
    if keysym in symbols:
        return symbols[keysym]
    if keysym in dead:
        return dead[keysym]
    match = re.fullmatch(r"U([0-9A-Fa-f]{4,6})", keysym) # Unicode keysyms, e.g. U0451
    return chr(int(match.group(1), 16)) if match else ""

codes = {name: int(code) for name, code in re.findall(r"^\s*<(\w+)>\s*=\s*(\d+);", keymap, re.M)}
keys = {}
for name, body in re.findall(r"^\s*key <(\w+)>\s*\{(.*?)\};", keymap, re.M | re.S):
    group = re.search(r"\[([^\]]*)\]", body)
    if not group:
        continue
    levels = [character(keysym.strip()) for keysym in group.group(1).split(",")]
    keys[name] = {"code": codes.get(name, 0), "levels": levels}

result = json.dumps({"layout": layout, "variant": variant, "keys": keys}, ensure_ascii=False)
os.makedirs(cache_dir, exist_ok=True)
with open(cache + ".tmp", "w") as f:
    f.write(result)
os.replace(cache + ".tmp", cache)
print(result)
