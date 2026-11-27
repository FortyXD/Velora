"""Manage Velora's proxy VPN profiles. Requests and replies each occupy one line of JSON."""
import fcntl
from http.client import HTTPException
import ipaddress
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import sys
import tempfile
import time
from urllib.error import URLError
from urllib.parse import quote, unquote, urldefrag, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener
from uuid import uuid4

from vpn_profiles import MAX_BYTES, ProfileError, decode64, digest, label, read_servers


ENGINE = Path("/usr/bin/sing-box")
UNIT = f"velora-vpn-{os.getuid()}.service"
INTERFACE = f"vlvpn{os.getuid():x}"
STORE = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share") / "velora/vpn"
RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}") / "velora-vpn"
BUS_ERROR = "Cannot reach the system service manager."
START_ERROR = "Could not start the VPN tunnel. Check system authorization and TUN availability."
STOP_FIRST = "Disconnect the current VPN first."


def write_private(path, data):
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as file:
        try:
            json.dump(data, file, ensure_ascii=False)
            file.flush()
            os.fsync(file.fileno())
            os.replace(file.name, path)
        finally:
            Path(file.name).unlink(missing_ok=True)


def load():
    try:
        return json.loads((STORE / "profiles.json").read_text())
    except FileNotFoundError:
        return {}


def bounded_read(stream):
    data = stream.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES:
        raise ProfileError("The subscription is too large.")
    return data


class SubscriptionRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        scheme = urlsplit(newurl).scheme
        if scheme not in ("http", "https") or (req.type == "https" and scheme != "https"):
            raise ProfileError("Could not download the VPN subscription.")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def subscription(url):
    if not urlsplit(url).hostname:
        raise ProfileError("The VPN profile is invalid.")
    request = Request(url, headers={"User-Agent": "Velora/1 (v2ray subscription)", "Accept": "text/plain, */*"})
    try:
        with build_opener(SubscriptionRedirect()).open(request, timeout=15) as reply:
            name = reply.headers.get("profile-title", "")
            if name.startswith("base64:"):
                try:
                    name = decode64(name[7:])
                except ValueError:
                    name = ""
            return bounded_read(reply), label(name, urlsplit(url).hostname)
    except (OSError, URLError, HTTPException, ValueError) as error:
        if isinstance(error, ProfileError):
            raise
        raise ProfileError("Could not download the VPN subscription.") from None


def service():
    result = subprocess.run(["systemctl", "show", UNIT, "--property=LoadState,ActiveState,Description"],
                            capture_output=True, text=True, timeout=5)
    values = dict(s.split("=", 1) for s in result.stdout.splitlines() if "=" in s)
    if values.get("LoadState") == "not-found" or values.get("ActiveState") in ("inactive", "failed"):
        return "", ""
    if result.returncode or not values.get("ActiveState"):
        raise ProfileError(BUS_ERROR)
    match = re.fullmatch(r"Velora VPN ([0-9a-f]{32}) ([0-9a-f]{32})", values.get("Description", ""))
    if not match:
        raise ProfileError("The VPN service is busy.")
    return match.groups()


def check_editable(group):
    try:
        if service()[0] == group:
            raise ProfileError(STOP_FIRST)
    except ProfileError as error:
        if str(error) != BUS_ERROR or (Path("/sys/class/net") / INTERFACE).exists():
            raise


def bootstrap(server):
    # Resolve before changing routes. Keep the original server name for TLS and HTTP transports.
    try:
        ipaddress.ip_address(server)
        return {"type": "local", "tag": "bootstrap"}
    except ValueError:
        pass
    try:
        answers = socket.getaddrinfo(server, None, type=socket.SOCK_STREAM)
    except OSError:
        raise ProfileError("Could not resolve the VPN server.") from None
    addresses = list(dict.fromkeys(address[0] for _, _, _, _, address in answers))
    return {"type": "hosts", "tag": "bootstrap", "predefined": {server: addresses}}


def tunnel_config(outbound):
    return {
        "log": {"disabled": True},
        "dns": {"servers": [bootstrap(outbound["server"]),
                            {"type": "https", "tag": "tunnel-dns", "server": "1.1.1.1", "detour": "vpn"}],
                "final": "tunnel-dns"},
        "inbounds": [{"type": "tun", "interface_name": INTERFACE, "address": ["172.19.0.1/30", "fdfe:dcba:9876::1/126"],
                      "auto_route": True, "auto_redirect": True, "strict_route": True, "stack": "system"}],
        "outbounds": [{**outbound, "tag": "vpn"}],
        "route": {"auto_detect_interface": True, "default_domain_resolver": "bootstrap",
                  "rules": [{"port": 53, "action": "hijack-dns"}], "final": "vpn"},
    }


