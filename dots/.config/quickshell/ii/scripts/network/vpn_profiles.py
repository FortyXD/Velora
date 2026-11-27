"""Read provider share links and subscription lists into sing-box outbounds."""
import base64
import binascii
import hashlib
import json
from urllib.parse import parse_qsl, unquote, urlsplit
from uuid import UUID


class ProfileError(ValueError):
    pass


INVALID = "The VPN profile is invalid."
UNSUPPORTED = "This VPN protocol or transport is unsupported."
MAX_BYTES = 4 * 1024 * 1024
TYPES = {"vless", "vmess", "shadowsocks", "trojan", "hysteria", "hysteria2", "tuic"}


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()[:32]


def label(text, fallback):
    text = "".join(c for c in str(text or "") if c.isprintable() and c not in "<>").strip()
    return text[:160] if text and "://" not in text else fallback


def decode64(value):
    value = "".join(value.split())
    return base64.b64decode(value + "=" * (-len(value) % 4), altchars=b"-_", validate=True).decode()


def port(value):
    number = int(value)
    if not 0 < number < 65536:
        raise ProfileError(INVALID)
    return number


def host(value):
    if not isinstance(value, str) or not value or any(c.isspace() or c in "/@?#<>%" for c in value):
        raise ProfileError(INVALID)
    return value


def truth(value):
    if str(value).lower() in ("1", "true", "yes"):
        return True
    if str(value).lower() in ("0", "false", "no", "", "none"):
        return False
    raise ProfileError(INVALID)


def tls_options(query, mode):
    if mode in ("none", ""):
        return {}
    if mode not in ("tls", "reality"):
        raise ProfileError(UNSUPPORTED)
    if any(query.get(key) for key in ("pinSHA256", "pin-sha256", "ech", "echConfig", "pinnedPeerCertSha256")):
        raise ProfileError(UNSUPPORTED)
    tls = {"enabled": True}
    name = query.get("sni") or query.get("peer") or query.get("serverName")
    if name:
        tls["server_name"] = name
    if truth(query.get("insecure") or query.get("allowInsecure") or query.get("allow_insecure")):
        tls["insecure"] = True
    if query.get("alpn"):
        tls["alpn"] = [p.strip() for p in query["alpn"].split(",") if p.strip()]
    if mode == "reality":
        if not query.get("pbk"):
            raise ProfileError(INVALID)
        tls["reality"] = {"enabled": True, "public_key": query["pbk"], "short_id": query.get("sid", "")}
    if query.get("fp") or mode == "reality":
        tls["utls"] = {"enabled": True, "fingerprint": query.get("fp") or "chrome"}
    return {"tls": tls}


def transport(query):
    kind = query.get("type") or "tcp"
    path, authority = query.get("path") or "/", query.get("host") or ""
    if kind in ("tcp", "raw", "none"):
        if query.get("headerType") not in (None, "", "none"):
            raise ProfileError(UNSUPPORTED)
        return {}
    if kind == "ws":
        options = {"type": kind, "path": path}
        if authority:
            options["headers"] = {"Host": authority}
        if query.get("ed"):
            options.update(max_early_data=int(query["ed"]), early_data_header_name=query.get("eh") or "Sec-WebSocket-Protocol")
    elif kind == "grpc":
        if query.get("mode") not in (None, "", "gun"):
            raise ProfileError(UNSUPPORTED)
        options = {"type": kind, "service_name": query.get("serviceName") or query.get("path", "")}
    elif kind in ("h2", "http", "httpupgrade"):
        options = {"type": "httpupgrade" if kind == "httpupgrade" else "http", "path": path}
        if authority:
            options["host"] = authority if kind == "httpupgrade" else authority.split(",")
    elif kind == "quic":
        options = {"type": "quic"}
    else:
        raise ProfileError(UNSUPPORTED)
    return {"transport": options}


