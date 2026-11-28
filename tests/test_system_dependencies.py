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
        probe = patch.object(velora, "matugen_can_select_source", return_value=True)
        self.matugen = probe.start()
        self.addCleanup(probe.stop)
        self.features = {"desktop": {}, "shell": {}}
        self.qml = self.base / "qml"
        for name in velora.QML_RUNTIME_MODULES:
            path = self.qml / name / "qmldir"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.touch()

    def test_missing_command_and_qml_plugin_are_reported(self):
        (self.qml / "QtMultimedia/qmldir").unlink()
        with patch.object(velora, "system_tool", side_effect=lambda name: None if name == "nmcli" else f"/usr/bin/{name}"), patch.object(velora, "run"):
            errors = velora.runtime_problems(self.features, qml_root=self.qml)
        self.assertCountEqual(errors, ["Missing command: nmcli (shell)", "Missing QML module: QtMultimedia"])

    def test_incompatible_matugen_is_reported_before_linking(self):
        self.matugen.return_value = False
        with patch.object(velora, "system_tool", return_value="/usr/bin/tool"), patch.object(velora, "run"):
            problems = velora.runtime_problems(self.features, qml_root=self.qml)
        self.assertTrue(any("--source-color-index" in error for error in problems))

    def test_native_helper_runs_without_a_shell_venv(self):
        with patch.object(velora, "system_tool", return_value="/usr/bin/tool"), patch.object(velora, "run") as run:
            self.assertEqual(velora.runtime_problems(self.features, qml_root=self.qml), [])
            self.assertEqual(run.call_args.args[0], ["/usr/bin/tool", "--version"])

    def test_missing_shared_library_is_reported(self):
        with patch.object(velora, "system_tool", return_value="/usr/bin/tool"), patch.object(velora, "run", side_effect=velora.VeloraError("missing shared library")):
            errors = velora.runtime_problems(self.features, qml_root=self.qml)
        self.assertTrue(any("missing shared library" in e for e in errors))

    def test_omitted_components_and_skipped_aur_do_not_require_optional_tools(self):
        with patch.object(velora, "system_tool", return_value=None):
            self.assertEqual(velora.runtime_problems({}), [])
            self.assertEqual(velora.runtime_problems({"live-wallpapers": {}}, skip_aur=True), [])
            self.assertEqual(velora.runtime_problems({"live-wallpapers": {}}), ["Missing command: mpvpaper (live-wallpapers)"])

    def test_runtime_failure_prevents_configuration_linking(self):
        args = velora.parser().parse_args(["install", "--yes", "--skip-packages"])
        with patch.object(velora, "preflight"), patch.object(velora, "run"), \
                patch.object(velora, "build_native_helper"), \
                patch.object(velora, "build_window_plugin"), \
                patch.object(velora, "build_file_dialog"), \
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
    def test_hyprland_does_not_export_an_obsolete_python_environment(self):
        script = PROJECT / "dots/.config/hypr/hyprland/env.lua"
        code = 'hl = {env = function(key, value) if key == "ILLOGICAL_IMPULSE_VIRTUAL_ENV" then print(value) end end}; '
        code += f'dofile({json.dumps(str(script))})'
        for state in ("", str(self.base / "custom state")):
            env = {**os.environ, "HOME": str(self.base / "home"), "XDG_STATE_HOME": state}
            result = subprocess.run([LUA, "-e", code], env=env, text=True, capture_output=True, check=True)
            self.assertEqual(result.stdout.strip(), '')


