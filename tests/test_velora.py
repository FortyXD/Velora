"""Regression tests using temporary configuration roots and local Git remotes."""
import argparse
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

PROJECT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("velora_cli", PROJECT / "scripts/velora.py")
velora = importlib.util.module_from_spec(spec)
spec.loader.exec_module(velora)


def git(directory, *args):
    return subprocess.run(["git", "-c", "user.name=Velora Test", "-c", "user.email=test@example.invalid", *args],
                          cwd=directory, check=True, text=True, capture_output=True).stdout.strip()


class IsolatedTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="velora tests '")
        self.base = Path(self.temporary.name)
        self.environment = patch.dict(os.environ, {
            "XDG_CONFIG_HOME": str(self.base / "config"),
            "XDG_DATA_HOME": str(self.base / "data"),
            "XDG_STATE_HOME": str(self.base / "state"),
            "XDG_CACHE_HOME": str(self.base / "cache"),
        })
        self.environment.start()
        self.output = contextlib.redirect_stdout(io.StringIO())
        self.output.__enter__()

    def tearDown(self):
        self.output.__exit__(None, None, None)
        self.environment.stop()
        self.temporary.cleanup()


class DependencyTests(IsolatedTest):
    def test_missing_packages_are_deduplicated_and_skip_aur_is_respected(self):
        features = {"a": {"repo": ["git", "kitty"], "aur": ["mpvpaper"]},
                    "b": {"repo": ["kitty", "python"], "aur": ["mpvpaper"]}}
        installed = {"git", "python"}
        with patch.object(velora, "missing_packages", side_effect=lambda packages: [pkg for pkg in packages if pkg not in installed]):
            self.assertEqual(velora.package_plan(features), (["kitty"], ["mpvpaper"]))
            self.assertEqual(velora.package_plan(features, True), (["kitty"], []))

    def test_font_step_skips_an_installed_font_and_only_warns_on_failure(self):
        with patch.object(velora, "font_installed", return_value=True), patch.object(velora, "run") as run:
            velora.install_fonts()
        run.assert_not_called()
        with patch.object(velora, "font_installed", return_value=False), \
                patch.object(velora, "run", side_effect=velora.VeloraError("offline")), \
                contextlib.redirect_stderr(io.StringIO()) as errors:
            velora.install_fonts()
        self.assertIn("Google Sans Flex was not installed", errors.getvalue())

    def test_packages_provided_by_others_count_as_installed(self):
        # pacman -T lists only what nothing installed provides, e.g. not curl when curl-git is installed
        completed = velora.subprocess.CompletedProcess([], 127, stdout="kitty\n", stderr="")
        with patch.object(velora.shutil, "which", return_value="/usr/bin/pacman"), \
                patch.object(velora.subprocess, "run", return_value=completed) as pacman:
            self.assertEqual(velora.missing_packages(["curl", "kitty"]), ["kitty"])
        self.assertEqual(pacman.call_args.args[0], ["pacman", "-T", "--", "curl", "kitty"])

    def test_required_or_unknown_components_are_rejected(self):
        for excluded in ("desktop", "not-a-component"):
            args = velora.parser().parse_args(["install", "--without", excluded])
            with self.assertRaises(velora.VeloraError):
                velora.selected_features(args)

    def test_component_selection_is_reused_without_reintroducing_excluded_features(self):
        velora.write_json(velora.state_dir() / "installation.json", {"without": ["toolbox"]})
        args = velora.parser().parse_args(["install"])
        features, excluded = velora.selected_features(args)
        self.assertNotIn("toolbox", features)
        self.assertEqual(excluded, ["toolbox"])

    def test_dry_dependency_plan_never_executes_package_commands(self):
        args = velora.parser().parse_args(["deps", "--dry-run"])
        with patch.object(velora, "package_plan", return_value=(["git"], ["mpvpaper"])), \
             patch.object(velora.shutil, "which", return_value=None), patch.object(velora, "run") as run:
            velora.install_dependencies(args, {"test": {}})
            self.assertTrue(run.call_args_list)
            self.assertTrue(all(call.kwargs.get("dry") for call in run.call_args_list))
            self.assertIn("-Syu", run.call_args_list[0].args[0])

    def test_paru_is_used_when_yay_is_unavailable(self):
        args = velora.parser().parse_args(["deps"])
        with patch.object(velora, "package_plan", return_value=([], ["mpvpaper"])), \
             patch.object(velora.shutil, "which", side_effect=lambda name: "/usr/bin/paru" if name == "paru" else None), \
             patch.object(velora, "run") as run:
            velora.install_dependencies(args, {})
            self.assertEqual(run.call_args_list[0].args[0][0], "/usr/bin/paru")