def shadowsocks(link):
    uri = urlsplit(link)
    address = link.split("://", 1)[1].split("#", 1)[0].split("?", 1)[0]
    if "@" not in address:
        address = decode64(unquote(address))
    credentials, endpoint = address.rsplit("@", 1)
    endpoint = urlsplit("ss://" + endpoint)
    credentials = unquote(credentials)
    if ":" not in credentials:
        credentials = decode64(credentials)
    method, password = credentials.split(":", 1)
    if not method or not password:
        raise ProfileError(INVALID)
    out = {"type": "shadowsocks", "server": host(endpoint.hostname), "server_port": port(endpoint.port),
           "method": method, "password": password}
    plugin = dict(parse_qsl(uri.query)).get("plugin")
    if plugin:
        name, _, options = plugin.partition(";")
        if name not in ("obfs-local", "v2ray-plugin"):
            raise ProfileError(UNSUPPORTED)
        out.update(plugin=name, plugin_opts=options)
    return unquote(uri.fragment), out


def parse_link(link):
    scheme, _, body = link.partition("://")
    scheme = scheme.lower()
    if scheme == "ss":
        return shadowsocks(link)
    scheme = "hysteria2" if scheme == "hy2" else scheme
    if scheme not in TYPES - {"shadowsocks"}:
        raise ProfileError(UNSUPPORTED)
    if scheme == "vmess" and "@" not in body:
        vm = json.loads(decode64(unquote(body.split("#", 1)[0])))
        if not isinstance(vm, dict):
            raise ProfileError(INVALID)
        out = {"type": scheme, "server": host(vm["add"]), "server_port": port(vm["port"]),
               "uuid": str(UUID(vm["id"])), "security": vm.get("scy") or "auto", "alter_id": int(vm.get("aid") or 0)}
        query = {**vm, "type": vm.get("net"), "headerType": vm.get("type")}
        out.update(transport(query), **tls_options(query, vm.get("tls") or ""))
        return vm.get("ps"), out
    uri = urlsplit(link)
    q = dict(parse_qsl(uri.query, keep_blank_values=True))
    out = {"type": scheme, "server": host(uri.hostname), "server_port": port(uri.port if uri.port is not None else 443)}
    user = unquote(uri.netloc.rsplit("@", 1)[0]) if "@" in uri.netloc else ""
    mode = q.get("security") or ("none" if scheme in ("vless", "vmess") else "tls")
    if scheme in ("tuic", "hysteria", "hysteria2") and mode != "tls":
        raise ProfileError(UNSUPPORTED)
    out.update(tls_options(q, mode))
    if scheme in ("vmess", "vless", "trojan"):
        out.update(transport(q))
    if scheme in ("vmess", "vless"):
        out["uuid"] = str(UUID(user))
        if scheme == "vmess":
            out.update(security=q.get("encryption") or "auto", alter_id=int(q.get("aid") or 0))
        elif q.get("encryption") not in (None, "", "none"):
            raise ProfileError(UNSUPPORTED)
        if scheme == "vless" and q.get("flow"):
            out["flow"] = q["flow"]
        if q.get("packetEncoding"):
            out["packet_encoding"] = q["packetEncoding"]
    elif scheme == "tuic":
        user_id, password = user.split(":", 1)
        out.update(uuid=str(UUID(user_id)), password=password)
        for key in ("congestion_control", "udp_relay_mode"):
            if q.get(key):
                out[key] = q[key]
        if truth(q.get("disable_sni")):
            out["tls"]["disable_sni"] = True
    elif scheme == "hysteria":
        if q.get("protocol") not in (None, "", "udp"):
            raise ProfileError(UNSUPPORTED)
        out.update(auth_str=q.get("auth") or user, up_mbps=int(q.get("upmbps") or 10),
                   down_mbps=int(q.get("downmbps") or 50))
        if q.get("obfsParam"):
            out["obfs"] = q["obfsParam"]
    else:
        if not user:
            raise ProfileError(INVALID)
        out["password"] = user
        if scheme == "hysteria2" and q.get("obfs"):
            if q["obfs"] != "salamander" or not q.get("obfs-password"):
                raise ProfileError(UNSUPPORTED)
            out["obfs"] = {"type": "salamander", "password": q["obfs-password"]}
    if scheme in ("hysteria", "hysteria2") and q.get("mport"):
        out["server_ports"] = [p.replace("-", ":") for p in q["mport"].split(",")]
        del out["server_port"]
    return unquote(uri.fragment), out


