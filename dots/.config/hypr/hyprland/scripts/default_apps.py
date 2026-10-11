#!/usr/bin/env python3
"""Default apps: list, change and launch them, and ask which app opens a file type the first time.

Roles backed by MIME types (browser, file manager, images...) live in ~/.config/mimeapps.list, so every
app that opens links or files agrees with them. File types nobody picked an app for point to the
chooser (folis-open-with.desktop): it asks the shell which app to use and can remember the answer in
the same file. Roles without a MIME type (terminal, code editor) live in
~/.config/hypr/custom/default_apps.json; the terminal is also written to kdeglobals so Dolphin's
"Open Terminal" follows it.

  default_apps.py list [LANG]                  JSON with every role, its current app and the choices
  default_apps.py set ROLE DESKTOP_ID|ask      make an installed app the default, or ask every time
  default_apps.py set-command ROLE CMD [NAME]  use a command instead (terminal and code editor only)
  default_apps.py set-webmail SERVICE          web mail used when the email app is a browser
  default_apps.py launch ROLE                  start the default app for ROLE
  default_apps.py open DESKTOP_ID [URI...]     start an app by its desktop file id, optionally with files
  default_apps.py sync                         install the chooser and hand it every type without an app
  default_apps.py open-with URI...             run by the chooser: ask the shell which app opens these
  default_apps.py set-mime DESKTOP_ID TYPE...  remember an app for file types
  default_apps.py unset-mime TYPE...           ask again next time
  default_apps.py mailto URI                   open a mailto: link in the chosen web mail
  default_apps.py open-archive URI...          browse archives as folders in Dolphin
"""

import json
import os
import shlex
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ElementTree
from pathlib import Path
from urllib.parse import quote, unquote, urlparse

HOME = Path.home()
CONFIG_HOME = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config")
DATA_HOME = Path(os.environ.get("XDG_DATA_HOME") or HOME / ".local/share")
DATA_DIRS = [Path(p) for p in (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":") if p]
CONFIG_DIRS = [Path(p) for p in (os.environ.get("XDG_CONFIG_DIRS") or "/etc/xdg").split(":") if p]
DESKTOPS = [d.lower() for d in (os.environ.get("XDG_CURRENT_DESKTOP") or "").split(":") if d]
STORE = CONFIG_HOME / "hypr/custom/default_apps.json"
USER_MIMEAPPS = CONFIG_HOME / "mimeapps.list"
USER_APPS = DATA_HOME / "applications"
# Through ~/.config so the entries keep working wherever the dotfiles are checked out
SELF = CONFIG_HOME / "hypr/hyprland/scripts/default_apps.py"
QS_CONFIG = os.environ.get("QS_CONFIG_NAME") or "ii"

CHOOSER_ID = "folis-open-with.desktop"
WEBMAIL_ID = "folis-webmail.desktop"
ARCHIVE_ID = "folis-dolphin-archive.desktop"
OWN_IDS = {CHOOSER_ID, WEBMAIL_ID, ARCHIVE_ID}
# Shadowed with NoDisplay and no MimeType: the file manager is Dolphin
HIDDEN_APPS = ["org.gnome.Nautilus.desktop"]
GENERATED_MARK = "# Written by default_apps.py sync, changes are overwritten"