class InstallerTests(IsolatedTest):
    def setUp(self):
        super().setUp()
        self.repo = self.base / "checkout with spaces"
        (self.repo / "scripts").mkdir(parents=True)
        shutil.copy(PROJECT / "scripts/install.sh", self.repo / "scripts/install.sh")
        for name in ("hypr", "quickshell", "kitty", "foot", "fuzzel", "matugen", "fish", "fontconfig", "Kvantum",
                     "kde-material-you-colors", "mpv", "wlogout", "xdg-desktop-portal", "zshrc.d", "tmux", "illogical-impulse"):
            (self.repo / "dots/.config" / name).mkdir(parents=True)
        files = ["home/.zshrc", "home/.tmux.conf", "dots/.config/starship.toml",
                 "dots/.config/wireplumber/wireplumber.conf.d/51-auto-audio-routes.conf",
                 "dots/.local/share/wireplumber/scripts/folis/prefer-plugged-routes.lua",
                 "dots/.local/share/icons/illogical-impulse.svg",
                 "dots/.local/share/kxmlgui5/dolphin/dolphinui.rc",
                 "dots/.local/share/folis/dolphin-create-archive.py",
                 "dots/.local/share/dbus-1/services/org.freedesktop.FileManager1.service",
                 "dots/.local/share/applications/drracket.desktop",
                 "dots/.config/quickshell/ii/modules/common/widgets/shapes/ShapeCanvas.qml"]
        for name in files:
            path = self.repo / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("fixture\n")
        (self.repo / "dots/.config/illogical-impulse/config.example.json").write_text('{"default": true}\n')
        self.home = self.base / "target user"
        self.home.mkdir()
        self.backup = self.base / "state/velora/backups/test"
        self.backup.mkdir(parents=True)
        self.journal = self.backup / "journal.jsonl"
        self.journal.touch()
        self.env = dict(os.environ, VELORA_TARGET_HOME=str(self.home), VELORA_BACKUP_ROOT=str(self.backup),
                        VELORA_INSTALL_JOURNAL=str(self.journal))

    def link(self, *options):
        return subprocess.run(["bash", str(self.repo / "scripts/install.sh"), "--no-reload", *options],
                              env=self.env, text=True, capture_output=True)

    def test_install_and_repeat_preserve_existing_shell_settings(self):
        config = Path(self.env["XDG_CONFIG_HOME"]) / "illogical-impulse"
        config.mkdir(parents=True)
        (config / "config.json").write_text('{"personal": true}\n')
        self.assertEqual(self.link().returncode, 0)
        self.assertEqual(json.loads((config / "config.json").read_text()), {"personal": True})
        before = self.journal.read_text()
        self.assertEqual(self.link().returncode, 0)
        self.assertEqual(self.journal.read_text(), before)
        self.assertEqual(json.loads((config / "config.json").read_text()), {"personal": True})

    def test_clean_install_links_right_click_defaults_without_overriding_them(self):
        hypr_source = self.repo / "dots/.config/hypr"
        for name in ("hyprland/general.lua", "custom/shell_settings_default.lua",
                     "custom/shell_settings_default.json"):
            source = PROJECT / "dots/.config/hypr" / name
            destination = hypr_source / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(source, destination)

        result = self.link()
        self.assertEqual(result.returncode, 0, result.stderr)
        installed = Path(self.env["XDG_CONFIG_HOME"]) / "hypr"
        self.assertTrue(installed.is_symlink())
        touchpad = (installed / "hyprland/general.lua").read_text().split("touchpad = {", 1)[1].split("}", 1)[0]
        self.assertIn("tap_to_click = true", touchpad)
        self.assertIn("clickfinger_behavior = false", touchpad)
        overrides = json.loads((installed / "custom/shell_settings.json").read_text())
        self.assertNotIn("input:touchpad:tap_to_click", overrides)
        self.assertNotIn("input:touchpad:clickfinger_behavior", overrides)
        generated = (installed / "custom/shell_settings.lua").read_text()
        self.assertNotIn("tap_to_click", generated)
        self.assertNotIn("clickfinger_behavior", generated)

    def test_backups_restore_files_and_keep_later_edits(self):
        zshrc = self.home / ".zshrc"
        zshrc.write_text("original\n")
        self.assertEqual(self.link().returncode, 0)
        self.assertTrue(zshrc.is_symlink())
        zshrc.unlink()
        zshrc.write_text("later edit\n")
        velora.restore_journal(self.journal)
        self.assertEqual(zshrc.read_text(), "original\n")
        recovered = [file.read_text() for directory in self.backup.glob("before-restore-*")
                     for file in directory.iterdir() if file.is_file() and not file.is_symlink()]
        self.assertIn("later edit\n", recovered)

    def test_partial_link_failure_can_restore_original_directories(self):
        hypr = Path(self.env["XDG_CONFIG_HOME"]) / "hypr"
        hypr.mkdir(parents=True)
        (hypr / "personal.lua").write_text("personal settings")
        (self.repo / "dots/.config/starship.toml").unlink()
        result = self.link()
        self.assertNotEqual(result.returncode, 0)
        velora.restore_journal(self.journal)
        self.assertFalse(hypr.is_symlink())
        self.assertEqual((hypr / "personal.lua").read_text(), "personal settings")
        self.assertFalse(os.path.lexists(self.home / ".zshrc"))

    def test_dry_run_changes_neither_targets_nor_source(self):
        before = self.journal.read_text()
        self.assertEqual(self.link("--dry-run").returncode, 0)
        self.assertEqual(self.journal.read_text(), before)
        self.assertFalse(os.path.lexists(self.home / ".zshrc"))
        self.assertFalse((self.repo / "dots/.config/illogical-impulse/config.json").exists())

    def test_installer_automatically_restores_after_registration_failure(self):
        shutil.copytree(PROJECT / "dependencies", self.repo / "dependencies")
        original = self.home / ".zshrc"
        original.write_text("keep this")
        args = velora.parser().parse_args(["install", "--yes", "--skip-packages"])
        real_run = velora.run

        def run(command, **kwargs):
            if command[:3] == ["git", "submodule", "update"]:
                return ""
            kwargs["env"] = dict(kwargs.get("env", os.environ), VELORA_TARGET_HOME=str(self.home))
            kwargs["capture"] = True
            return real_run(command, **kwargs)

        with patch.object(velora, "ROOT", self.repo), patch.object(velora, "run", side_effect=run), \
             patch.object(velora, "install_fonts"), \
             patch.object(velora, "register_installation", side_effect=velora.VeloraError("registration failed")):
            with self.assertRaisesRegex(velora.VeloraError, "registration failed"):
                velora.install(args)
        self.assertEqual(original.read_text(), "keep this")
        self.assertFalse(original.is_symlink())

    def test_relink_repairs_links_after_the_checkout_is_renamed(self):
        (self.repo / "velora").write_text("#!/bin/sh\nexit 0\n")
        (self.repo / "velora").chmod(0o755)
        real_run = velora.run

        def run(command, **kwargs):
            if command[0] == "systemctl":
                return ""
            kwargs["capture"] = True
            return real_run(command, **kwargs)

        with patch.dict(os.environ, {"VELORA_TARGET_HOME": str(self.home)}), patch.object(velora, "run", side_effect=run), \
                patch.object(velora.Path, "home", return_value=self.home):
            with patch.object(velora, "ROOT", self.repo):
                velora.link_configuration(velora.parser().parse_args(["install", "--no-reload"]), [])
                self.assertEqual(velora.stale_links(), [])
            moved = self.base / "renamed checkout"
            self.repo.rename(moved)
            hypr = Path(self.env["XDG_CONFIG_HOME"]) / "hypr"
            self.assertFalse(hypr.exists())  # Dangling, like after renaming the folder
            with patch.object(velora, "ROOT", moved):
                self.assertIn(str(hypr), velora.stale_links())
                velora.relink(velora.parser().parse_args(["relink", "--no-reload"]))
                self.assertEqual(velora.stale_links(), [])
        self.assertEqual(hypr.resolve(), moved / "dots/.config/hypr")
        self.assertEqual((self.home / ".local/bin/velora").resolve(), moved / "velora")
        self.assertEqual(velora.preferences()["repository"], str(moved))
        service = (Path(self.env["XDG_CONFIG_HOME"]) / "systemd/user/velora-update.service").read_text()
        self.assertIn(str(moved), service)
        self.assertNotIn(str(self.repo), service)

    def test_restore_refuses_missing_backup_before_changing_anything(self):
        target = self.home / "keep"
        target.write_text("keep this")
        self.journal.write_text(json.dumps({"target": str(target), "backup": str(self.backup / "missing")}) + "\n")
        with self.assertRaisesRegex(velora.VeloraError, "Backup is missing"):
            velora.restore_journal(self.journal)
        self.assertEqual(target.read_text(), "keep this")

    def test_command_launcher_and_update_timer_are_registered_and_restorable(self):
        (self.repo / "velora").write_text("#!/bin/sh\nexit 0\n")
        (self.repo / "velora").chmod(0o755)
        args = velora.parser().parse_args(["install", "--yes", "--skip-packages"])
        with patch.object(velora, "ROOT", self.repo), patch.object(velora.Path, "home", return_value=self.home), \
             patch.object(velora, "run"):
            velora.register_installation(self.journal, args, ["toolbox"])
        command = self.home / ".local/bin/velora"
        self.assertTrue(command.is_symlink())
        self.assertEqual(command.resolve(), self.repo / "velora")
        config = Path(self.env["XDG_CONFIG_HOME"])
        timer = config / "systemd/user/timers.target.wants/velora-update.timer"
        self.assertTrue(timer.is_symlink())
        launcher = Path(self.env["XDG_DATA_HOME"]) / "applications/velora-update.desktop"
        if shutil.which("desktop-file-validate"):
            subprocess.run(["desktop-file-validate", str(launcher)], check=True, capture_output=True, text=True)
        velora.restore_journal(self.journal)
        self.assertFalse(os.path.lexists(command))
        self.assertFalse(os.path.lexists(timer))
        self.assertFalse(launcher.exists())

    @unittest.skipUnless(shutil.which("systemd-analyze"), "systemd-analyze is unavailable")
    def test_generated_systemd_units_validate(self):
        (self.repo / "velora").write_text("#!/bin/sh\nexit 0\n")
        (self.repo / "velora").chmod(0o755)
        args = velora.parser().parse_args(["install", "--yes", "--skip-packages"])
        with patch.object(velora, "ROOT", self.repo), patch.object(velora.Path, "home", return_value=self.home), \
             patch.object(velora, "run"):
            velora.register_installation(self.journal, args, [])
        units = Path(self.env["XDG_CONFIG_HOME"]) / "systemd/user"
        result = subprocess.run(["systemd-analyze", "--generators=no", "verify",
                                 str(units / "velora-update.service"), str(units / "velora-update.timer")],
                                capture_output=True, text=True)
        if result.returncode and all(
            line.startswith(("Failed to turn off SO_PASSRIGHTS", "Failed to enable SO_PASSCRED"))
            and "Operation not permitted" in line
            for line in result.stderr.splitlines() if line
        ) and result.stderr:
            self.skipTest("Sandbox blocks systemd user-manager socket options")
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_no_updates_removes_an_enabled_timer_and_restores_it_on_rollback(self):
        config = Path(self.env["XDG_CONFIG_HOME"])
        timer = config / "systemd/user/timers.target.wants/velora-update.timer"
        timer.parent.mkdir(parents=True)
        timer.symlink_to(config / "systemd/user/velora-update.timer")
        args = velora.parser().parse_args(["install", "--yes", "--skip-packages", "--no-updates"])
        with patch.object(velora, "ROOT", self.repo), patch.object(velora.Path, "home", return_value=self.home), \
             patch.object(velora, "run"):
            velora.register_installation(self.journal, args, [])
        self.assertFalse(os.path.lexists(timer))
        velora.restore_journal(self.journal)
        self.assertTrue(timer.is_symlink())