class ExistingDesktopTests(IsolatedTest):
    def test_repairs_features_missing_from_installed_providers(self):
        features = {"desktop": {"repo": ["quickshell", "matugen"]}}
        with patch.object(velora, "missing_packages", return_value=[]), \
                patch.object(velora, "POLKIT_QML", self.base / "absent"), \
                patch.object(velora, "matugen_can_select_source", return_value=False):
            self.assertEqual(velora.package_plan(features), (["quickshell"], ["matugen-bin"]))
            self.assertEqual(velora.package_plan(features, skip_aur=True), (["quickshell"], []))
            self.assertEqual(velora.package_plan(features, source_packages=["quickshell", "matugen"]), ([], []))

    def test_repairs_an_incomplete_same_version_package(self):
        args = velora.parser().parse_args(["deps", "--dry-run"])
        with patch.object(velora, "package_plan", return_value=(["quickshell"], [])), \
                patch.object(velora, "configure_desktop_services"), patch.object(velora, "run") as run:
            velora.install_dependencies(args, {"desktop": {}})
        run.assert_any_call(["sudo", "pacman", "-Syu", "--", "quickshell"], dry=True)

    def test_upgrades_repository_matugen_without_installing_a_second_provider(self):
        features = {"shell": {"repo": ["matugen"]}}
        def missing(names):
            return ["matugen-bin"] if "matugen-bin" in names else []
        with patch.object(velora, "missing_packages", side_effect=missing), \
                patch.object(velora, "matugen_can_select_source", return_value=False):
            self.assertEqual(velora.package_plan(features), (["matugen"], []))

    def test_migrates_layouts_and_switch_option_only_when_valid(self):
        options = {"input:kb_layout": "us,de", "input:kb_variant": "[[EMPTY]]",
                   "input:kb_options": "grp:alt_shift_toggle"}
        with patch.dict(os.environ, HYPRLAND_INSTANCE_SIGNATURE="test"), \
                patch.object(shutil, "which", return_value="hyprctl"), \
                patch.object(velora, "run", side_effect=lambda cmd, **kw: json.dumps({"str": options[cmd[-1]]})):
            self.assertEqual(velora.previous_layouts(), {"kb_layout": "us,de", "kb_options": "grp:alt_shift_toggle"})
            options["input:kb_layout"] = "us"
            self.assertEqual(velora.previous_layouts(), {})
            options["input:kb_layout"] = 'us,de"'
            self.assertEqual(velora.previous_layouts(), {})

    def test_activates_loaded_modules_after_a_clean_reload_only(self):
        args = velora.parser().parse_args(["install"])
        for errors in ("", "bad config"):
            with self.subTest(errors=errors), patch.dict(os.environ, HYPRLAND_INSTANCE_SIGNATURE="test"), \
                    patch.object(shutil, "which", return_value="hyprctl"), \
                    patch.object(velora, "register_installation"), \
                    patch.object(velora, "run", side_effect=lambda cmd, **kw: errors if "configerrors" in cmd else "ok") as run:
                velora.link_configuration(args, [])
                calls = [call.args[0] for call in run.call_args_list]
                self.assertIn(["hyprctl", "reload"], calls)
                self.assertEqual(any(cmd[:2] == ["hyprctl", "eval"] for cmd in calls), not errors)


