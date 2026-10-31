"""Desktop readiness and service setup without changing host packages, devices or services."""
import json
import os
import shutil
import subprocess
import unittest
from unittest.mock import patch

from test_velora import IsolatedTest, PROJECT, velora

LUA = shutil.which("lua5.4") or shutil.which("lua")


class RuntimeTests(IsolatedTest):
    def setUp(self):
        super().setUp()
        self.features = {"desktop": {}, "shell": {}}
        self.qml = self.base / "qml"
        for name in velora.QML_RUNTIME_MODULES:
            path = self.qml / name / "qmldir"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.touch()
        self.python = self.base / "state/quickshell/.venv/bin/python"
        self.python.parent.mkdir(parents=True)
        self.python.touch()

    def test_missing_command_qml_plugin_and_gnome_typelib_are_all_reported(self):
        (self.qml / "QtMultimedia/qmldir").unlink()
        with patch.object(velora, "system_tool", side_effect=lambda name: None if name == "nmcli" else f"/usr/bin/{name}"), \
                patch.object(velora, "run", return_value=json.dumps(["GTK/GnomeDesktop introspection: namespace unavailable"])):
            errors = velora.runtime_problems(self.features, qml_root=self.qml)
        self.assertEqual(len(errors), 3)
        self.assertIn("Missing command: nmcli (shell)", errors)
        self.assertIn("Missing QML module: QtMultimedia", errors)
        self.assertIn("Python: GTK/GnomeDesktop introspection: namespace unavailable", errors)

    def test_successful_check_uses_the_locked_environment_instead_of_path_python(self):
        with patch.object(velora, "system_tool", return_value="/usr/bin/tool"), \
                patch.object(velora, "run", return_value="[]") as run:
            self.assertEqual(velora.runtime_problems(self.features, qml_root=self.qml), [])
        self.assertEqual(run.call_args.args[0][0], self.python)
        self.assertIn("gi.require_version('GnomeDesktop', '4.0')", run.call_args.args[0][2])

    def test_broken_python_environment_fails_even_when_its_interpreter_exists(self):
        with patch.object(velora, "system_tool", return_value="/usr/bin/tool"), \
                patch.object(velora, "run", side_effect=velora.VeloraError("missing shared library")):
            errors = velora.runtime_problems(self.features, qml_root=self.qml)
        self.assertTrue(any("missing shared library" in error for error in errors))

    def test_omitted_components_and_skipped_aur_do_not_require_optional_tools(self):
        with patch.object(velora, "system_tool", return_value=None):
            self.assertEqual(velora.runtime_problems({}), [])
            self.assertEqual(velora.runtime_problems({"live-wallpapers": {}}, skip_aur=True), [])
            self.assertEqual(velora.runtime_problems({"live-wallpapers": {}}), ["Missing command: mpvpaper (live-wallpapers)"])

    def test_runtime_failure_prevents_configuration_linking(self):
        args = velora.parser().parse_args(["install", "--yes", "--skip-packages"])
        with patch.object(velora, "preflight"), patch.object(velora, "run"), \
                patch.object(velora, "build_native_helper"), \
                patch.object(velora, "install_fonts"), \
                patch.object(velora, "runtime_problems", return_value=["Missing QML module: QtMultimedia"]), \
                patch.object(velora, "link_configuration") as link:
            with self.assertRaisesRegex(velora.VeloraError, "Desktop runtime checks failed"):
                velora.install(args)
        link.assert_not_called()

    def test_core_packages_explicitly_cover_the_default_integration_and_thumbnail_api(self):
        core = {package for feature in velora.manifest().values() if feature["required"] for package in feature["repo"]}
        self.assertTrue({"gnome-desktop-4", "plasma-integration", "breeze-icons", "breeze", "qt6-declarative",
                         "qt6-svg", "qt6-shadertools", "pipewire-audio", "libpulse", "xkeyboard-config", "fish", "kmod"} <= core)

    def test_runtime_dry_run_does_not_import_or_probe_the_host(self):
        args = velora.parser().parse_args(["install", "--dry-run"])
        with patch.object(velora, "runtime_problems") as probe:
            velora.verify_runtime(self.features, args)
        probe.assert_not_called()

    @unittest.skipUnless(LUA, "Lua is not installed")
    def test_hyprland_uses_the_same_python_environment_for_custom_state_directories(self):
        script = PROJECT / "dots/.config/hypr/hyprland/env.lua"
        code = 'hl = {env = function(key, value) if key == "ILLOGICAL_IMPULSE_VIRTUAL_ENV" then print(value) end end}; '
        code += f'dofile({json.dumps(str(script))})'
        for state in ("", str(self.base / "custom state")):
            env = {**os.environ, "HOME": str(self.base / "home"), "XDG_STATE_HOME": state}
            result = subprocess.run([LUA, "-e", code], env=env, text=True, capture_output=True, check=True)
            expected = (self.base / "custom state" if state else self.base / "home/.local/state") / "quickshell/.venv"
            self.assertEqual(result.stdout.strip(), str(expected))