def native_server(item):
    # Import the remote endpoint only. A provider cannot change local routing, load a file,
    # or request a different network interface through its configuration.
    keys = {"type", "tag", "server", "server_port", "server_ports", "network", "tls", "transport",
            "uuid", "security", "alter_id", "password", "method", "flow", "packet_encoding",
            "auth", "auth_str", "up_mbps", "down_mbps", "obfs", "plugin", "plugin_opts",
            "congestion_control", "udp_relay_mode", "zero_rtt_handshake", "heartbeat", "hop_interval"}
    if item.get("type") not in TYPES or item.keys() - keys:
        raise ProfileError(UNSUPPORTED)
    out = dict(item)
    name = out.pop("tag", None)
    host(out["server"])
    if "server_ports" not in out:
        out["server_port"] = port(out["server_port"])
    if out["type"] in ("vless", "vmess", "tuic"):
        out["uuid"] = str(UUID(out["uuid"]))
    if out["type"] in ("shadowsocks", "trojan", "tuic", "hysteria2") and not out.get("password"):
        raise ProfileError(INVALID)
    if out["type"] == "shadowsocks" and not out.get("method"):
        raise ProfileError(INVALID)
    if out.get("plugin") not in (None, "", "obfs-local", "v2ray-plugin"):
        raise ProfileError(UNSUPPORTED)
    tls = out.get("tls", {})
    if tls.keys() - {"enabled", "server_name", "insecure", "disable_sni", "alpn", "utls", "reality",
                     "min_version", "max_version", "certificate", "certificate_public_key_sha256"}:
        raise ProfileError(UNSUPPORTED)
    if tls.get("reality", {}).keys() - {"enabled", "public_key", "short_id"} or tls.get("utls", {}).keys() - {"enabled", "fingerprint"}:
        raise ProfileError(UNSUPPORTED)
    trans = out.get("transport", {})
    if trans and (trans.get("type") not in {"ws", "grpc", "http", "httpupgrade", "quic"} or
                  trans.keys() - {"type", "host", "path", "headers", "method", "service_name", "max_early_data",
                                  "early_data_header_name", "idle_timeout", "ping_timeout", "permit_without_stream"}):
        raise ProfileError(UNSUPPORTED)
    return name, out


def entries(text):
    if not text.startswith(("{", "[")):
        return [line.strip() for line in text.splitlines() if line.strip() and not line.lstrip().startswith("#")]
    items = json.loads(text)
    if isinstance(items, dict):
        items = items.get("outbounds", [items])
    if not isinstance(items, list):
        raise ProfileError(INVALID)
    return [item for item in items if not isinstance(item, dict) or
            item.get("type") not in {"direct", "block", "dns", "selector", "urltest"}]


def read_servers(content):
    text = content.decode("utf-8-sig").strip()
    if not text.startswith(("{", "[")) and "://" not in text:
        try:
            text = decode64(text).strip()
        except (ValueError, UnicodeError):
            raise ProfileError(UNSUPPORTED) from None
    servers = {}
    skipped = 0
    last_error = INVALID
    for item in entries(text):
        try:
            if isinstance(item, dict):
                name, outbound = native_server(item)
            elif isinstance(item, str) and len(item) <= 32768 and all(ord(c) >= 32 for c in item):
                name, outbound = parse_link(item)
            else:
                raise ProfileError(INVALID)
            key = digest(json.dumps(outbound, sort_keys=True))
            servers[key] = {"id": key, "name": label(name, outbound["server"]), "outbound": outbound}
        except (ValueError, TypeError, KeyError, AttributeError, binascii.Error) as error:
            last_error = str(error) if isinstance(error, ProfileError) else INVALID
            skipped += 1
    if not servers:
        raise ProfileError(last_error)
    return list(servers.values()), skipped