def connect(group, node):
    active = service()
    if active == (group, node["id"]):
        return
    if active[0]:
        raise ProfileError(STOP_FIRST)
    if not ENGINE.is_file():
        raise ProfileError("Install the VPN engine to connect.")
    RUNTIME.mkdir(mode=0o700, parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode="w", dir=RUNTIME, suffix=".json") as config:
        json.dump(tunnel_config(node["outbound"]), config)
        config.flush()
        if subprocess.run([ENGINE, "check", "-c", config.name], capture_output=True, timeout=10).returncode:
            raise ProfileError("The VPN engine rejected this server configuration.")
        # The system manager authorizes network administration. The engine runs as the desktop user.
        command = ["systemd-run", "--system", "--quiet", "--collect", "--service-type=exec",
                   "--expand-environment=no", "--unit=" + UNIT, f"--description=Velora VPN {group} {node['id']}",
                   f"--uid={os.getuid()}", f"--gid={os.getgid()}", "--property=NoNewPrivileges=yes",
                   "--property=CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW",
                   "--property=AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW",
                   "--property=ProtectSystem=strict", "--property=ProtectHome=read-only",
                   "--property=UMask=0077", f"--property=BindsTo=user@{os.getuid()}.service",
                   "--", str(ENGINE), "run", "-c", config.name]
        if subprocess.run(command, capture_output=True, timeout=120).returncode:
            raise ProfileError(START_ERROR)
        until = time.monotonic() + 8
        while time.monotonic() < until:
            if not service()[0]:
                raise ProfileError(START_ERROR)
            if (Path("/sys/class/net") / INTERFACE).exists():
                return
            time.sleep(0.1)
        disconnect(group)
        raise ProfileError(START_ERROR)


def disconnect(group):
    active, _ = service()
    if not active:
        return
    if group != active:
        raise ProfileError(STOP_FIRST)
    if subprocess.run(["systemctl", "stop", UNIT], capture_output=True, timeout=120).returncode:
        raise ProfileError("Could not stop the VPN tunnel.")


def import_group(groups, request):
    source = request.get("link", "").strip()
    if len(source.encode()) > MAX_BYTES:
        raise ProfileError("The subscription is too large.")
    # Existing provider buttons may wrap a share link before delivering it to a desktop client.
    if source.startswith("hiddify://import/"):
        source = source.removeprefix("hiddify://import/")
        if "://" not in source:
            source = unquote(source)
    if request.get("path"):
        path = Path(request["path"])
        if not path.is_file():
            raise ProfileError("Choose a VPN profile file.")
        with path.open("rb") as file:
            data = bounded_read(file)
        name, key, source = path.stem, digest("file:" + str(path.resolve())), ""
    elif urlsplit(source).scheme in ("http", "https"):
        source = urldefrag(source).url
        data, name = subscription(source)
        key = digest("url:" + source)
    else:
        data, name, key, source = source.encode(), "", "", ""
    servers, skipped = read_servers(data)
    if not key:
        name = servers[0]["name"]
        key = digest("link:" + servers[0]["id"])
    origin = key
    key = next((uid for uid, old in groups.items() if old.get("origin", uid) == origin), None) or uuid4().hex
    old = groups.get(key, {})
    # The system service's public description contains only random IDs, independent of credentials.
    previous_ids = {digest(json.dumps(s["outbound"], sort_keys=True)): s["id"] for s in old.get("servers", [])}
    for server in servers:
        server["id"] = previous_ids.get(server["id"]) or uuid4().hex
    previous = old.get("selected")
    selected = previous if any(s["id"] == previous for s in servers) else servers[0]["id"]
    groups[key] = {"origin": origin, "name": label(name, servers[0]["name"]), "source": source, "servers": servers,
                   "selected": selected, "skipped": skipped}
    return key


