import base64
from contextlib import ExitStack
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1] / "dots/.config/quickshell/ii/scripts/network"
sys.path.insert(0, str(SCRIPTS))
import proxy_vpn as vpn
from vpn_profiles import ProfileError, read_servers

UUID = "353c6a14-908f-453a-9393-bafa1c541234"


def encoded(text):
    return base64.urlsafe_b64encode(text.encode()).decode().rstrip("=")


def links():
    return [
        f"vless://{UUID}@127.0.0.1:443?security=tls&type=ws&path=%2Fsocket&host=vpn.test#Primary",
        "vmess://" + encoded(json.dumps({"add": "127.0.0.1", "port": "443", "id": UUID,
                                         "net": "grpc", "path": "rpc", "tls": "tls", "ps": "VMess"})),
        "ss://" + encoded("aes-128-gcm:private:/+") + "@127.0.0.1:8388#SS",
        "trojan://private%3A%2F%2B@127.0.0.1:443?sni=test.invalid#TLS",
        "hysteria://127.0.0.1:443?auth=private&upmbps=12&downmbps=60#Hy1",
        "hy2://private@127.0.0.1:443?obfs=salamander&obfs-password=test#Hy2",
        f"tuic://{UUID}:private@127.0.0.1:443?congestion_control=bbr&alpn=h3#TUIC",
    ]