ROLES = {
    "browser": {
        "mimes": ["x-scheme-handler/https", "x-scheme-handler/http", "text/html", "application/xhtml+xml",
                  "x-scheme-handler/about", "x-scheme-handler/unknown"],
        "categories": ["WebBrowser"],
    },
    "mail": {
        "mimes": ["x-scheme-handler/mailto", "message/rfc822"],
        # Browsers can open mail links through a web mail service
        "categories": ["Email", "WebBrowser"],
        "match": "either",
    },
    "files": {
        "mimes": ["inode/directory"],
        "categories": ["FileManager"],
        "match": "categories",
    },
    "terminal": {
        "categories": ["TerminalEmulator"],
        "command": True,
    },
    "text": {
        "mimes": ["text/plain"],
        "categories": ["TextEditor"],
    },
    "code": {
        "categories": ["IDE", "TextEditor"],
        "command": True,
    },
    "images": {
        "mimes": ["image/png", "image/jpeg", "image/gif", "image/webp", "image/bmp", "image/tiff",
                  "image/avif", "image/heif", "image/svg+xml", "image/x-icon"],
        "categories": ["Viewer", "Photography", "RasterGraphics"],
    },
    "video": {
        "mimes": ["video/mp4", "video/x-matroska", "video/webm", "video/quicktime", "video/x-msvideo",
                  "video/mpeg", "video/ogg", "video/x-flv", "video/3gpp"],
        "categories": ["Video", "Player"],
    },
    "music": {
        "mimes": ["audio/mpeg", "audio/flac", "audio/x-flac", "audio/ogg", "audio/x-vorbis+ogg", "audio/opus",
                  "audio/wav", "audio/x-wav", "audio/mp4", "audio/aac", "audio/x-m4a", "audio/webm"],
        "categories": ["Audio", "Music", "Player"],
    },
    "pdf": {
        "mimes": ["application/pdf"],
        "categories": ["Viewer", "Office"],
    },
    "documents": {
        "mimes": ["application/vnd.oasis.opendocument.text",
                  "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                  "application/msword", "application/rtf"],
        "categories": ["WordProcessor", "Office"],
    },
    "spreadsheets": {
        "mimes": ["application/vnd.oasis.opendocument.spreadsheet",
                  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                  "application/vnd.ms-excel"],
        "categories": ["Spreadsheet", "Office"],
    },
    "presentations": {
        "mimes": ["application/vnd.oasis.opendocument.presentation",
                  "application/vnd.openxmlformats-officedocument.presentationml.presentation",
                  "application/vnd.ms-powerpoint"],
        "categories": ["Presentation", "Office"],
    },
    "archives": {
        "mimes": ["application/zip", "application/x-7z-compressed", "application/vnd.rar", "application/x-rar",
                  "application/x-tar", "application/gzip", "application/x-compressed-tar",
                  "application/x-bzip2-compressed-tar", "application/x-xz-compressed-tar",
                  "application/x-zstd-compressed-tar", "application/zstd"],
        "categories": ["Archiving", "Compression"],
    },
}

# Archives Dolphin can browse, and the KIO protocol (kio-extras) that reads each
ARCHIVE_PROTOCOLS = {
    "application/zip": "zip",
    "application/x-7z-compressed": "sevenz",
    "application/x-tar": "tar",
    "application/x-compressed-tar": "tar",
    "application/x-bzip2-compressed-tar": "tar",
    "application/x-xz-compressed-tar": "tar",
    "application/x-zstd-compressed-tar": "tar",
    "application/x-lzma-compressed-tar": "tar",
}

WEBMAIL = {
    "gmail": {"name": "Gmail", "home": "https://mail.google.com/",
              "compose": "https://mail.google.com/mail/?extsrc=mailto&url={uri}"},
    "outlook": {"name": "Outlook", "home": "https://outlook.live.com/mail/",
                "compose": "https://outlook.live.com/mail/deeplink/compose?mailtouri={uri}"},
    "yandex": {"name": "Yandex", "home": "https://mail.yandex.ru/",
               "compose": "https://mail.yandex.ru/compose?mailto={uri}"},
    "proton": {"name": "Proton Mail", "home": "https://mail.proton.me/",
               "compose": "https://mail.proton.me/inbox/#mailto={uri}"},
}

# Apps a fresh setup starts with: the first one installed wins. Only roles still without an app.
SEED = {
    "browser": ["brave-browser.desktop", "firefox.desktop", "chromium.desktop", "org.gnome.Epiphany.desktop"],
    "files": ["org.kde.dolphin.desktop"],
    "text": ["org.kde.kate.desktop", "org.gnome.TextEditor.desktop", "org.kde.kwrite.desktop"],
    "images": ["org.gnome.Loupe.desktop", "org.kde.gwenview.desktop", "imv.desktop"],
    "video": ["org.gnome.Showtime.desktop", "mpv.desktop", "vlc.desktop", "org.kde.haruna.desktop"],
    "music": ["org.gnome.Decibels.desktop", "org.kde.elisa.desktop", "vlc.desktop"],
    "pdf": ["org.gnome.Papers.desktop", "org.kde.okular.desktop", "org.gnome.Evince.desktop"],
    "documents": ["libreoffice-writer.desktop"],
    "spreadsheets": ["libreoffice-calc.desktop"],
    "presentations": ["libreoffice-impress.desktop"],
    "archives": [ARCHIVE_ID],
}
SEED_WEBMAIL = "gmail"


def localized(entry, key):
    lang = (os.environ.get("LC_MESSAGES") or os.environ.get("LANG") or "").split(".")[0]
    for candidate in (f"{key}[{lang}]", f"{key}[{lang.split('_')[0]}]", key):
        if entry.get(candidate):
            return entry[candidate]
    return ""


def parse_desktop_file(path):
    entry = {}
    in_main = False
    try:
        with open(path, encoding="utf-8", errors="replace") as file:
            for line in file:
                line = line.strip()
                if line.startswith("["):
                    in_main = line == "[Desktop Entry]"
                    continue
                if in_main and "=" in line and not line.startswith("#"):
                    key, value = line.split("=", 1)
                    entry[key.strip()] = value.strip()
    except OSError:
        return None
    return entry


def split_list(value):
    return [item for item in (value or "").split(";") if item]


def installed_apps():
    """Desktop id -> app info. Earlier directories win, like everywhere else."""
    apps = {}
    for base in [DATA_HOME] + DATA_DIRS:
        root = base / "applications"
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*.desktop")):
            app_id = str(path.relative_to(root)).replace("/", "-")
            if app_id in apps:
                continue
            entry = parse_desktop_file(path)
            if entry is None:
                continue
            apps[app_id] = None  # Shadowed entries further down must stay hidden
            if entry.get("Type", "Application") != "Application" or entry.get("Hidden") == "true":
                continue
            try_exec = entry.get("TryExec")
            if try_exec and not (shutil.which(os.path.expanduser(try_exec)) or Path(os.path.expanduser(try_exec)).is_file()):
                continue
            apps[app_id] = {
                "id": app_id,
                "path": str(path),
                "name": localized(entry, "Name") or app_id.removesuffix(".desktop"),
                "comment": localized(entry, "GenericName") or localized(entry, "Comment"),
                "icon": entry.get("Icon", ""),
                "exec": entry.get("Exec", ""),
                "terminal": entry.get("Terminal") == "true",
                "mimes": set(split_list(entry.get("MimeType"))),
                "categories": set(split_list(entry.get("Categories"))),
                "hidden": entry.get("NoDisplay") == "true",
            }
    return {app_id: app for app_id, app in apps.items() if app}


def choosable(app):
    """Shown in lists: visible apps and our own handlers, never the chooser itself."""
    return app["id"] != CHOOSER_ID and app["id"] != WEBMAIL_ID and (not app["hidden"] or app["id"] in OWN_IDS)


# MIME database -------------------------------------------------------------------------------------

def mime_dirs():
    return [base / "mime" for base in [DATA_HOME] + DATA_DIRS if (base / "mime").is_dir()]


def read_pairs(name):
    pairs = []
    for directory in mime_dirs():
        try:
            for line in (directory / name).read_text(encoding="utf-8").splitlines():
                parts = line.split()
                if len(parts) == 2:
                    pairs.append(parts)
        except OSError:
            pass
    return pairs


_aliases = None
_parents = None


def canonical(mime):
    global _aliases
    if _aliases is None:
        _aliases = {alias: target for alias, target in read_pairs("aliases")}
    return _aliases.get(mime, mime)


def aliases_of(mime):
    canonical(mime)
    return {alias for alias, target in _aliases.items() if target == mime}


def ancestors(mime):
    """The type, its aliases and every type it is a kind of (text/markdown -> text/plain), nearest first."""
    global _parents
    if _parents is None:
        _parents = {}
        for child, parent in read_pairs("subclasses"):
            _parents.setdefault(child, []).append(parent)
    mime = canonical(mime)
    order = [mime]
    index = 0
    while index < len(order):
        current = order[index]
        index += 1
        parents = list(_parents.get(current, []))
        if current.startswith("text/") and current != "text/plain":
            parents.append("text/plain")
        for parent in parents:
            parent = canonical(parent)
            if parent not in order:
                order.append(parent)
    result = []
    for item in order:
        result.append(item)
        result.extend(sorted(aliases_of(item)))
    return result


def all_types():
    types = set()
    for directory in mime_dirs():
        try:
            types.update(line.strip() for line in (directory / "types").read_text(encoding="utf-8").splitlines())
        except OSError:
            pass
    # Removable media and special files aren't opened by double-clicking
    return sorted(t for t in types if t and not t.startswith(("inode/", "x-content/", "all/")))


def mime_info(mime, lang=""):
    """{"description", "patterns"} from the shared MIME database, in the UI language when it has one."""
    xml_lang = "{http://www.w3.org/XML/1998/namespace}lang"
    wanted = [lang.replace("_", "-"), lang.split("_")[0]] if lang else []
    for directory in mime_dirs():
        path = directory / f"{canonical(mime)}.xml"
        if not path.is_file():
            continue
        try:
            root = ElementTree.parse(path).getroot()
        except (OSError, ElementTree.ParseError):
            continue
        namespace = "{http://www.freedesktop.org/standards/shared-mime-info}"
        comments = {c.get(xml_lang, ""): (c.text or "") for c in root.findall(f"{namespace}comment")}
        description = next((comments[l] for l in wanted if l in comments), comments.get("", ""))
        patterns = [g.get("pattern", "") for g in root.findall(f"{namespace}glob")]
        return {"description": description, "patterns": [p for p in patterns if p]}
    return {"description": "", "patterns": []}


def file_types(uri):
    """MIME types of a file: shared-mime-info's first, then file(1)'s when it differs (xdg-open uses that)."""
    parsed = urlparse(uri)
    if parsed.scheme and parsed.scheme != "file" and len(parsed.scheme) > 1:
        return [f"x-scheme-handler/{parsed.scheme.lower()}"]
    path = unquote(parsed.path) if parsed.scheme == "file" else uri
    types = []
    try:
        result = subprocess.run(["gio", "info", "-a", "standard::content-type", path],
                                capture_output=True, text=True, timeout=5)
        for line in result.stdout.splitlines():
            if "standard::content-type:" in line:
                types.append(line.split(":", 3)[-1].strip())
    except (OSError, subprocess.TimeoutExpired):
        pass
    try:
        result = subprocess.run(["xdg-mime", "query", "filetype", path], capture_output=True, text=True, timeout=5)
        other = result.stdout.strip().split(";")[0]
        if other and other not in types:
            types.append(other)
    except (OSError, subprocess.TimeoutExpired):
        pass
    return types or ["application/octet-stream"]


# mimeapps.list -------------------------------------------------------------------------------------

def mimeapps_files():
    files = []
    for directory in [CONFIG_HOME] + CONFIG_DIRS:
        files += [directory / f"{desktop}-mimeapps.list" for desktop in DESKTOPS] + [directory / "mimeapps.list"]
    for directory in [DATA_HOME] + DATA_DIRS:
        files += [directory / "applications" / f"{desktop}-mimeapps.list" for desktop in DESKTOPS]
        files += [directory / "applications/mimeapps.list", directory / "applications/defaults.list"]
    return files


def read_ini(path):
    """Sections as ordered lists of raw lines, so rewriting keeps everything else intact."""
    sections = [("", [])]
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return sections
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            sections.append((stripped[1:-1], []))
        else:
            sections[-1][1].append(line)
    return sections


def ini_get(sections, section, key):
    for name, lines in sections:
        if name != section:
            continue
        for line in lines:
            if "=" in line and line.split("=", 1)[0].strip() == key:
                return line.split("=", 1)[1].strip()
    return None


def ini_keys(sections, section):
    return {line.split("=", 1)[0].strip(): line.split("=", 1)[1].strip()
            for name, lines in sections if name == section
            for line in lines if "=" in line and not line.lstrip().startswith("#")}


def default_for_mime(mime, apps):
    for path in mimeapps_files():
        if not path.is_file():
            continue
        value = ini_get(read_ini(path), "Default Applications", mime)
        for app_id in split_list(value):
            if app_id in apps:
                return app_id
    # Nothing explicit: ask xdg-mime, which also knows the MIME cache order
    try:
        result = subprocess.run(["xdg-mime", "query", "default", mime], capture_output=True, text=True, timeout=5)
        app_id = result.stdout.strip()
        return app_id if app_id in apps else None
    except (OSError, subprocess.TimeoutExpired):
        return None


def update_mimeapps(path, defaults, associate=True):
    """Set [Default Applications] mime=app for each pair; with `associate` also put the app first in
    [Added Associations], so it shows up for the type even if its desktop file doesn't list it."""
    sections = read_ini(path)
    wanted = ["Default Applications"] + (["Added Associations"] if associate else [])
    names = [name for name, _ in sections]
    for section in wanted:
        if section not in names:
            sections.append((section, []))
            names.append(section)
    changed = False
    for name, lines in sections:
        if name not in wanted:
            continue
        existing = {}
        for index, line in enumerate(lines):
            if "=" in line:
                existing[line.split("=", 1)[0].strip()] = index
        additions = []
        for mime, app_id in defaults.items():
            if name == "Default Applications":
                value = f"{mime}={app_id}"
            else:
                old = split_list(lines[existing[mime]].split("=", 1)[1]) if mime in existing else []
                value = f"{mime}=" + ";".join([app_id] + [item for item in old if item != app_id]) + ";"
            if mime in existing:
                if lines[existing[mime]] != value:
                    lines[existing[mime]] = value
                    changed = True
            else:
                additions.append(value)
        if additions:
            # Keep new keys above trailing blank lines
            position = len(lines)
            while position > 0 and not lines[position - 1].strip():
                position -= 1
            lines[position:position] = additions
            changed = True
    if not changed:
        return
    out = []
    for name, lines in sections:
        if name:
            if out and out[-1].strip():
                out.append("")
            out.append(f"[{name}]")
        out.extend(lines)
    write_text(path, "\n".join(out).strip("\n") + "\n")


def write_text(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name + ".tmp")
    temp.write_text(text, encoding="utf-8")
    temp.replace(path)


def user_mimeapps_targets():
    targets = [USER_MIMEAPPS]
    targets += [CONFIG_HOME / f"{desktop}-mimeapps.list" for desktop in DESKTOPS
                if (CONFIG_HOME / f"{desktop}-mimeapps.list").is_file()]
    return targets


def set_mime_defaults(defaults, associate=True):
    for path in user_mimeapps_targets():
        update_mimeapps(path, defaults, associate)


# Store -----------------------------------------------------------------------------------------------

def read_store():
    try:
        return json.loads(STORE.read_text())
    except (OSError, ValueError):
        return {}


def write_store(store):
    write_text(STORE, json.dumps(store, indent=4, ensure_ascii=False) + "\n")


def kde_terminal():
    if not shutil.which("kreadconfig6"):
        return None, None
    def read(key):
        result = subprocess.run(["kreadconfig6", "--file", "kdeglobals", "--group", "General", "--key", key],
                                capture_output=True, text=True)
        return result.stdout.strip() or None
    return read("TerminalService"), read("TerminalApplication")


# Roles -----------------------------------------------------------------------------------------------

def supports(app, mime):
    return bool(app["mimes"] & set(ancestors(mime)))


def candidates_for(role, apps):
    spec = ROLES[role]
    mimes = set(spec.get("mimes", []))
    categories = set(spec.get("categories", []))
    match = spec.get("match", "mimes" if mimes else "categories")
    found = []
    for app in apps.values():
        if not choosable(app):
            continue
        by_mime = bool(app["mimes"] & mimes)
        by_category = bool(app["categories"] & categories)
        if match == "mimes" and by_mime or match == "categories" and by_category or match == "either" and (by_mime or by_category):
            found.append(app)
    # Apps made for the job first (categories are listed by importance), then the ones
    # that open the most of the role's file types, then by name
    order = spec.get("categories", [])
    def rank(app):
        category = min((order.index(c) for c in app["categories"] & categories), default=len(order))
        return (category, -len(app["mimes"] & mimes), app["name"].lower())
    found.sort(key=rank)
    return found


def is_browser(app):
    return bool(app and "WebBrowser" in app["categories"])


def current_for(role, apps):
    """{"app": id} or {"command": cmd, "name": ...} or {"ask": True} or {}"""
    spec = ROLES[role]
    if spec.get("mimes"):
        app_id = default_for_mime(spec["mimes"][0], apps)
        if app_id == CHOOSER_ID:
            return {"ask": True}
        if app_id == WEBMAIL_ID:
            mail = read_store().get("mail") or {}
            if mail.get("browser") in apps:
                return {"app": mail["browser"], "webmail": mail.get("webmail") or SEED_WEBMAIL}
            return {}
        return {"app": app_id} if app_id else {}
    stored = read_store().get(role) or {}
    if stored.get("app") in apps or stored.get("command"):
        return stored
    if role == "terminal":
        service, command = kde_terminal()
        if service in apps:
            return {"app": service}
        if command:
            return {"command": command}
    candidates = candidates_for(role, apps)
    return {"app": candidates[0]["id"]} if candidates else {}


def public(app):
    return {key: app[key] for key in ("id", "name", "comment", "icon")}


def remembered_types(apps, lang):
    """File types the user picked an app for that aren't part of a role."""
    role_mimes = {mime for spec in ROLES.values() for mime in spec.get("mimes", [])}
    defaults = ini_keys(read_ini(USER_MIMEAPPS), "Default Applications")
    types = []
    for mime, value in defaults.items():
        if mime in role_mimes or mime.startswith(("x-scheme-handler/", "inode/")):
            continue
        app_id = next((item for item in split_list(value) if item in apps), None)
        if not app_id or app_id == CHOOSER_ID:
            continue
        info = mime_info(mime, lang)
        types.append({"mime": mime, "description": info["description"] or mime,
                      "patterns": info["patterns"][:3], "app": public(apps[app_id])})
    types.sort(key=lambda item: item["description"].lower())
    return types


def cmd_list(lang=""):
    apps = installed_apps()
    roles = []
    for role, spec in ROLES.items():
        current = current_for(role, apps)
        candidates = candidates_for(role, apps)
        if current.get("app") and current["app"] not in [app["id"] for app in candidates]:
            candidates.insert(0, apps[current["app"]])
        entry = dict(current)
        if current.get("app"):
            entry["app"] = public(apps[current["app"]])
        roles.append({
            "id": role,
            "current": entry,
            "candidates": [public(app) for app in candidates],
            "allowsCommand": bool(spec.get("command")),
            "allowsAsk": bool(spec.get("mimes")) and role not in ("browser", "files"),
        })
    print(json.dumps({
        "roles": roles,
        "apps": [public(app) for app in sorted(apps.values(), key=lambda a: a["name"].lower())
                 if choosable(app) and app["id"] not in OWN_IDS],
        "webmail": [{"id": key, "name": value["name"]} for key, value in WEBMAIL.items()],
        "types": remembered_types(apps, lang),
    }, ensure_ascii=False))


def set_kde_terminal(service, command):
    if not shutil.which("kwriteconfig6"):
        return
    base = ["kwriteconfig6", "--file", "kdeglobals", "--group", "General", "--key"]
    subprocess.run(base + ["TerminalApplication", command])
    if service:
        subprocess.run(base + ["TerminalService", service])
    else:
        subprocess.run(base + ["TerminalService", "--delete"])


def exec_program(app):
    try:
        parts = shlex.split(app["exec"])
    except ValueError:
        return app["exec"].split(" ")[0]
    return parts[0] if parts else ""


def set_role_app(role, app_id, apps):
    spec = ROLES[role]
    if spec.get("mimes"):
        if app_id == "ask":
            set_mime_defaults({mime: CHOOSER_ID for mime in spec["mimes"]}, associate=False)
            return
        app = apps[app_id]
        if role == "mail" and is_browser(app) and not (app["mimes"] & set(spec["mimes"])):
            store = read_store()
            store["mail"] = {"browser": app_id, "webmail": (store.get("mail") or {}).get("webmail") or SEED_WEBMAIL}
            write_store(store)
            write_own_entries()
            set_mime_defaults({"x-scheme-handler/mailto": WEBMAIL_ID})
            return
        # Only the types the app can open; all of them when it doesn't say (picked from all apps)
        mimes = [mime for mime in spec["mimes"] if supports(app, mime)] or spec["mimes"]
        set_mime_defaults({mime: app_id for mime in mimes})
        return
    store = read_store()
    store[role] = {"app": app_id}
    write_store(store)
    if role == "terminal":
        set_kde_terminal(app_id, exec_program(apps[app_id]))


def cmd_set(role, app_id):
    apps = installed_apps()
    if role not in ROLES or (app_id != "ask" and app_id not in apps):
        sys.exit(f"Unknown role or app: {role} {app_id}")
    set_role_app(role, app_id, apps)


def cmd_set_command(role, command, name=""):
    if not ROLES.get(role, {}).get("command") or not command.strip():
        sys.exit(f"{role} can't use a command")
    store = read_store()
    store[role] = {"command": command.strip(), **({"name": name} if name else {})}
    write_store(store)
    if role == "terminal":
        set_kde_terminal(None, command.strip())


def cmd_set_webmail(service):
    if service not in WEBMAIL:
        sys.exit(f"Unknown web mail service: {service}")
    store = read_store()
    store["mail"] = dict(store.get("mail") or {}, webmail=service)
    write_store(store)


# Launching -------------------------------------------------------------------------------------------

def spawn(args, shell=False):
    subprocess.Popen(args, shell=shell, start_new_session=True, stdin=subprocess.DEVNULL,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, cwd=HOME)


def to_path(uri):
    parsed = urlparse(uri)
    return unquote(parsed.path) if parsed.scheme == "file" else uri


def expand_exec(app, uris):
    """Command lines for the app's Exec with field codes filled in; one per file for %f/%u apps."""
    try:
        parts = shlex.split(app["exec"])
    except ValueError:
        parts = app["exec"].split()
    codes = {code for part in parts for code in ("%f", "%F", "%u", "%U") if code in part}
    single = bool(codes & {"%f", "%u"}) and not codes & {"%F", "%U"}
    groups = [[uri] for uri in uris] if single and len(uris) > 1 else [uris]
    commands = []
    for group in groups:
        command = []
        for part in parts:
            if part in ("%F", "%U"):
                command += [to_path(u) for u in group] if part == "%F" else group
                continue
            if part == "%i":
                command += ["--icon", app["icon"]] if app["icon"] else []
                continue
            part = part.replace("%f", to_path(group[0]) if group else "").replace("%u", group[0] if group else "")
            part = part.replace("%c", app["name"]).replace("%k", app["path"])
            for code in ("%d", "%D", "%n", "%N", "%v", "%m"):
                part = part.replace(code, "")
            part = part.replace("%%", "%")
            if part:
                command.append(part)
        if not codes and group:
            command += group
        commands.append(command)
    return commands


def open_app(app_id, uris=None, apps=None):
    apps = apps or installed_apps()
    app = apps.get(app_id) or apps.get(f"{app_id}.desktop")
    if not app:
        sys.exit(f"No such app: {app_id}")
    uris = uris or []
    local = all(urlparse(uri).scheme in ("", "file") for uri in uris)
    if shutil.which("gio") and (local or app["terminal"]):
        # gio also handles terminal apps, D-Bus activation and startup notification
        spawn(["gio", "launch", app["path"], *[to_path(uri) for uri in uris]])
        return
    for command in expand_exec(app, uris):
        spawn(command)


def cmd_launch(role):
    if role not in ROLES:
        sys.exit(f"Unknown role: {role}")
    apps = installed_apps()
    current = current_for(role, apps)
    if current.get("command"):
        spawn(current["command"], shell=True)
    elif current.get("webmail"):
        open_app(current["app"], [WEBMAIL[current["webmail"]]["home"]], apps)
    elif current.get("app"):
        open_app(current["app"], apps=apps)
    else:
        subprocess.run(["notify-send", "-a", "Default apps", "No default app",
                        f"Pick one for “{role}” in Settings > Default Apps"])


def cmd_mailto(uri):
    apps = installed_apps()
    mail = read_store().get("mail") or {}
    browser = mail.get("browser")
    if browser not in apps:
        browser = default_for_mime("x-scheme-handler/https", apps)
    service = WEBMAIL.get(mail.get("webmail") or SEED_WEBMAIL, WEBMAIL[SEED_WEBMAIL])
    url = service["compose"].format(uri=quote(uri, safe="")) if uri.startswith("mailto:") else service["home"]
    if browser in apps:
        open_app(browser, [url], apps)
    else:
        spawn(["xdg-open", url])


def cmd_open_archive(uris):
    for uri in uris:
        path = to_path(uri)
        protocol = next((ARCHIVE_PROTOCOLS[t] for t in file_types(uri) if t in ARCHIVE_PROTOCOLS), None)
        target = f"{protocol}:{quote(path)}/" if protocol else str(Path(path).parent)
        spawn(["dolphin", target])


# The chooser -------------------------------------------------------------------------------------------

def describe(uris, apps, lang=""):
    """What the chooser shows for files that share their first type."""
    types = []
    for uri in uris:
        for mime in file_types(uri):
            if mime not in types:
                types.append(mime)
    primary = types[0]
    lineage = []
    for mime in types:
        lineage += [item for item in ancestors(mime) if item not in lineage]
    def closeness(app):
        return min((lineage.index(mime) for mime in app["mimes"] if mime in lineage), default=len(lineage))
    recommended = [app for app in apps.values() if choosable(app) and app["mimes"] & set(lineage)]
    # Apps that open everything (application/octet-stream) come last
    recommended.sort(key=lambda app: (closeness(app), app["name"].lower()))
    others = sorted((app for app in apps.values() if choosable(app) and app["id"] not in OWN_IDS
                     and app not in recommended), key=lambda app: app["name"].lower())
    info = mime_info(primary, lang)
    name = Path(to_path(uris[0])).name or uris[0]
    suffix = Path(name).suffix
    return {
        "uris": uris,
        "name": name if len(uris) == 1 else f"{name} (+{len(uris) - 1})",
        "extension": suffix.lower() if suffix and len(suffix) <= 12 else "",
        "types": types,
        "description": info["description"] or primary,
        "recommended": [public(app) for app in recommended],
        "others": [public(app) for app in others],
    }


def shell_language():
    try:
        config = json.loads((CONFIG_HOME / "illogical-impulse/config.json").read_text())
        language = config.get("language", {}).get("ui", "auto")
        if language and language != "auto":
            return language
    except (OSError, ValueError):
        pass
    return (os.environ.get("LANG") or "").split(".")[0]


def cmd_open_with(uris):
    apps = installed_apps()
    lang = shell_language()
    # Files of one type go together, like the file manager handed them over
    groups = {}
    for uri in uris:
        groups.setdefault(file_types(uri)[0], []).append(uri)
    for group in groups.values():
        request = describe(group, apps, lang)
        if len(request["recommended"]) == 1:
            open_app(request["recommended"][0]["id"], group, apps)
            continue
        try:
            result = subprocess.run(["qs", "-c", QS_CONFIG, "ipc", "call", "openWith", "ask",
                                     json.dumps(request, ensure_ascii=False)],
                                    capture_output=True, text=True, timeout=5)
            if result.returncode == 0:
                continue
        except (OSError, subprocess.TimeoutExpired):
            pass
        # The shell isn't running: open with the best match instead of doing nothing
        if request["recommended"]:
            open_app(request["recommended"][0]["id"], group, apps)
        else:
            subprocess.run(["notify-send", "-a", "Default apps", "No app can open this file", request["name"]])


def cmd_set_mime(app_id, mimes):
    if app_id not in installed_apps():
        sys.exit(f"No such app: {app_id}")
    set_mime_defaults({mime: app_id for mime in mimes})


def cmd_unset_mime(mimes):
    set_mime_defaults({mime: CHOOSER_ID for mime in mimes}, associate=False)


# Setup -----------------------------------------------------------------------------------------------

def desktop_entry(lines):
    return "\n".join([GENERATED_MARK, "[Desktop Entry]", *lines]) + "\n"


def write_if_changed(path, text):
    try:
        if path.read_text(encoding="utf-8") == text:
            return False
    except OSError:
        pass
    write_text(path, text)
    return True


def desktop_quote(arg):
    """Exec= quoting from the desktop entry spec: double quotes, with \\ \" ` $ escaped."""
    if not any(c in arg for c in " \t\n\"'\\><~|&;$*?#()`"):
        return arg
    return '"' + "".join("\\" + c if c in '"`$\\' else c for c in arg) + '"'


def write_own_entries():
    command = desktop_quote(str(SELF))
    changed = write_if_changed(USER_APPS / CHOOSER_ID, desktop_entry([
        "Type=Application",
        "Name=Choose an app",
        "Name[ru]=Выбрать приложение",
        "Comment=Asks which app should open the file",
        "Comment[ru]=Спрашивает, каким приложением открыть файл",
        "Icon=document-open",
        f"Exec={command} open-with %U",
        "NoDisplay=true",
        "Terminal=false",
    ]))
    changed |= write_if_changed(USER_APPS / WEBMAIL_ID, desktop_entry([
        "Type=Application",
        "Name=Web mail",
        "Name[ru]=Веб-почта",
        "Comment=Opens email links in the web mail chosen in Settings",
        "Icon=internet-mail",
        f"Exec={command} mailto %u",
        "MimeType=x-scheme-handler/mailto;",
        "NoDisplay=true",
        "Terminal=false",
    ]))
    if shutil.which("dolphin"):
        changed |= write_if_changed(USER_APPS / ARCHIVE_ID, desktop_entry([
            "Type=Application",
            "Name=Dolphin",
            "GenericName=Opens archives as folders",
            "GenericName[ru]=Открывает архивы как папки",
            "Icon=org.kde.dolphin",
            f"Exec={command} open-archive %U",
            "MimeType=" + ";".join(ARCHIVE_PROTOCOLS) + ";",
            "NoDisplay=true",
            "Terminal=false",
        ]))
    for app_id in HIDDEN_APPS:
        changed |= hide_app(app_id)
    return changed


def hide_app(app_id):
    """A copy of the system entry that stays out of menus and doesn't claim any file types."""
    target = USER_APPS / app_id
    if target.is_file() and not target.read_text(encoding="utf-8", errors="replace").startswith(GENERATED_MARK):
        return False  # The user's own override wins
    source = next((base / "applications" / app_id for base in DATA_DIRS
                   if (base / "applications" / app_id).is_file()), None)
    if source is None:
        if target.is_file():
            target.unlink()
            return True
        return False
    lines = [GENERATED_MARK]
    in_main = False
    for line in source.read_text(encoding="utf-8", errors="replace").splitlines():
        stripped = line.strip()
        if stripped.startswith("["):
            if in_main:
                lines.append("NoDisplay=true")
            in_main = stripped == "[Desktop Entry]"
        elif in_main and stripped.split("=", 1)[0].strip() in ("NoDisplay", "MimeType"):
            continue
        lines.append(line)
    if in_main:
        lines.append("NoDisplay=true")
    return write_if_changed(target, "\n".join(lines) + "\n")


def seed(apps):
    store = read_store()
    if store.get("seeded"):
        return
    explicit = ini_keys(read_ini(USER_MIMEAPPS), "Default Applications")
    def unset(role):
        first = ROLES[role]["mimes"][0]
        return first not in explicit or explicit[first] == CHOOSER_ID
    for role, choices in SEED.items():
        app_id = next((choice for choice in choices if choice in apps), None)
        if app_id and unset(role):
            set_role_app(role, app_id, apps)
    if unset("mail"):
        browser = default_for_mime("x-scheme-handler/https", apps)
        if browser in apps and is_browser(apps[browser]):
            set_role_app("mail", browser, apps)
    if shutil.which("kwriteconfig6"):
        subprocess.run(["kwriteconfig6", "--file", "dolphinrc", "--group", "General",
                        "--key", "BrowseThroughArchives", "true"])
    store = read_store()
    store["seeded"] = True
    write_store(store)


def cmd_sync():
    changed = write_own_entries()
    if changed and shutil.which("update-desktop-database"):
        subprocess.run(["update-desktop-database", str(USER_APPS)], stderr=subprocess.DEVNULL)
    apps = installed_apps()
    seed(apps)
    # Every type that still has no app goes to the chooser
    explicit = ini_keys(read_ini(USER_MIMEAPPS), "Default Applications")
    missing = {mime: CHOOSER_ID for mime in all_types() if mime not in explicit}
    if missing:
        update_mimeapps(USER_MIMEAPPS, missing, associate=False)
    if (changed or missing) and shutil.which("kbuildsycoca6"):
        subprocess.run(["kbuildsycoca6"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    args = sys.argv[1:]
    command = args[0] if args else ""
    if command == "list" and len(args) <= 2:
        cmd_list(args[1] if len(args) == 2 else "")
    elif command == "set" and len(args) == 3:
        cmd_set(args[1], args[2])
    elif command == "set-command" and len(args) in (3, 4):
        cmd_set_command(*args[1:])
    elif command == "set-webmail" and len(args) == 2:
        cmd_set_webmail(args[1])
    elif command == "launch" and len(args) == 2:
        cmd_launch(args[1])
    elif command == "open" and len(args) >= 2:
        open_app(args[1], args[2:])
    elif command == "sync" and len(args) == 1:
        cmd_sync()
    elif command == "open-with" and len(args) >= 2:
        cmd_open_with(args[1:])
    elif command == "set-mime" and len(args) >= 3:
        cmd_set_mime(args[1], args[2:])
    elif command == "unset-mime" and len(args) >= 2:
        cmd_unset_mime(args[1:])
    elif command == "mailto" and len(args) <= 2:
        cmd_mailto(args[1] if len(args) == 2 else "")
    elif command == "open-archive" and len(args) >= 2:
        cmd_open_archive(args[1:])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