class UpdateTests(IsolatedTest):
    def setUp(self):
        super().setUp()
        self.remote = self.base / "remote.git"
        self.author = self.base / "author"
        self.checkout = self.base / "checkout"
        git(self.base, "init", "--bare", "--initial-branch=main", str(self.remote))
        git(self.base, "clone", str(self.remote), str(self.author))
        (self.author / "tracked.txt").write_text("initial\n")
        git(self.author, "add", ".")
        git(self.author, "commit", "-m", "Initial")
        git(self.author, "push", "-u", "origin", "main")
        git(self.base, "clone", str(self.remote), str(self.checkout))
        self.root_patch = patch.object(velora, "ROOT", self.checkout)
        self.root_patch.start()

    def tearDown(self):
        self.root_patch.stop()
        super().tearDown()

    def remote_update(self):
        (self.author / "tracked.txt").write_text("remote update\n")
        git(self.author, "add", ".")
        git(self.author, "commit", "-m", "Remote update")
        git(self.author, "push")

    def args(self, *extra):
        return velora.parser().parse_args(["update", *extra])

    def test_background_check_records_availability_without_installing(self):
        before = git(self.checkout, "rev-parse", "HEAD")
        self.remote_update()
        velora.update(self.args("--check"))
        self.assertEqual(git(self.checkout, "rev-parse", "HEAD"), before)
        self.assertEqual((self.checkout / "tracked.txt").read_text(), "initial\n")
        status = velora.read_json(velora.state_dir() / "update.json")
        self.assertTrue(status["available"])
        self.assertEqual(status["behind"], 1)

    def test_dirty_checkout_is_preserved(self):
        self.remote_update()
        tracked = self.checkout / "tracked.txt"
        tracked.write_text("local changes\n")
        with self.assertRaisesRegex(velora.VeloraError, "Local changes"):
            velora.update(self.args())
        self.assertEqual(tracked.read_text(), "local changes\n")

    def test_untracked_work_is_preserved(self):
        self.remote_update()
        local = self.checkout / "untracked.txt"
        local.write_text("new local work")
        with self.assertRaisesRegex(velora.VeloraError, "Local changes"):
            velora.update(self.args())
        self.assertEqual(local.read_text(), "new local work")

    def test_diverged_history_is_rejected(self):
        (self.checkout / "local.txt").write_text("local commit")
        git(self.checkout, "add", ".")
        git(self.checkout, "commit", "-m", "Local change")
        self.remote_update()
        head = git(self.checkout, "rev-parse", "HEAD")
        with self.assertRaisesRegex(velora.VeloraError, "diverged"):
            velora.update(self.args())
        self.assertEqual(git(self.checkout, "rev-parse", "HEAD"), head)

    def test_dry_run_does_not_fetch_or_create_state(self):
        self.remote_update()
        velora.update(self.args("--dry-run"))
        self.assertFalse(velora.state_dir().exists())
        self.assertEqual(velora.update_status(fetch=False)["behind"], 0)

    def test_failed_fetch_preserves_previous_information_with_error(self):
        velora.write_json(velora.state_dir() / "update.json", {"available": True, "target": "known-target"})
        git(self.checkout, "remote", "set-url", "origin", str(self.base / "missing.git"))
        with self.assertRaises(velora.VeloraError):
            velora.update(self.args("--check"))
        status = velora.read_json(velora.state_dir() / "update.json")
        self.assertTrue(status["available"])
        self.assertEqual(status["target"], "known-target")
        self.assertTrue(status["error"])

    def test_update_runs_new_installer_and_reuses_component_preferences(self):
        self.remote_update()
        velora.write_json(velora.state_dir() / "installation.json", {"without": ["toolbox"], "skip_aur": True})
        real_run = velora.run
        installer_commands = []

        def run(command, **kwargs):
            if Path(command[0]).name == "velora":
                installer_commands.append(command)
                return ""
            return real_run(command, **kwargs)

        with patch.object(velora, "run", side_effect=run):
            velora.update(self.args())
        self.assertEqual((self.checkout / "tracked.txt").read_text(), "remote update\n")
        self.assertIn("--skip-aur", installer_commands[0])
        self.assertIn("toolbox", installer_commands[0])
        self.assertTrue(velora.read_json(velora.state_dir() / "last-update.json")["complete"])

    def test_generated_files_survive_the_update_that_stops_tracking_them(self):
        colors = "dots/.config/hypr/hyprland/colors.lua"
        (self.author / colors).parent.mkdir(parents=True)
        (self.author / colors).write_text("shipped colors\n")
        git(self.author, "add", ".")
        git(self.author, "commit", "-m", "Track colors")
        git(self.author, "push")
        git(self.checkout, "pull")
        (self.checkout / colors).write_text("colors from my wallpaper\n")  # Rewritten by the desktop
        git(self.author, "rm", "--cached", colors)
        (self.author / ".gitignore").write_text("/" + colors + "\n")
        git(self.author, "add", ".gitignore")
        git(self.author, "commit", "-m", "Stop tracking colors")
        git(self.author, "push")
        real_run = velora.run

        def run(command, **kwargs):
            return "" if Path(command[0]).name == "velora" else real_run(command, **kwargs)

        with patch.object(velora, "run", side_effect=run):
            velora.update(self.args())
        self.assertEqual((self.checkout / colors).read_text(), "colors from my wallpaper\n")
        self.assertEqual(git(self.checkout, "ls-files", colors), "")
        self.assertFalse(velora.update_status(fetch=False)["dirty"])

    def test_failed_install_records_incomplete_update_for_recovery(self):
        self.remote_update()
        previous = git(self.checkout, "rev-parse", "HEAD")
        real_run = velora.run

        def run(command, **kwargs):
            if Path(command[0]).name == "velora":
                raise velora.VeloraError("Simulated package failure")
            return real_run(command, **kwargs)

        with patch.object(velora, "run", side_effect=run):
            with self.assertRaisesRegex(velora.VeloraError, "installation did not finish"):
                velora.update(self.args())
        record = velora.read_json(velora.state_dir() / "last-update.json")
        self.assertEqual(record["previous"], previous)
        self.assertFalse(record["complete"])

    def test_release_check_resolves_the_tag_rather_than_unreleased_branch_changes(self):
        self.remote_update()
        released = git(self.author, "rev-parse", "HEAD")
        git(self.author, "tag", "v0.2.0")
        git(self.author, "push", "origin", "v0.2.0")
        (self.author / "tracked.txt").write_text("unreleased changes\n")
        git(self.author, "add", ".")
        git(self.author, "commit", "-m", "Unreleased change")
        git(self.author, "push")
        with patch.object(velora, "latest_release", return_value={"version": "v0.2.0", "url": ""}):
            velora.update(self.args("--check", "--channel", "release"))
        status = velora.read_json(velora.state_dir() / "update.json")
        self.assertEqual(status["target"], released)
        self.assertTrue(status["available"])
        self.assertEqual((self.checkout / "tracked.txt").read_text(), "initial\n")