class ProxyVpnTests(unittest.TestCase):
    def setUp(self):
        stack = self.enterContext(ExitStack())
        self.directory = Path(stack.enter_context(tempfile.TemporaryDirectory()))
        stack.enter_context(patch.object(vpn, "STORE", self.directory / "profiles"))
        stack.enter_context(patch.object(vpn, "RUNTIME", self.directory / "runtime"))
        self.service = stack.enter_context(patch.object(vpn, "service", return_value=("", "")))

    def test_share_formats_and_engine_configs(self):
        servers, skipped = read_servers("\n".join(links()).encode())
        self.assertEqual(skipped, 0)
        nodes = [s["outbound"] for s in servers]
        self.assertEqual([n["type"] for n in nodes], ["vless", "vmess", "shadowsocks", "trojan", "hysteria", "hysteria2", "tuic"])
        self.assertEqual(nodes[0]["transport"], {"type": "ws", "path": "/socket", "headers": {"Host": "vpn.test"}})
        self.assertEqual(nodes[1]["transport"]["service_name"], "rpc")
        self.assertEqual(nodes[2]["password"], "private:/+")
        self.assertEqual(nodes[3]["password"], "private:/+")
        self.assertEqual(nodes[5]["obfs"]["password"], "test")
        legacy = "ss://" + encoded("aes-128-gcm:private:/+@[::1]:8388") + "#IPv6"
        self.assertEqual(read_servers(legacy.encode())[0][0]["outbound"]["server"], "::1")
        engine = os.environ.get("VELORA_TEST_SING_BOX") or shutil.which("sing-box")
        if engine:
            config = self.directory / "check.json"
            for node in nodes:
                with self.subTest(protocol=node["type"]):
                    config.write_text(json.dumps(vpn.tunnel_config(node)))
                    result = subprocess.run([engine, "check", "-c", config], capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stderr)

    def test_raw_native_and_unsupported_profiles(self):
        body = links()[0].replace("security=tls", "security=reality&pbk=" + encoded("a"*32) + "&sid=0102")
        out = read_servers(body.encode())[0][0]["outbound"]
        self.assertEqual(out["tls"]["reality"]["short_id"], "0102")
        self.assertEqual(out["tls"]["utls"]["fingerprint"], "chrome")
        items = [dict(out, tag="First"), dict(out, tag="Unsafe", tls={"certificate_path": "/example"}),
                 {"type": "selector", "tag": "select"}]
        config = {"outbounds": items, "inbounds": [{"type": "mixed", "listen": "0.0.0.0"}]}
        servers, skipped = read_servers(encoded(json.dumps(config)).encode())
        self.assertEqual((len(servers), skipped), (1, 1))
        self.assertEqual(servers[0]["outbound"], out)
        with self.assertRaises(ProfileError):
            read_servers(links()[0].replace("type=ws", "type=xhttp").encode())

    def test_subscription_refresh_selection_and_private_storage(self):
        url = "https://provider.invalid/sub/private-token"
        body = encoded("\n".join(links()[:3] + [links()[0], "invalid://entry"])).encode()
        with patch.object(vpn, "subscription", return_value=(body, "Provider")):
            first = vpn.handle({"action": "import", "link": url})["profiles"][0]
        key, chosen = first["id"], first["servers"][1]["id"]
        self.assertEqual((len(first["servers"]), first["skipped"]), (3, 1))
        self.assertNotIn("private", json.dumps(first))
        self.assertEqual((vpn.STORE / "profiles.json").stat().st_mode & 0o777, 0o600)
        vpn.handle({"action": "select", "id": key, "server": chosen})
        with patch.object(vpn, "subscription", return_value=("\n".join(reversed(links())).encode(), "Provider")):
            new = vpn.handle({"action": "refresh", "id": key})["profiles"][0]
        self.assertEqual(new["selected"], chosen)
        before = (vpn.STORE / "profiles.json").read_bytes()
        with patch.object(vpn, "subscription", return_value=(b"invalid://content", "Provider")), self.assertRaises(ProfileError):
            vpn.handle({"action": "refresh", "id": key})
        self.assertEqual((vpn.STORE / "profiles.json").read_bytes(), before)
        self.service.return_value = (key, chosen)
        for action in ("remove", "select", "refresh"):
            with self.subTest(action=action), self.assertRaises(ProfileError):
                vpn.handle({"action": action, "id": key, "server": chosen})
        self.service.return_value = ("", "")
        self.assertEqual(vpn.handle({"action": "remove", "id": key})["profiles"], [])

    def test_connect_disconnect_and_authorization_failure(self):
        profile = vpn.handle({"action": "import", "link": links()[2]})["profiles"][0]
        key, selected = profile["id"], profile["selected"]
        invocations = []
        allow = False
        def run(cmd, **kwargs):
            invocations.append(cmd)
            if cmd[0] == "systemd-run":
                config = json.loads(Path(cmd[-1]).read_text())
                self.assertEqual(config["outbounds"][0]["password"], "private:/+")
                if allow:
                    self.service.return_value = (key, selected)
                return subprocess.CompletedProcess(cmd, 0 if allow else 1)
            if cmd[0] == "systemctl":
                self.service.return_value = ("", "")
            return subprocess.CompletedProcess(cmd, 0)
        with patch.object(vpn, "ENGINE", Path("/usr/bin/true")), patch.object(vpn, "INTERFACE", "lo"), patch.object(vpn.subprocess, "run", side_effect=run):
            with self.assertRaisesRegex(ProfileError, "authorization"):
                vpn.handle({"action": "connect", "id": key})
            allow = True
            self.assertEqual(vpn.handle({"action": "connect", "id": key})["active"], key)
            self.assertEqual(vpn.handle({"action": "disconnect", "id": key})["active"], "")
        self.assertFalse(any("private" in str(arg) for cmd in invocations for arg in cmd))
        self.assertEqual(list(vpn.RUNTIME.iterdir()), [])

    def test_file_import_and_duplicate_are_stable(self):
        path = self.directory / "two profiles.txt"
        path.write_text("\n".join(links()[:2]))
        first = vpn.handle({"action": "import", "path": str(path)})
        second = vpn.handle({"action": "import", "path": str(path)})
        self.assertEqual(first, second)
        self.assertEqual(first["profiles"][0]["name"], "two profiles")
        self.assertEqual(vpn.handle({"action": "status"}), second)
        direct = vpn.handle({"action": "import", "link": links()[0]})
        wrapped = vpn.handle({"action": "import", "link": "hiddify://import/" + links()[0]})
        self.assertEqual(direct, wrapped)

    def test_install_recovers_a_rotated_package_without_updating_the_system(self):
        executable = self.directory / "sing-box"
        commands = []
        def run(cmd, **kwargs):
            commands.append(cmd)
            if "-Sp" in cmd:
                return subprocess.CompletedProcess(cmd, 0, stdout="extra sing-box sing-box-1-x86_64.pkg.tar.zst\n")
            if len(commands) == 1:
                return subprocess.CompletedProcess(cmd, 1, stderr=b"404")
            if "-S" in cmd:
                executable.touch()
            return subprocess.CompletedProcess(cmd, 0, stderr=b"")
        with patch.object(vpn, "ENGINE", executable), patch.object(vpn.subprocess, "run", side_effect=run):
            vpn.install_engine()
        self.assertEqual(commands[2][-1], "https://archive.archlinux.org/packages/s/sing-box/sing-box-1-x86_64.pkg.tar.zst")
        self.assertIn("-Uw", commands[2])
        self.assertEqual(commands[0], commands[3])
        executable.unlink()
        with patch.object(vpn, "ENGINE", executable), patch.object(vpn.subprocess, "run", return_value=subprocess.CompletedProcess([], 126, stderr=b"")) as denied:
            with self.assertRaisesRegex(ProfileError, "authorized"):
                vpn.install_engine()
            denied.assert_called_once()

    @unittest.skipUnless(os.environ.get("VELORA_TEST_PREBUILT"), "uses loopback in tests/run_isolated.py")
    def test_subscription_over_private_http(self):
        class Provider(BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200)
                self.send_header("Profile-Title", "base64:" + encoded("Тест"))
                self.end_headers()
                self.wfile.write(encoded("\n".join(links())).encode())

            def log_message(self, *args):
                pass

        with ThreadingHTTPServer(("127.0.0.1", 0), Provider) as server:
            thread = threading.Thread(target=server.serve_forever)
            thread.start()
            try:
                url = f"http://127.0.0.1:{server.server_port}/subscription/private"
                profile = vpn.handle({"action": "import", "link": url})["profiles"][0]
                self.assertEqual(profile["name"], "Тест")
                self.assertEqual(len(profile["servers"]), 7)
                self.assertEqual(vpn.handle({"action": "refresh", "id": profile["id"]})["profiles"], [profile])
            finally:
                server.shutdown()
                thread.join()
