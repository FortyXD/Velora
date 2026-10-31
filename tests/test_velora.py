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
            "HOME": str(self.base / "home"),
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


class NativeToolsTests(IsolatedTest):
    def fake_build(self, command, env=None, dry=False):
        release = Path(env["CARGO_TARGET_DIR"]) / "release"
        release.mkdir(parents=True, exist_ok=True)
        for name in velora.NATIVE_BINARIES:
            (release / name).write_text(name)
            (release / name).chmod(0o755)

    def test_both_tools_are_installed_where_the_shell_looks(self):
        with patch.object(velora, "package_metadata", return_value=None), \
                patch.object(velora.shutil, "which", return_value="/usr/bin/cargo"), \
                patch.object(velora, "run", side_effect=self.fake_build) as run:
            velora.build_native_helper()
        self.assertIn("--locked", run.call_args.args[0])
        for name in ("velora-helper", "velora-connectivityd"):
            self.assertEqual(velora.native_helper_path(name).read_text(), name)
            self.assertFalse(velora.native_helper_path(f".{name}.new").exists())

    def test_a_failed_build_stops_the_installation(self):
        with patch.object(velora, "package_metadata", return_value=None), \
                patch.object(velora.shutil, "which", return_value="/usr/bin/cargo"), \
                patch.object(velora, "run", side_effect=velora.VeloraError("cargo failed")):
            with self.assertRaisesRegex(velora.VeloraError, "cargo failed"):
                velora.build_native_helper()

    def test_a_build_without_its_output_is_a_failure(self):
        with patch.object(velora, "package_metadata", return_value=None), \
                patch.object(velora.shutil, "which", return_value="/usr/bin/cargo"), \
                patch.object(velora, "run"):
            with self.assertRaisesRegex(velora.VeloraError, "without producing"):
                velora.build_native_helper()

    def test_missing_cargo_stops_a_real_install_but_not_a_dry_run(self):
        with patch.object(velora, "package_metadata", return_value=None), \
                patch.object(velora.shutil, "which", return_value=None):
            with self.assertRaisesRegex(velora.VeloraError, "cargo is missing"):
                velora.build_native_helper()
            with contextlib.redirect_stdout(io.StringIO()):
                velora.build_native_helper(dry=True)

    def test_a_dry_run_installs_nothing(self):
        with patch.object(velora, "package_metadata", return_value=None), \
                patch.object(velora.shutil, "which", return_value="/usr/bin/cargo"), \
                patch.object(velora, "run") as run:
            velora.build_native_helper(dry=True)
        self.assertTrue(run.call_args.kwargs["dry"])
        self.assertFalse(velora.native_helper_path("velora-connectivityd").exists())

    def test_the_package_builds_its_own(self):
        packaged = self.base / "package-bin"
        packaged.mkdir()
        for name in velora.NATIVE_BINARIES:
            (packaged / name).write_text("packaged " + name)
            (packaged / name).chmod(0o755)
            old = velora.native_helper_path(name)
            old.parent.mkdir(parents=True, exist_ok=True)
            old.write_text("old checkout binary")
        with patch.object(velora, "package_metadata", return_value={"version": "1"}), \
                patch.object(velora, "packaged_native_path", side_effect=lambda name: packaged / name), \
                patch.object(velora, "run") as run:
            velora.build_native_helper()
        run.assert_not_called()
        self.assertTrue(velora.native_tools_current())
        for name in velora.NATIVE_BINARIES:
            self.assertEqual(velora.native_helper_path(name).read_text(), "packaged " + name)

    def test_missing_modified_or_unregistered_native_tools_need_repair(self):
        self.assertFalse(velora.native_tools_current())
        with patch.object(velora, "package_metadata", return_value=None), \
                patch.object(velora.shutil, "which", return_value="/usr/bin/cargo"), \
                patch.object(velora, "run", side_effect=self.fake_build):
            velora.build_native_helper()
        self.assertTrue(velora.native_tools_current())
        velora.native_helper_path("velora-connectivityd").write_text("old protocol binary")
        self.assertFalse(velora.native_tools_current())
        velora.native_helper_path("velora-connectivityd").unlink()
        self.assertFalse(velora.native_tools_current())

    def test_updated_sources_invalidate_the_installed_pair(self):
        source = self.base / "source"
        files = {"VERSION":"0.1.3", "tools/Cargo.toml":"workspace", "tools/Cargo.lock":"locked"}
        for name in velora.NATIVE_BINARIES:
            files[f"tools/{name}/Cargo.toml"] = "crate"
            files[f"tools/{name}/src/main.rs"] = "old source"
        for name, content in files.items():
            path = source / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
        with patch.object(velora, "ROOT", source), \
                patch.object(velora.shutil, "which", return_value="/usr/bin/cargo"), \
                patch.object(velora, "run", side_effect=self.fake_build):
            velora.build_native_helper()
            self.assertTrue(velora.native_tools_current())
            (source / "VERSION").write_text("0.1.4")
            (source / "tools/velora-connectivityd/src/main.rs").write_text("protocol 2")
            self.assertFalse(velora.native_tools_current())
            velora.build_native_helper()
            self.assertTrue(velora.native_tools_current())

    def test_incomplete_build_keeps_both_old_binaries_and_does_not_record_success(self):
        for name in velora.NATIVE_BINARIES:
            binary = velora.native_helper_path(name)
            binary.parent.mkdir(parents=True, exist_ok=True)
            binary.write_text("old " + name)
        def incomplete(command, env=None, **kwargs):
            release = Path(env["CARGO_TARGET_DIR"]) / "release"
            release.mkdir(parents=True)
            (release / "velora-helper").write_text("new helper")
        with patch.object(velora, "package_metadata", return_value=None), \
                patch.object(velora.shutil, "which", return_value="/usr/bin/cargo"), \
                patch.object(velora, "run", side_effect=incomplete), \
                self.assertRaisesRegex(velora.VeloraError, "without producing velora-connectivityd"):
            velora.build_native_helper()
        for name in velora.NATIVE_BINARIES:
            self.assertEqual(velora.native_helper_path(name).read_text(), "old " + name)
        self.assertFalse((velora.state_dir() / "native-tools.json").exists())

    def test_skip_packages_still_installs_native_tools_before_linking(self):
        steps = []
        args = velora.parser().parse_args(["install", "--yes", "--skip-packages"])
        with patch.object(velora, "preflight"), patch.object(velora, "run"), \
                patch.object(velora, "install_dependencies") as dependencies, \
                patch.object(velora, "build_native_helper", side_effect=lambda: steps.append("native")), \
                patch.object(velora, "install_fonts"), \
                patch.object(velora, "verify_runtime", side_effect=lambda *args: steps.append("verify")), \
                patch.object(velora, "link_configuration", side_effect=lambda *args: steps.append("link") or self.base):
            velora.install(args)
        dependencies.assert_not_called()
        self.assertEqual(steps, ["native", "verify", "link"])

    def test_native_build_failure_stops_a_fresh_install_before_linking(self):
        args = velora.parser().parse_args(["install", "--yes", "--skip-packages"])
        with patch.object(velora, "preflight"), patch.object(velora, "run"), \
                patch.object(velora, "build_native_helper", side_effect=velora.VeloraError("native build failed")), \
                patch.object(velora, "link_configuration") as link, \
                self.assertRaisesRegex(velora.VeloraError, "native build failed"):
            velora.install(args)
        link.assert_not_called()

    def test_the_package_recipe_installs_the_connection_service(self):
        recipe = (PROJECT / "packaging/arch/PKGBUILD.in").read_text()
        self.assertIn('cargo-target/release/velora-connectivityd" "$pkgdir/usr/bin/velora-connectivityd"', recipe)

    def test_the_fakes_stay_out_of_release_builds(self):
        workspace = (PROJECT / "tools/Cargo.toml").read_text()
        default_members = next(line for line in workspace.splitlines() if line.startswith("default-members"))
        self.assertIn("velora-connectivityd", default_members)
        self.assertNotIn("fakes", default_members)

    def test_a_missing_connection_service_is_a_runtime_problem(self):
        with patch.object(velora, "system_tool", side_effect=lambda name: None if name == "velora-connectivityd" else f"/usr/bin/{name}"):
            problems = velora.runtime_problems({"shell": {}})
        self.assertIn("Missing connection service: velora-connectivityd (shell)", problems)
        velora.native_helper_path("velora-connectivityd").parent.mkdir(parents=True, exist_ok=True)
        velora.native_helper_path("velora-connectivityd").write_text("")
        with patch.object(velora, "system_tool", side_effect=lambda name: None if name == "velora-connectivityd" else f"/usr/bin/{name}"):
            problems = velora.runtime_problems({"shell": {}})
        self.assertNotIn("Missing connection service: velora-connectivityd (shell)", problems)


