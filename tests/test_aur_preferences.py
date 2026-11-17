"""Offline regressions for AUR overrides; no runtime subprocesses are allowed."""
import contextlib
import io
import json
import os
from pathlib import Path
from unittest.mock import patch

from test_velora import IsolatedTest, velora


class AurPreferenceTests(IsolatedTest):
    def setUp(self):
        super().setUp()
        for target, name, options in (
            (velora.subprocess, "run", {"side_effect": AssertionError("Unexpected subprocess.run")}),
            (velora.subprocess, "Popen", {"side_effect": AssertionError("Unexpected subprocess.Popen")}),
            (velora.os, "geteuid", {"return_value": 1000}),
            (velora.sys.stdin, "isatty", {"return_value": False}),
            (velora, "package_metadata", {"return_value": {}}),
        ):
            mock = patch.object(target, name, **options)
            mock.start()
            self.addCleanup(mock.stop)
        environment = patch.dict(os.environ, VELORA_GUI_UPDATE="0", VELORA_PARENT_OPERATION="")
        environment.start()
        self.addCleanup(environment.stop)

    def save(self, **values):
        velora.write_json(velora.state_dir() / "installation.json", values)

    def assert_aur_flag(self, command, skip):
        expected = [] if skip is None else ["--skip-aur" if skip else "--with-aur"]
        self.assertEqual([flag for flag in command if flag in ("--skip-aur", "--with-aur")], expected)

    def test_flags_are_tristate_and_mutually_exclusive_for_each_command(self):
        for command in ("install", "deps", "doctor"):
            for flags, expected in (([], None), (["--skip-aur"], True), (["--with-aur"], False)):
                with self.subTest(command=command, flags=flags):
                    self.assertIs(velora.parser().parse_args([command, *flags]).skip_aur, expected)
            for flags in (("--skip-aur", "--with-aur"), ("--with-aur", "--skip-aur")):
                with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
                    velora.parser().parse_args([command, *flags])
                self.assertEqual(error.exception.code, 2)

    def test_install_command_preserves_explicit_choices_and_existing_options(self):
        for flags, skip in (([], None), (["--skip-aur"], True), (["--with-aur"], False)):
            args = velora.parser().parse_args(["install", *flags, "--skip-packages", "--no-updates", "--no-reload",
                                              "--login-manager", "existing", "--login-theme", "velora"])
            args.source_packages = ["quickshell"]
            command = velora.install_command("/usr/bin/velora", args, ["toolbox"])
            self.assert_aur_flag(command, skip)
            for flag in ("--skip-packages", "--no-updates", "--no-reload"):
                self.assertIn(flag, command)
            for flag, value in (("--login-manager", "existing"), ("--login-theme", "velora"),
                                ("--build-from-source", "quickshell"), ("--without", "toolbox")):
                self.assertEqual(command[command.index(flag) + 1], value)
            child = velora.parser().parse_args(command[1:])
            self.assertIs(child.skip_aur, skip)

    @contextlib.contextmanager
    def isolated_install(self):
        with contextlib.ExitStack() as stack:
            mocks = {}
            for name in ("preflight", "run", "install_dependencies", "build_native_helper", "build_file_dialog",
                         "install_fonts", "verify_runtime", "configure_greeter", "prepare_source_tree"):
                mocks[name] = stack.enter_context(patch.object(velora, name))
            mocks["link_configuration"] = stack.enter_context(patch.object(velora, "link_configuration", return_value=self.base))
            stack.enter_context(patch.object(velora, "bluetooth_adapters_present", return_value=False))
            stack.enter_context(patch.object(velora.login_manager, "inspect", return_value={}))
            stack.enter_context(patch.object(velora.login_manager, "choose", return_value="skip"))
            stack.enter_context(patch.object(velora.login_manager, "describe"))
            stack.enter_context(patch.object(velora.login_manager, "configure"))
            yield mocks

    def test_install_and_deps_respect_saved_explicit_choices_and_exclusions(self):
        for command in ("install", "deps"):
            # None models installations created before the AUR preference was saved.
            for saved in (None, False, True):
                for flags, expected in (([], bool(saved)), (["--skip-aur"], True), (["--with-aur"], False)):
                    for skip_packages in (False, True):
                        with self.subTest(command=command, saved=saved, flags=flags, skip_packages=skip_packages):
                            saved_values = {"without": ["toolbox", "live-wallpapers"]}
                            if saved is not None:
                                saved_values["skip_aur"] = saved
                            self.save(**saved_values)
                            options = [command, "--yes", *flags, *(["--skip-packages"] if skip_packages else [])]
                            with self.isolated_install() as mocks:
                                self.assertEqual(velora.main(options), 0)
                            features, args = mocks["verify_runtime"].call_args.args
                            self.assertIs(args.skip_aur, expected)
                            self.assertIs(args.skip_packages, skip_packages)
                            self.assertNotIn("toolbox", features)
                            self.assertNotIn("live-wallpapers", features)
                            if command == "install" and skip_packages:
                                mocks["install_dependencies"].assert_not_called()
                            else:
                                self.assertIs(mocks["install_dependencies"].call_args.args[0].skip_aur, expected)
                            mocks["install_fonts"].assert_called_once()
                            if command == "install":
                                self.assertEqual(mocks["link_configuration"].call_args.args[1], ["live-wallpapers", "toolbox"])
                                mocks["build_file_dialog"].assert_called_once()
                                mocks["configure_greeter"].assert_called_once_with("keep")
                            # deps must not silently persist an invocation-only override.
                            self.assertEqual(velora.preferences(), saved_values)

    def test_install_registers_resolved_choice_without_losing_saved_selection(self):
        for flags, expected in (([], True), (["--with-aur"], False), (["--skip-aur"], True)):
            with self.subTest(flags=flags):
                self.save(skip_aur=True, without=["toolbox"], login_theme="velora")
                with self.isolated_install() as mocks:
                    mocks["link_configuration"].side_effect = lambda args, without: (
                        velora.register_installation(self.base / "journal", args, without) or self.base)
                    with patch.object(velora, "journal_file") as journal, patch.object(velora.shutil, "which", return_value=None):
                        velora.main(["install", "--yes", *flags])
                    states = [json.loads(call.kwargs["content"]) for call in journal.call_args_list
                              if call.args[1] == velora.state_dir() / "installation.json"]
                self.assertEqual(len(states), 1)
                self.assertIs(states[0]["skip_aur"], expected)
                self.assertEqual(states[0]["without"], ["toolbox"])
                self.assertEqual(states[0]["login_theme"], "velora")

    def test_build_package_reinstall_forwards_resolved_override_and_selection(self):
        for flags, expected in (([], True), (["--with-aur"], False), (["--skip-aur"], True)):
            with self.subTest(flags=flags):
                self.save(skip_aur=True, without=["toolbox"], login_theme="velora")
                with self.isolated_install() as mocks, patch.object(velora, "build_metadata", return_value={}), \
                        patch.object(velora.builds, "build_package") as build:
                    self.assertEqual(velora.main(["install", "--yes", "--build-package", *flags]), 0)
                self.assertTrue(build.call_args.kwargs["install"])
                command = mocks["run"].call_args.args[0]
                self.assertEqual(command[0], Path("/usr/bin/velora"))
                self.assert_aur_flag(command, expected)
                self.assertEqual(command[command.index("--without") + 1], "toolbox")
                self.assertEqual(command[command.index("--login-theme") + 1], "velora")
                mocks["link_configuration"].assert_not_called()

    def test_updated_tree_preserves_old_and_saved_preferences_including_gui(self):
        for saved in (None, False, True):
            for gui in (False, True):
                with self.subTest(saved=saved, gui=gui):
                    values = dict(without=["toolbox", "live-wallpapers"], skip_packages=True,
                                  no_updates=True, login_theme="velora", login_manager="existing",
                                  build_from_source=["quickshell"])
                    if saved is not None:
                        values["skip_aur"] = saved
                    self.save(**values)
                    with patch.dict(os.environ, VELORA_GUI_UPDATE="1" if gui else "0"), patch.object(velora, "run") as run:
                        velora.install_updated_tree(Path("/usr/bin/velora"))
                    command = run.call_args.args[0]
                    self.assert_aur_flag(command, saved)
                    self.assertEqual("--skip-packages" in command, not gui)
                    self.assertEqual("--no-reload" in command, gui)
                    for flag, value in (("--without", "toolbox,live-wallpapers"), ("--login-theme", "velora"),
                                        ("--login-manager", "existing"), ("--build-from-source", "quickshell")):
                        self.assertEqual(command[command.index(flag) + 1], value)
                    self.assertEqual(velora.preferences(), values)

    def test_update_forwards_saved_choice_through_checkout_package_and_retry_paths(self):
        for kind in ("checkout", "package"):
            for retry in (False, True):
                for skip in (False, True):
                    with self.subTest(kind=kind, retry=retry, skip=skip):
                        self.save(skip_aur=skip, without=["toolbox"])
                        status = dict(current="a" * 40, target="b" * 40, available=not retry,
                                      current_version="0.2.0", latest_version="0.2.1", dirty=False, diverged=False,
                                      installation_type=kind, branch="main", repository="https://example.invalid/velora")
                        velora.write_json(velora.state_dir() / "last-update.json",
                                          {"complete": False, "target": status["current"]})
                        with patch.object(velora, "update_status", return_value=status), \
                                patch.object(velora, "run") as run, patch.object(velora, "git"), \
                                patch.object(velora, "generated_files_kept", side_effect=contextlib.nullcontext), \
                                patch.object(velora, "build_metadata", return_value={"version": "0.2.1"}), \
                                patch.object(velora.builds, "build_package") as build:
                            velora.update(velora.parser().parse_args(["update"]))
                        installs = [call.args[0] for call in run.call_args_list if len(call.args[0]) > 1 and call.args[0][1] == "install"]
                        self.assertEqual(len(installs), 1)
                        self.assert_aur_flag(installs[0], skip)
                        self.assertEqual(installs[0][0], Path("/usr/bin/velora") if kind == "package" else velora.ROOT / "velora")
                        self.assertEqual(build.call_count, int(kind == "package" and not retry))
                        self.assertTrue(velora.read_json(velora.state_dir() / "last-update.json")["complete"])

    def test_with_aur_allows_saved_aur_source_build_but_skip_still_conflicts(self):
        self.save(skip_aur=True, build_from_source=["mpvpaper"])
        with self.isolated_install() as mocks:
            velora.main(["deps", "--with-aur"])
            self.assertEqual(mocks["install_dependencies"].call_args.args[0].source_packages, ["mpvpaper"])
        with self.isolated_install(), self.assertRaisesRegex(velora.VeloraError, "--skip-aur conflicts"):
            velora.main(["deps", "--skip-aur"])

    def test_doctor_fails_only_for_enabled_missing_aur_in_saved_override_matrix(self):
        venv = velora.xdg("XDG_STATE_HOME", ".local/state") / "quickshell/.venv/bin/python"
        venv.parent.mkdir(parents=True)
        venv.touch()
        for saved in (None, False, True):
            for flags, skip in (([], bool(saved)), (["--skip-aur"], True), (["--with-aur"], False)):
                for missing in (False, True):
                    with self.subTest(saved=saved, flags=flags, missing=missing):
                        self.save(**({} if saved is None else {"skip_aur": saved}))
                        with patch.object(velora, "package_plan", side_effect=lambda features, skip_aur: ([], ["breeze-plus"] if missing and not skip_aur else [])) as plan, \
                                patch.object(velora, "runtime_problems", return_value=[]), \
                                patch.object(velora, "font_installed", return_value=True), \
                                patch.object(velora, "service_active", return_value=True), \
                                patch.object(velora, "connection_service", return_value="/usr/bin/velora-connectivityd"), \
                                patch.object(velora, "stale_links", return_value=[]), \
                                patch.object(velora.shutil, "which", return_value="/usr/bin/tool"):
                            args = velora.parser().parse_args(["doctor", *flags])
                            if missing and not skip:
                                with self.assertRaisesRegex(velora.VeloraError, "Some checks need attention"):
                                    velora.doctor(args)
                            else:
                                velora.doctor(args)
                            self.assertIs(plan.call_args.kwargs["skip_aur"], skip)