def snapshot(groups):
    public = []
    for key, group in groups.items():
        servers = [{"id": s["id"], "name": s["name"], "protocol": s["outbound"]["type"]} for s in group["servers"]]
        public.append({"id": key, "name": group["name"], "subscription": bool(group["source"]),
                       "servers": servers, "selected": group["selected"], "skipped": group["skipped"]})
    try:
        active, node = service() if groups else ("", "")
        problem = ""
    except (ProfileError, OSError, subprocess.TimeoutExpired):
        active, node, problem = "", "", BUS_ERROR
    return {"profiles": public, "active": active, "activeServer": node, "engine": ENGINE.is_file(), "serviceError": problem}


def archive_urls():
    plan = subprocess.run(["/usr/bin/pacman", "-Sp", "--needed", "--print-format", "%r %n %f", "sing-box"],
                          capture_output=True, text=True, timeout=20)
    urls = []
    for line in plan.stdout.splitlines():
        fields = line.split()
        if len(fields) != 3:
            return []
        repo, name, filename = fields
        if (repo not in {"core", "extra", "multilib"} or not re.fullmatch(r"[a-z0-9][a-z0-9+_.@-]*", name)
                or Path(filename).name != filename or not filename.startswith(name + "-")
                or not filename.endswith(".pkg.tar.zst")):
            return []
        urls.append(f"https://archive.archlinux.org/packages/{name[0]}/{quote(name)}/{quote(filename)}")
    return [] if plan.returncode else urls


def install_engine():
    if ENGINE.is_file():
        return
    manager = ["/usr/bin/pkexec", "/usr/bin/pacman"]
    install = [*manager, "-S", "--needed", "--noconfirm", "sing-box"]
    result = subprocess.run(install, capture_output=True, timeout=300)
    if result.returncode and b"404" in result.stderr:
        # Mirrors rotate old versions out. Cache the exact signed packages from the system's
        # sync database, then let the normal repository transaction verify and install them.
        urls = archive_urls()
        if urls:
            cached = subprocess.run([*manager, "-Uw", "--noconfirm", "--", *urls], capture_output=True, timeout=180)
            result = subprocess.run(install, capture_output=True, timeout=300) if not cached.returncode else cached
    if result.returncode in (126, 127):
        raise ProfileError("VPN engine installation was not authorized.")
    if result.returncode or not ENGINE.is_file():
        raise ProfileError("Could not install the VPN engine.")


def handle(request):
    action = request.get("action")
    if action == "status":
        return snapshot(load())
    if action == "install":
        install_engine()
        return snapshot(load())
    STORE.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (STORE / "lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        groups = load()
        key = request.get("id", "")
        if action == "import":
            existing = set(groups)
            updated = import_group(groups, request)
            if updated in existing:
                check_editable(updated)
        elif key not in groups:
            raise ProfileError("This VPN profile no longer exists.")
        elif action == "connect":
            node = next(s for s in groups[key]["servers"] if s["id"] == groups[key]["selected"])
            connect(key, node)
        elif action == "disconnect":
            disconnect(key)
        elif action in ("refresh", "select", "remove"):
            check_editable(key)
            if action == "remove":
                del groups[key]
            elif action == "select":
                selected = request.get("server")
                if not any(s["id"] == selected for s in groups[key]["servers"]):
                    raise ProfileError("This VPN profile no longer exists.")
                groups[key]["selected"] = selected
            elif groups[key]["source"]:
                import_group(groups, {"link": groups[key]["source"]})
            else:
                raise ProfileError("This profile has no subscription URL.")
        else:
            raise ProfileError("Unknown VPN action.")
        if action in ("import", "refresh", "select", "remove"):
            write_private(STORE / "profiles.json", groups)
        return snapshot(groups)


def main():
    os.umask(0o077)
    try:
        line = sys.stdin.buffer.readline(65537)
        if len(line) > 65536:
            raise ProfileError("The VPN profile is invalid.")
        if sys.argv[1:] == ["import-link"]:
            request = {"action": "import", "link": line.decode().strip()}
        else:
            request = json.loads(line)
        print(json.dumps(handle(request), ensure_ascii=False))
    except ProfileError as error:
        print(json.dumps({"error": str(error)}))
        return 1
    except subprocess.TimeoutExpired:
        print(json.dumps({"error": "The VPN operation timed out."}))
        return 1
    except (OSError, ValueError, KeyError, TypeError, StopIteration):
        # Low-level errors can contain the entire subscription URL or a credential.
        print(json.dumps({"error": "Could not read or save the VPN profile."}))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