class DesktopServiceTests(IsolatedTest):
    def test_enables_network_audio_and_keyboard_on_a_new_desktop(self):
        args = velora.parser().parse_args(["deps"])
        with patch.object(velora, "service_active", return_value=False), patch.object(velora, "run") as run:
            velora.configure_desktop_services(args)
        commands = [call.args[0] for call in run.call_args_list]
        self.assertIn(["sudo", "systemctl", "enable", "--now", "NetworkManager.service"], commands)
        enable = next(command for command in commands if command[:4] == ["systemctl", "--user", "--no-reload", "enable"])
        self.assertEqual(set(enable[4:]), {"pipewire.socket", "pipewire-pulse.socket", "wireplumber.service", "ydotool.service"})
        self.assertIn(["sudo", "modprobe", "uinput"], commands)
        self.assertIn(["sudo", "udevadm", "settle"], commands)
        self.assertFalse(any("usermod" in command or "chmod" in command for command in commands))

    def test_keeps_an_existing_network_manager_running(self):
        args = velora.parser().parse_args(["deps"])
        with patch.object(velora, "service_active", side_effect=lambda unit: unit == "iwd.service"), \
                patch.object(velora, "run") as run:
            velora.configure_desktop_services(args)
        self.assertFalse(any("NetworkManager.service" in call.args[0] for call in run.call_args_list))

    def test_user_services_are_enabled_even_without_a_running_user_manager(self):
        def run(command, **kwargs):
            if command == ["systemctl", "--user", "daemon-reload"]:
                raise velora.VeloraError("no user bus")
        args = velora.parser().parse_args(["deps"])
        with patch.object(velora, "service_active", return_value=False), patch.object(velora, "run", side_effect=run) as calls:
            velora.configure_desktop_services(args)
        self.assertTrue(any(call.args[0][:4] == ["systemctl", "--user", "--no-reload", "enable"] for call in calls.call_args_list))

    def test_service_dry_run_passes_dry_to_every_mutating_command(self):
        args = velora.parser().parse_args(["deps", "--dry-run"])
        with patch.object(velora, "service_active", return_value=False), patch.object(velora, "run") as run:
            velora.configure_desktop_services(args)
        self.assertTrue(run.call_args_list)
        self.assertTrue(all(call.kwargs.get("dry") for call in run.call_args_list))
        self.assertFalse((self.base / "config").exists())

    def test_skip_packages_does_not_configure_services(self):
        args = velora.parser().parse_args(["deps", "--skip-packages"])
        with patch.object(velora, "configure_desktop_services") as services, patch.object(velora, "run") as run:
            velora.install_dependencies(args, {"shell": {}})
        services.assert_not_called()
        run.assert_not_called()

    def test_virtual_keyboard_access_and_socket_are_scoped_to_the_local_user(self):
        rule = (PROJECT / "dependencies/system/70-velora-uinput.rules").read_text()
        unit = (PROJECT / "dependencies/system/ydotool-user.conf").read_text()
        environment = (PROJECT / "dots/.config/hypr/hyprland/env.lua").read_text()
        self.assertIn('KERNEL=="uinput"', rule)
        self.assertIn('TAG+="uaccess"', rule)
        self.assertIn("--socket-path=%t/ydotool.sock --socket-perm=0600", unit)
        self.assertIn('hl.env("YDOTOOL_SOCKET", runtime .. "/ydotool.sock")', environment)
        self.assertNotIn('GROUP="input"', rule)
