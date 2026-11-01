"""Login-manager plans and commands without modifying host packages or services."""
from pathlib import Path
from unittest.mock import Mock, patch

from test_velora import IsolatedTest, velora
import login_manager as manager


def inventory(*names, active=None, enabled=None, configured=None, target="graphical.target"):
    return {"managers": [{"name": name, "label": manager.MANAGERS[name][0],
                          "package": manager.MANAGERS[name][1], "unit": manager.MANAGERS[name][2],
                          "installed": True, "active": name == active, "enabled": name == enabled,
                          "configured": name == configured} for name in names], "default_target": target}


class LoginManagerTests(IsolatedTest):
    def test_fresh_unattended_install_does_not_opt_in(self):
        self.assertEqual(manager.choose(None, None, inventory()), "skip")
        self.assertIsNone(velora.parser().parse_args(["install", "--yes"]).login_manager)

    def test_interactive_default_skips_and_yes_offers_gdm(self):
        self.assertEqual(manager.choose(None, None, inventory(), interactive=True, ask=Mock(return_value="")), "skip")
        ask = Mock(side_effect=["yes", ""])
        self.assertEqual(manager.choose(None, None, inventory(), interactive=True, ask=ask), "gdm")
        self.assertIn("gdm (GNOME)", ask.call_args.args[0])

    def test_interactive_sddm_alternative(self):
        self.assertEqual(manager.choose(None, None, inventory(), interactive=True,
                                        ask=Mock(side_effect=["y", "sddm"])), "sddm")

    def test_interactive_existing_manager_is_preferred(self):
        state = inventory("sddm", "gdm", active="sddm", enabled="sddm")
        self.assertEqual(manager.choose(None, None, state, interactive=True,
                                        ask=Mock(side_effect=["yes", ""])), "sddm")

    def test_saved_opt_in_is_reused_and_skip_overrides_it(self):
        self.assertEqual(manager.choose(None, "gdm", inventory()), "gdm")
        self.assertEqual(manager.choose("skip", "gdm", inventory()), "skip")

    def test_existing_requires_a_detected_manager(self):
        with self.assertRaisesRegex(ValueError, "No existing"):
            manager.choose("existing", None, inventory())

    def test_ambiguous_installed_managers_require_selection(self):
        with self.assertRaisesRegex(ValueError, "Multiple"):
            manager.choose("existing", None, inventory("gdm", "sddm"))

    def test_existing_and_saved_choices_never_replace_another_manager(self):
        state = inventory("sddm", active="sddm", enabled="sddm")
        self.assertEqual(manager.choose("existing", None, state), "sddm")
        for requested, saved in (("gdm", None), (None, "gdm")):
            with self.assertRaisesRegex(ValueError, "Keeping the existing"):
                manager.choose(requested, saved, state)

    def test_detection_prefers_active_configured_manager_and_lists_installed(self):
        alias = self.base / "display-manager.service"
        alias.symlink_to(self.base / "sddm.service")

        def probe(command):
            if command[0] == "pacman":
                return "gdm\nsddm\ngreetd\nly\n"
            if "list-unit-files" in command:
                return "gdm.service disabled disabled\nsddm.service enabled disabled\ngreetd.service disabled disabled\nly@tty2.service disabled disabled\n"
            if "list-units" in command:
                return "sddm.service loaded active running Display Manager\n"
            return "graphical.target\n"

        with patch.object(manager, "probe", side_effect=probe):
            result = manager.inspect(alias)
        self.assertEqual(result["managers"][0]["name"], "sddm")
        self.assertTrue(result["managers"][0]["configured"])
        self.assertEqual({item["name"] for item in result["managers"]}, {"gdm", "sddm", "greetd", "ly"})
        self.assertEqual(next(item["unit"] for item in result["managers"] if item["name"] == "ly"), "ly@tty2.service")

    def test_unknown_configured_manager_is_preserved(self):
        alias = self.base / "display-manager.service"
        alias.symlink_to(self.base / "custom-login.service")
        with patch.object(manager, "probe", return_value=""):
            result = manager.inspect(alias)
        self.assertEqual(manager.choose("existing", None, result), "existing")
        with self.assertRaisesRegex(ValueError, "Keeping the existing"):
            manager.choose("gdm", None, result)

    def test_runtime_display_manager_alias_is_also_detected(self):
        system = self.base / "etc"
        runtime = self.base / "run"
        runtime.mkdir()
        (runtime / "display-manager.service").symlink_to(self.base / "custom-login.service")
        with patch.object(manager, "SYSTEM_UNIT_DIRS", (system, runtime)), patch.object(manager, "probe", return_value=""):
            result = manager.inspect()
        self.assertEqual(result["managers"][0]["unit"], "custom-login.service")
        with self.assertRaisesRegex(ValueError, "Keeping the existing"):
            manager.choose("gdm", None, result)

    def test_generated_display_manager_unit_is_not_overlooked(self):
        def probe(command):
            return "display-manager.service generated -\n" if "list-unit-files" in command else ""
        with patch.object(manager, "probe", side_effect=probe):
            result = manager.inspect(self.base / "absent-alias")
        self.assertEqual(result["managers"][0]["unit"], "display-manager.service")
        with self.assertRaisesRegex(ValueError, "Keeping the existing"):
            manager.choose("gdm", None, result)

    def test_alternative_package_providing_the_service_is_not_replaced(self):
        def probe(command):
            if command[0] == "pacman":
                return "gdm-git\n"
            if "list-unit-files" in command:
                return "gdm.service enabled disabled\n"
            return ""
        with patch.object(manager, "probe", side_effect=probe):
            result = manager.inspect(self.base / "absent-alias")
        self.assertTrue(result["managers"][0]["installed"])

    def test_failed_active_service_probe_is_not_treated_as_an_empty_system(self):
        with patch.object(manager, "probe", side_effect=lambda command: None if "list-units" in command else "graphical.target\n"):
            result = manager.inspect(self.base / "absent-alias")
        run = Mock()
        with self.assertRaisesRegex(ValueError, "Could not inspect"):
            manager.configure("gdm", run, inventory=result)
        run.assert_not_called()

    def test_gdm_install_enables_next_boot_without_start_or_force(self):
        run = Mock()
        with patch.object(manager, "session_entry", return_value=Path("/usr/share/wayland-sessions/hyprland.desktop")):
            manager.configure("gdm", run, inventory=inventory(target="multi-user.target"))
        commands = [call.args[0] for call in run.call_args_list]
        self.assertEqual(commands, [["sudo", "pacman", "-Syu", "--needed", "--", "gdm"],
                                    ["sudo", "systemctl", "enable", "--", "gdm.service"],
                                    ["sudo", "systemctl", "set-default", "graphical.target"]])
        self.assertFalse(any(arg in ("--now", "--force", "start", "stop", "restart", "disable") for command in commands for arg in command))

    def test_existing_enabled_manager_is_idempotent(self):
        run = Mock()
        with patch.object(manager, "session_entry", return_value=Path("session.desktop")):
            manager.configure("gdm", run, inventory=inventory("gdm", active="gdm", enabled="gdm"))
        run.assert_not_called()

    def test_installed_disabled_sddm_is_enabled_without_reinstalling(self):
        run = Mock()
        with patch.object(manager, "session_entry", return_value=Path("session.desktop")):
            manager.configure("sddm", run, inventory=inventory("sddm"))
        self.assertEqual([call.args[0] for call in run.call_args_list], [["sudo", "systemctl", "enable", "--", "sddm.service"]])

    def test_existing_active_greeter_is_enabled_for_next_boot(self):
        run = Mock()
        with patch.object(manager, "session_entry", return_value=Path("session.desktop")):
            manager.configure("greetd", run, inventory=inventory("greetd", active="greetd"))
        self.assertEqual([call.args[0] for call in run.call_args_list], [["sudo", "systemctl", "enable", "--", "greetd.service"]])

    def test_unconfigured_nonautomatic_greeter_is_not_enabled(self):
        with self.assertRaisesRegex(ValueError, "needs its greeter"):
            manager.choose("existing", None, inventory("greetd"))

    def test_skip_packages_and_skip_do_not_probe_or_change_services(self):
        with patch.object(manager, "inspect") as inspect:
            run = Mock()
            manager.configure("gdm", run, skip_packages=True)
            manager.configure("skip", run)
        inspect.assert_not_called()
        run.assert_not_called()

    def test_missing_session_stops_service_enable(self):
        run = Mock()
        with patch.object(manager, "session_entry", side_effect=ValueError("missing session")):
            with self.assertRaisesRegex(ValueError, "missing session"):
                manager.configure("gdm", run, inventory=inventory("gdm"))
        run.assert_not_called()

    def test_dry_run_only_emits_dry_commands_and_never_checks_host_session(self):
        run = Mock()
        with patch.object(manager, "session_entry") as entry:
            manager.configure("gdm", run, dry=True, inventory=inventory(target="multi-user.target"))
        entry.assert_not_called()
        self.assertEqual(len(run.call_args_list), 3)
        self.assertTrue(all(call.kwargs["dry"] for call in run.call_args_list))

    def test_unavailable_systemd_blocks_opt_in_mutations(self):
        run = Mock()
        with self.assertRaisesRegex(ValueError, "Could not inspect"):
            manager.configure("gdm", run, inventory=inventory(target=""))
        run.assert_not_called()

    def test_session_entry_requires_a_valid_application_entry(self):
        directory = self.base / "sessions"
        directory.mkdir()
        path = directory / "hyprland.desktop"
        for text in ("invalid", "[Desktop Entry]\nType=Application\n"):
            path.write_text(text)
            with self.assertRaisesRegex(ValueError, "missing or invalid"):
                manager.session_entry(directory)
        path.write_text("[Desktop Entry]\nType=Application\nExec=/usr/bin/start-hyprland\n")
        with patch.object(manager.shutil, "which", return_value="/usr/bin/start-hyprland"):
            self.assertEqual(manager.session_entry(directory), path)

    def test_session_entry_rejects_missing_executables(self):
        directory = self.base / "sessions"
        directory.mkdir()
        (directory / "hyprland.desktop").write_text("[Desktop Entry]\nType=Application\nExec=missing-compositor\n")
        with patch.object(manager.shutil, "which", return_value=None):
            with self.assertRaisesRegex(ValueError, "missing or invalid"):
                manager.session_entry(directory)

    def test_direct_hyprland_session_is_preferred_over_optional_uwsm(self):
        directory = self.base / "sessions"
        directory.mkdir()
        for name in ("hyprland-uwsm.desktop", "hyprland.desktop"):
            (directory / name).write_text("[Desktop Entry]\nType=Application\nExec=compositor\n")
        with patch.object(manager.shutil, "which", return_value="/usr/bin/compositor"):
            self.assertEqual(manager.session_entry(directory).name, "hyprland.desktop")

    def test_package_install_handoff_keeps_the_explicit_choice(self):
        args = velora.parser().parse_args(["install", "--login-manager", "gdm"])
        command = velora.install_command(Path("/usr/bin/velora"), args, [])
        self.assertEqual(command[command.index("--login-manager") + 1], "gdm")

    def test_successful_registration_persists_the_choice_and_relink_preserves_it(self):
        journal = self.base / "backup/journal.jsonl"
        journal.parent.mkdir()
        journal.touch()
        args = velora.parser().parse_args(["install", "--yes"])
        args.login_manager_choice = "gdm"
        with patch.object(velora, "run"):
            velora.register_installation(journal, args, [])
        self.assertEqual(velora.preferences()["login_manager"], "gdm")
        del args.login_manager_choice
        with patch.object(velora, "run"):
            velora.register_installation(journal, args, [])
        self.assertEqual(velora.preferences()["login_manager"], "gdm")