class DependencyTests(IsolatedTest):
    def setUp(self):
        super().setUp()
        builder = patch.object(velora, "build_native_helper")
        builder.start()
        self.addCleanup(builder.stop)

    def test_missing_packages_are_deduplicated_and_skip_aur_is_respected(self):
        features = {"a": {"repo": ["git", "kitty"], "aur": ["mpvpaper"]},
                    "b": {"repo": ["kitty", "python"], "aur": ["mpvpaper"]}}
        installed = {"git", "python"}
        with patch.object(velora, "missing_packages", side_effect=lambda packages: [pkg for pkg in packages if pkg not in installed]):
            self.assertEqual(velora.package_plan(features), (["kitty"], ["mpvpaper"]))
            self.assertEqual(velora.package_plan(features, True), (["kitty"], []))

    def test_components_report_choice_and_installation_for_the_setup_assistant(self):
        velora.write_json(velora.state_dir() / "installation.json", {"without": ["toolbox"]})
        with patch.object(velora, "missing_packages", side_effect=lambda packages: [p for p in packages if p == "yt-dlp"]):
            state = {item["id"]: item for item in velora.components_state()}
        self.assertFalse(state["toolbox"]["selected"])
        self.assertFalse(state["toolbox"]["installed"])
        self.assertEqual((state["toolbox"]["missingRepo"], state["toolbox"]["missingAur"]), (["yt-dlp"], []))
        self.assertTrue(state["desktop"]["required"] and state["desktop"]["installed"])

    def test_deps_add_keeps_the_new_components_in_the_saved_selection(self):
        velora.write_json(velora.state_dir() / "installation.json", {"without": ["toolbox", "live-wallpapers"], "skip_aur": False})
        args = velora.parser().parse_args(["deps", "--add", "toolbox"])
        velora.add_features(args)
        self.assertEqual(args.without, "live-wallpapers")
        self.assertEqual(velora.preferences()["without"], ["live-wallpapers"])
        with self.assertRaisesRegex(velora.VeloraError, "Unknown components"):
            velora.add_features(velora.parser().parse_args(["deps", "--add", "nonsense"]))

    def test_bluetooth_dependencies_and_controller_detection(self):
        shell = velora.manifest()["shell"]
        self.assertTrue({"bluez", "bluez-utils"}.issubset(shell["repo"]))
        sysfs = self.base / "sys/class/bluetooth"
        self.assertFalse(velora.bluetooth_adapters_present(sysfs))
        (sysfs / "hci0").mkdir(parents=True)
        self.assertTrue(velora.bluetooth_adapters_present(sysfs))

    def test_deps_skip_packages_leaves_packages_environment_and_services_unchanged(self):
        with patch.object(velora, "package_plan") as package_plan, \
                patch.object(velora, "bluetooth_adapters_present") as adapters, \
                patch.object(velora, "install_fonts"), \
                patch.object(velora, "verify_runtime"), \
                patch.object(velora, "run") as run:
            self.assertEqual(velora.main(["deps", "--skip-packages"]), 0)
        package_plan.assert_not_called()
        adapters.assert_not_called()
        run.assert_not_called()

    def test_bluetooth_service_only_enabled_for_detected_controller(self):
        args = velora.parser().parse_args(["deps"])
        features = {"shell": velora.manifest()["shell"]}
        command = ["sudo", "systemctl", "enable", "--now", "bluetooth.service"]
        with patch.object(velora, "package_plan", return_value=([], [])), \
                patch.object(velora, "bluetooth_adapters_present", return_value=True), \
                patch.object(velora, "run") as run:
            velora.install_dependencies(args, features)
            run.assert_any_call(command, dry=False)
        with patch.object(velora, "package_plan", return_value=([], [])), \
                patch.object(velora, "bluetooth_adapters_present", return_value=False), \
                patch.object(velora, "run") as run:
            velora.install_dependencies(args, features)
            self.assertNotIn(command, [item.args[0] for item in run.call_args_list])
        args.dry_run = True
        with patch.object(velora, "package_plan", return_value=([], [])), \
                patch.object(velora, "bluetooth_adapters_present", return_value=True), \
                patch.object(velora, "run") as run:
            velora.install_dependencies(args, features)
            run.assert_any_call(command, dry=True)

    def test_font_step_refreshes_cache_without_downloading_installed_fonts(self):
        with patch.object(velora, "font_installed", return_value=True), \
                patch.object(velora, "font_tool", side_effect=lambda name: f"/usr/bin/{name}"), \
                patch.object(velora, "download_font") as download, patch.object(velora, "run") as run:
            velora.install_fonts()
        download.assert_not_called()
        run.assert_called_once_with(["/usr/bin/fc-cache", "-f"], timeout=180)

    def test_missing_required_font_is_fatal_instead_of_linking_a_broken_desktop(self):
        with patch.object(velora, "font_installed", side_effect=lambda family: family != "Google Sans Flex"), \
                patch.object(velora, "font_tool", side_effect=lambda name: f"/usr/bin/{name}"), \
                patch.object(velora, "run"), \
                patch.object(velora, "download_font", side_effect=velora.VeloraError("offline")):
            with self.assertRaisesRegex(velora.VeloraError, "Required fonts are missing: Google Sans Flex"):
                velora.install_fonts()

    def test_font_detection_matches_aliases_without_accepting_partial_names(self):
        with patch.object(velora, "font_tool", side_effect=lambda name: f"/usr/bin/{name}"), \
                patch.object(velora, "run", return_value="JetBrainsMono Nerd Font,JetBrainsMono NF\nGoogle Sans Flex\nNoto Sans Arabic\n"):
            self.assertTrue(velora.font_installed("JetBrains Mono NF"))
            self.assertTrue(velora.font_installed("Google Sans Flex"))
            self.assertFalse(velora.font_installed("Google Sans"))
            self.assertFalse(velora.font_installed("Noto Sans"))

    def test_core_font_requirements_cover_configured_families_and_stay_required(self):
        example = json.loads((PROJECT / "dots/.config/illogical-impulse/config.example.json").read_text())
        required = set(velora.FONT_PACKAGES)
        self.assertTrue(set(example["appearance"]["fonts"].values()) <= required)
        self.assertTrue({"Material Symbols Rounded", "Hack Nerd Font", "Noto Sans", "Noto Color Emoji"} <= required)
        shell = velora.manifest()["shell"]
        self.assertTrue(shell["required"])
        self.assertTrue({"fontconfig", "ttf-jetbrains-mono-nerd", "ttf-hack-nerd", "noto-fonts", "noto-fonts-emoji"} <= set(shell["repo"]))
        downloadable_packages = {velora.FONT_PACKAGES[family] for family in velora.FONT_DOWNLOADS}
        self.assertFalse(downloadable_packages & set(shell["aur"]))

    def test_skip_aur_repairs_ui_fonts_and_refreshes_cache_before_verifying(self):
        installed = set(velora.FONT_PACKAGES) - set(velora.FONT_DOWNLOADS)
        args = ["deps", "--skip-aur"]
        with patch.object(velora, "install_dependencies") as dependencies, \
                patch.object(velora, "build_native_helper"), \
                patch.object(velora, "preflight"), \
                patch.object(velora, "verify_runtime"), \
                patch.object(velora, "font_tool", side_effect=lambda name: f"/usr/bin/{name}"), \
                patch.object(velora, "font_installed", side_effect=lambda family: family in installed), \
                patch.object(velora, "download_font", side_effect=installed.add) as download, \
                patch.object(velora, "run") as run:
            self.assertEqual(velora.main(args), 0)
        self.assertTrue(dependencies.call_args.args[0].skip_aur)
        self.assertEqual({call.args[0] for call in download.call_args_list}, set(velora.FONT_DOWNLOADS))
        self.assertEqual([call.args[0] for call in run.call_args_list], [["/usr/bin/fc-cache", "-f"]] * 2)
        self.assertEqual(installed, set(velora.FONT_PACKAGES))

    def test_missing_package_font_names_the_package_to_repair(self):
        with patch.object(velora, "font_installed", side_effect=lambda family: family != "Hack Nerd Font"), \
                patch.object(velora, "font_tool", side_effect=lambda name: f"/usr/bin/{name}"), \
                patch.object(velora, "run"), patch.object(velora, "download_font") as download:
            with self.assertRaisesRegex(velora.VeloraError, r"Hack Nerd Font \(ttf-hack-nerd\)"):
                velora.install_fonts()
        download.assert_not_called()

    def test_font_dry_run_does_not_create_directories_or_refresh_cache(self):
        with patch.object(velora, "font_installed", return_value=False), \
                patch.object(velora, "download_font") as download, patch.object(velora, "run") as run:
            velora.install_fonts(dry=True)
        download.assert_not_called()
        run.assert_not_called()
        self.assertFalse((self.base / "data/fonts").exists())

    def test_download_validates_family_and_preserves_the_license(self):
        family = "Material Symbols Rounded"
        def fetched(command, **kwargs):
            if Path(command[0]).name == "curl":
                Path(command[command.index("--output") + 1]).write_bytes(b"downloaded font or license")
                return ""
            self.assertEqual(Path(command[0]).name, "fc-scan")
            return family
        with patch.object(velora, "font_tool", side_effect=lambda name: f"/usr/bin/{name}"), \
                patch.object(velora, "run", side_effect=fetched):
            velora.download_font(family)
        target = self.base / "data/fonts/velora-material-symbols-rounded"
        self.assertTrue((target / "material-symbols-rounded.ttf").is_file())
        self.assertTrue((target / "LICENSE.txt").is_file())

    def test_invalid_download_is_rejected_before_replacing_a_font(self):
        target = self.base / "data/fonts/velora-google-sans-flex"
        target.mkdir(parents=True)
        previous = target / "google-sans-flex.ttf"
        previous.write_bytes(b"existing font")
        def fetched(command, **kwargs):
            if Path(command[0]).name == "curl":
                Path(command[command.index("--output") + 1]).write_bytes(b"wrong font")
                return ""
            return "Unrelated Font"
        with patch.object(velora, "font_tool", side_effect=lambda name: f"/usr/bin/{name}"), \
                patch.object(velora, "run", side_effect=fetched):
            with self.assertRaisesRegex(velora.VeloraError, "does not provide Google Sans Flex"):
                velora.download_font("Google Sans Flex")
        self.assertEqual(previous.read_bytes(), b"existing font")

    def test_installer_does_not_link_configuration_after_font_failure(self):
        args = velora.parser().parse_args(["install", "--yes", "--skip-packages"])
        with patch.object(velora, "run"), patch.object(velora, "preflight"), \
                patch.object(velora, "build_native_helper"), \
                patch.object(velora, "install_fonts", side_effect=velora.VeloraError("Required fonts are missing")), \
                patch.object(velora, "link_configuration") as link:
            with self.assertRaisesRegex(velora.VeloraError, "Required fonts are missing"):
                velora.install(args)
        link.assert_not_called()

    def test_system_font_tools_win_over_an_environment_on_path(self):
        with patch.object(velora.Path, "is_file", return_value=True), \
                patch.object(velora.shutil, "which", return_value="/opt/conda/bin/fc-list") as which:
            self.assertEqual(velora.font_tool("fc-list"), "/usr/bin/fc-list")
        which.assert_not_called()

    def test_unavailable_fontconfig_stops_before_any_download(self):
        with patch.object(velora, "font_tool", return_value=None), \
                patch.object(velora, "download_font") as download:
            with self.assertRaisesRegex(velora.VeloraError, "Install fontconfig"):
                velora.install_fonts()
        download.assert_not_called()

    def test_doctor_checks_all_families_even_when_the_main_font_is_installed(self):
        venv = velora.xdg("XDG_STATE_HOME", ".local/state") / "quickshell/.venv/bin/python"
        venv.parent.mkdir(parents=True)
        venv.touch()
        with patch.object(velora, "font_installed", side_effect=lambda family: family != "Material Symbols Rounded"), \
                patch.object(velora, "package_plan", return_value=([], [])), \
                patch.object(velora, "stale_links", return_value=[]), \
                patch.object(velora, "runtime_problems", return_value=[]), \
                patch.object(velora, "service_active", return_value=True), \
                patch.object(velora.shutil, "which", return_value="/usr/bin/tool"), \
                contextlib.redirect_stdout(io.StringIO()) as output:
            with self.assertRaises(velora.VeloraError):
                velora.doctor(velora.parser().parse_args(["doctor"]))
        self.assertIn("Font Google Sans Flex: installed", output.getvalue())
        self.assertIn("Font Material Symbols Rounded: missing", output.getvalue())

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
                 "dots/.local/share/icons/hicolor/scalable/apps/org.velora.Settings.svg",
                 "dots/.local/share/applications/org.velora.Settings.desktop",
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
             patch.object(velora, "build_native_helper"), \
             patch.object(velora, "install_fonts"), \
             patch.object(velora, "verify_runtime"), \
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