class ConcurrencyTests(IsolatedTest):
    def test_operations_cannot_modify_configuration_concurrently(self):
        with velora.operation_lock():
            with self.assertRaisesRegex(velora.VeloraError, "Another Velora operation"):
                with velora.operation_lock():
                    self.fail("The second operation should not acquire the lock")


class TouchpadDefaultsTests(unittest.TestCase):
    def test_right_click_works_with_a_corner_click_or_two_finger_tap(self):
        source = (PROJECT / "dots/.config/hypr/hyprland/general.lua").read_text()
        touchpad = source.split("touchpad = {", 1)[1].split("}", 1)[0]
        self.assertIn("tap_to_click = true", touchpad)
        self.assertIn("clickfinger_behavior = false", touchpad)

        settings = (PROJECT / "dots/.config/quickshell/ii/modules/settings/MouseConfig.qml").read_text()
        self.assertRegex(settings, r'option: "input:touchpad:tap_to_click"\s+fallback: true')
        self.assertRegex(settings, r'option: "input:touchpad:clickfinger_behavior"\s+fallback: false')
        self.assertIn('title: Translation.tr("Physical right click")', settings)
        self.assertRegex(settings, r'displayName: Translation.tr\("Bottom-right corner"\).*value: false')
        self.assertRegex(settings, r'displayName: Translation.tr\("Two-finger click"\).*value: true')


if __name__ == "__main__":
    unittest.main()