class DesktopServiceTests(IsolatedTest):
    def setUp(self):
        super().setUp()
        # A fresh install must be independent of the QEMU guest's existing setup.
        for name in ('files_equal', 'input_ready'):
            mocked = patch.object(velora, name, return_value=False)
            mocked.start()
            self.addCleanup(mocked.stop)

    def test_ready_system_only_refreshes_user_services_without_sudo(self):
        def run(command, **kwargs):
            self.assertNotEqual(command[0], 'sudo')
            return 'enabled' if command[:2] == ['systemctl', 'is-enabled'] else ''
        args = velora.parser().parse_args(['deps'])
        with patch.object(velora, 'service_active', side_effect=lambda unit, **kwargs: unit == 'NetworkManager.service'), \
                patch.object(velora, 'files_equal', return_value=True), \
                patch.object(velora, 'input_ready', return_value=True), patch.object(velora, 'run', side_effect=run):
            velora.configure_desktop_services(args)

    def test_active_but_disabled_service_still_gets_enabled(self):
        with patch.object(velora, 'service_active', return_value=True), \
                patch.object(velora, 'run', return_value='disabled') as run:
            velora.ensure_system_service('power-profiles-daemon')
        run.assert_any_call(['sudo', 'systemctl', 'enable', '--now', 'power-profiles-daemon'], dry=False)

    def test_restarts_an_active_virtual_keyboard_missing_its_configured_socket(self):
        args = velora.parser().parse_args(["deps"])
        with patch.dict(os.environ, XDG_RUNTIME_DIR=str(self.base)), \
                patch.object(velora, "service_active", return_value=True), patch.object(velora, "run") as run:
            velora.configure_desktop_services(args)
            run.assert_any_call(["systemctl", "--user", "restart", "ydotool.service"], dry=False)

    def test_enables_network_audio_and_keyboard_on_a_new_desktop(self):
        args = velora.parser().parse_args(["deps"])
        with patch.object(velora, "competing_network_units", return_value=(set(), set())), \
                patch.object(velora, "service_active", return_value=False), patch.object(velora, "run") as run:
            velora.configure_desktop_services(args)
            velora.configure_network(args)
        commands = [call.args[0] for call in run.call_args_list]
        self.assertIn(["sudo", "systemctl", "enable", "--now", "NetworkManager.service"], commands)
        enable = next(command for command in commands if command[:4] == ["systemctl", "--user", "--no-reload", "enable"])
        self.assertEqual(set(enable[4:]), {"pipewire.socket", "pipewire-pulse.socket", "wireplumber.service", "ydotool.service"})
        self.assertIn(["sudo", "modprobe", "uinput"], commands)
        self.assertIn(["sudo", "udevadm", "settle"], commands)
        self.assertFalse(any("usermod" in command or "chmod" in command for command in commands))

    def test_keeps_an_existing_network_manager_running(self):
        args = velora.parser().parse_args(["deps"])
        with patch.object(velora, "competing_network_units", return_value=({"iwd.service"}, {"iwd.service"})), \
                patch.object(velora, "run") as run:
            velora.configure_network(args)
        run.assert_not_called()

    def test_minimal_install_schedules_one_manager_without_disconnecting_the_live_network(self):
        units = {"systemd-networkd.socket", "systemd-networkd.service", "iwd.service"}
        args = velora.parser().parse_args(["install", "--yes"])
        with patch.object(velora, "competing_network_units", return_value=(units, units)), \
                patch.object(velora, "run") as run:
            velora.plan_network(args)
            velora.configure_network(args)
        self.assertEqual([call.args[0] for call in run.call_args_list], [
            ["systemctl", "list-unit-files", "NetworkManager.service", "--no-legend", "--no-pager"],
            ["sudo", "systemctl", "enable", "NetworkManager.service"],
            ["sudo", "systemctl", "disable", *sorted(units)],
        ])

    def test_enabled_but_idle_competitor_is_switched_at_boot(self):
        args = velora.parser().parse_args(["deps", "--network-manager", "migrate", "--dry-run"])
        with patch.object(velora, "competing_network_units", return_value=(set(), {"dhcpcd@eth0.service"})), \
                patch.object(velora, "run") as run:
            velora.configure_network(args)
        run.assert_any_call(["sudo", "systemctl", "disable", "dhcpcd@eth0.service"], dry=True)
        self.assertTrue(all("--now" not in call.args[0] and call.kwargs["dry"] for call in run.call_args_list))

    def test_iwd_used_by_networkmanager_is_a_backend(self):
        with patch.object(velora, "system_tool", return_value="/usr/bin/NetworkManager"), \
                patch.object(velora, "run", side_effect=[
                    "iwd.service loaded active running Wireless service",
                    "iwd.service enabled disabled\nsystemd-networkd.service enabled disabled",
                    "[device]\nwifi.backend=iwd\n",
                ]):
            self.assertEqual(velora.competing_network_units(), (set(), {"systemd-networkd.service"}))

    def test_keep_and_skip_packages_do_not_touch_network_units(self):
        for flags in (["--network-manager", "keep"], ["--network-manager", "migrate", "--skip-packages"]):
            args = velora.parser().parse_args(["install", "--yes", *flags])
            with patch.object(velora, "competing_network_units") as inspect, patch.object(velora, "run") as run:
                velora.plan_network(args)
                velora.configure_network(args)
            inspect.assert_not_called()
            run.assert_not_called()

    def test_nm_only_boot_has_no_competing_units(self):
        def list_units(command, **kwargs):
            # systemctl list-unit-files returns 1 if all explicit unit names miss the state filter.
            self.assertTrue(command[-1].startswith("--state="))
            return "NetworkManager.service enabled disabled\nwpa_supplicant.service active running\n"
        with patch.object(velora, "run", side_effect=list_units):
            self.assertEqual(velora.competing_network_units(), (set(), set()))

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