class NoUpstreamTests(IsolatedTest):
    def run_update(self, *arguments):
        args = velora.parser().parse_args(["update", *arguments])
        def fake_git(*command, **_):
            if command[:1] == ("symbolic-ref",):
                return "work"
            raise velora.VeloraError("Command failed (1): git config branch.work.remote")
        with patch.object(velora, "package_metadata", return_value=None), patch.object(velora, "git", side_effect=fake_git):
            velora.update(args)

    def test_the_scheduled_check_on_a_local_branch_isnt_a_failure(self):
        self.run_update("--check", "--notify")

    def test_asking_to_update_a_local_branch_says_why_not(self):
        with self.assertRaisesRegex(velora.NoUpstream, "doesn't follow a remote"):
            self.run_update()


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

    def test_current_sources_repair_outdated_native_tools_without_reinstalling_configuration(self):
        before = git(self.checkout, "rev-parse", "HEAD")
        with patch.object(velora, "native_tools_current", return_value=False), \
                patch.object(velora, "build_native_helper") as build, \
                patch.object(velora, "link_configuration") as link:
            velora.update(self.args())
        build.assert_called_once_with()
        link.assert_not_called()
        self.assertEqual(git(self.checkout, "rev-parse", "HEAD"), before)

    def test_current_sources_and_binaries_do_not_rebuild(self):
        with patch.object(velora, "native_tools_current", return_value=True), \
                patch.object(velora, "build_native_helper") as build:
            velora.update(self.args())
        build.assert_not_called()

    def test_background_check_never_repairs_or_builds_native_tools(self):
        with patch.object(velora, "native_tools_current", return_value=False), \
                patch.object(velora, "build_native_helper") as build:
            velora.update(self.args("--check"))
        build.assert_not_called()

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
        velora.write_json(velora.state_dir() / "installation.json", {"without": ["toolbox"], "skip_aur": True, "skip_packages": True})
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
        self.assertIn("--skip-packages", installer_commands[0])
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
