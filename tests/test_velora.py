"""Regression tests using temporary configuration roots and local Git remotes."""
import argparse
import contextlib
import hashlib
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
    def fake_build(self, command, env=None, dry=False, cwd=None):
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
        for name in velora.NATIVE_BINARIES:
            self.assertEqual(velora.native_helper_path(name).read_text(), name)
            self.assertFalse(velora.native_helper_path(f".{name}.new").exists())

    def test_explicit_package_build_replaces_a_stale_cached_agent(self):
        release = Path(os.environ["XDG_CACHE_HOME"]) / "velora/cargo-target/release"
        release.mkdir(parents=True)
        (release / "velora-agentd").write_text("stale protocol agent")
        (release / "velora-agentd").chmod(0o755)
        requested = []
        def selective_build(command, env=None, dry=False, cwd=None):
            packages = [command[i + 1] for i, argument in enumerate(command) if argument == "--package"]
            requested.extend(packages)
            # Model a workspace whose default selection omits the already-cached agent.
            selected = list(packages or [name for name in velora.NATIVE_PACKAGES if name != "velora-agentd"])
            if "velora-helper" in selected:
                selected.append("velora-desktop-state")
            for name in selected:
                (release / name).write_text("rebuilt " + name)
                (release / name).chmod(0o755)
        with patch.object(velora, "package_metadata", return_value=None), \
                patch.object(velora.shutil, "which", return_value="/usr/bin/cargo"), \
                patch.object(velora, "run", side_effect=selective_build):
            velora.build_native_helper()
        self.assertEqual(set(requested), set(velora.NATIVE_PACKAGES))
        self.assertEqual(velora.native_helper_path("velora-agentd").read_text(), "rebuilt velora-agentd")
        self.assertTrue(velora.native_tools_current())

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
        files = {"VERSION":"0.1.3", "tools/Cargo.toml":"workspace", "tools/Cargo.lock":"locked", "tools/rust-toolchain.toml":"toolchain"}
        for name in velora.NATIVE_PACKAGES:
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

    def test_incomplete_build_keeps_old_binaries_and_does_not_record_success(self):
        for name in velora.NATIVE_BINARIES:
            binary = velora.native_helper_path(name)
            binary.parent.mkdir(parents=True, exist_ok=True)
            binary.write_text("old " + name)
        def incomplete(command, env=None, **kwargs):
            release = Path(env["CARGO_TARGET_DIR"]) / "release"
            release.mkdir(parents=True)
            for name in velora.NATIVE_BINARIES:
                if name != "velora-connectivityd":
                    (release / name).write_text("new " + name)
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
                patch.object(velora, "build_window_plugin"), \
                patch.object(velora, "build_file_dialog", side_effect=lambda: steps.append("dialog")), \
                patch.object(velora, "install_fonts"), \
                patch.object(velora, "verify_runtime", side_effect=lambda *args: steps.append("verify")), \
                patch.object(velora, "link_configuration", side_effect=lambda *args: steps.append("link") or self.base):
            velora.install(args)
        dependencies.assert_not_called()
        self.assertEqual(steps, ["native", "dialog", "verify", "link"])

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
                patch.object(velora, "install_ui_font") as download, patch.object(velora, "run") as run:
            velora.install_fonts()
        download.assert_not_called()
        run.assert_called_once_with(["/usr/bin/fc-cache", "-f"], timeout=180)

    def test_missing_required_font_is_fatal_instead_of_linking_a_broken_desktop(self):
        with patch.object(velora, "font_installed", side_effect=lambda family: family != "Google Sans Flex"), \
                patch.object(velora, "font_tool", side_effect=lambda name: f"/usr/bin/{name}"), \
                patch.object(velora, "run"), \
                patch.object(velora, "install_ui_font", side_effect=velora.VeloraError("offline")):
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
        example = json.loads((PROJECT / "dots/.config/velora/config.example.json").read_text())
        required = set(velora.FONT_PACKAGES)
        self.assertTrue(set(example["appearance"]["fonts"].values()) <= required)
        self.assertTrue({"Material Symbols Rounded", "Hack Nerd Font", "Noto Sans", "Noto Color Emoji",
                         "Noto Sans CJK JP", "Noto Sans CJK KR"} <= required)
        shell = velora.manifest()["shell"]
        self.assertTrue(shell["required"])
        self.assertTrue({"fontconfig", "ttf-jetbrains-mono-nerd", "ttf-hack-nerd", "noto-fonts", "noto-fonts-cjk", "noto-fonts-emoji"} <= set(shell["repo"]))
        self.assertIn("ttf-material-symbols-variable", shell["repo"])
        bundled = {family for family, pkg in velora.FONT_PACKAGES.items() if pkg is None}
        self.assertEqual(set(velora.UI_FONT_HASHES), bundled | {"Material Symbols Rounded"})

    def test_skip_aur_repairs_ui_fonts_and_refreshes_cache_before_verifying(self):
        installed = set(velora.FONT_PACKAGES) - set(velora.UI_FONT_HASHES)
        args = ["deps", "--skip-aur"]
        with patch.object(velora, "install_dependencies") as dependencies, \
                patch.object(velora, "build_native_helper"), \
                patch.object(velora, "preflight"), \
                patch.object(velora, "verify_runtime"), patch.object(velora, "configure_network"), \
                patch.object(velora, "font_tool", side_effect=lambda name: f"/usr/bin/{name}"), \
                patch.object(velora, "font_installed", side_effect=lambda family: family in installed), \
                patch.object(velora, "install_ui_font", side_effect=installed.add) as download, \
                patch.object(velora, "run") as run:
            self.assertEqual(velora.main(args), 0)
        self.assertTrue(dependencies.call_args.args[0].skip_aur)
        self.assertEqual({call.args[0] for call in download.call_args_list}, set(velora.UI_FONT_HASHES))
        self.assertEqual([call.args[0] for call in run.call_args_list], [["/usr/bin/fc-cache", "-f"]] * 2)
        self.assertEqual(installed, set(velora.FONT_PACKAGES))

    def test_missing_package_font_names_the_package_to_repair(self):
        with patch.object(velora, "font_installed", side_effect=lambda family: family != "Hack Nerd Font"), \
                patch.object(velora, "font_tool", side_effect=lambda name: f"/usr/bin/{name}"), \
                patch.object(velora, "run"), patch.object(velora, "install_ui_font") as download:
            with self.assertRaisesRegex(velora.VeloraError, r"Hack Nerd Font \(ttf-hack-nerd\)"):
                velora.install_fonts()
        download.assert_not_called()

    def test_font_dry_run_does_not_create_directories_or_refresh_cache(self):
        with patch.object(velora, "font_installed", return_value=False), \
                patch.object(velora, "install_ui_font") as download, patch.object(velora, "run") as run:
            velora.install_fonts(dry=True)
        download.assert_not_called()
        run.assert_not_called()
        self.assertFalse((self.base / "data/fonts").exists())

    def test_download_validates_family_and_preserves_the_license(self):
        family = "Material Symbols Rounded"
        digest = hashlib.sha256(b"downloaded font or license").hexdigest()
        def fetched(command, **kwargs):
            if Path(command[0]).name == "curl":
                Path(command[command.index("--output") + 1]).write_bytes(b"downloaded font or license")
                return ""
            self.assertEqual(Path(command[0]).name, "fc-scan")
            return family
        with patch.dict(velora.UI_FONT_HASHES, {family: (digest, digest)}), \
                patch.object(velora, "font_tool", side_effect=lambda name: f"/usr/bin/{name}"), \
                patch.object(velora, "run", side_effect=fetched):
            velora.install_ui_font(family)
        target = self.base / "data/fonts/velora-material-symbols-rounded"
        self.assertTrue((target / "material-symbols-rounded.ttf").is_file())
        self.assertTrue((target / "LICENSE.txt").is_file())

    def test_invalid_bundle_is_rejected_before_replacing_a_font(self):
        target = self.base / "data/fonts/velora-google-sans-flex"
        target.mkdir(parents=True)
        previous = target / "google-sans-flex.ttf"
        previous.write_bytes(b"existing font")
        with patch.object(velora, "font_tool", return_value="/usr/bin/fc-scan"), \
                patch.object(velora, "run", return_value="Unrelated Font"):
            with self.assertRaisesRegex(velora.VeloraError, "does not provide Google Sans Flex"):
                velora.install_ui_font("Google Sans Flex")
        self.assertEqual(previous.read_bytes(), b"existing font")

    def test_repairs_truncated_bundled_fonts_and_licenses_even_when_fontconfig_lists_the_family(self):
        for family, package in velora.FONT_PACKAGES.items():
            if package is not None:
                continue
            with self.subTest(family=family), patch.object(velora, "run", return_value=family) as run:
                target = velora.ui_font_directory(family)
                velora.install_ui_font(family)
                self.assertFalse(velora.ui_font_needs_install(family))
                for file in (next(target.glob("*.ttf")), target / "LICENSE.txt"):
                    valid = file.read_bytes()
                    file.write_bytes(valid[:100])
                    self.assertTrue(velora.ui_font_needs_install(family))
                    velora.install_ui_font(family)
                    self.assertEqual(file.read_bytes(), valid)
                self.assertFalse(any(Path(call.args[0][0]).name == "curl" for call in run.call_args_list))

    def test_truncated_download_cannot_replace_the_previous_icon_font(self):
        family = "Material Symbols Rounded"
        target = velora.ui_font_directory(family)
        target.mkdir(parents=True)
        previous = target / "material-symbols-rounded.ttf"
        previous.write_bytes(b"previous font")
        def truncated(command, **kwargs):
            self.assertEqual(Path(command[0]).name, "curl")
            Path(command[command.index("--output") + 1]).write_bytes(b"partial download")
        with patch.object(velora, "run", side_effect=truncated):
            with self.assertRaisesRegex(velora.VeloraError, "SHA-256 mismatch"):
                velora.install_ui_font(family)
        self.assertEqual(list(target.iterdir()), [previous])
        self.assertEqual(previous.read_bytes(), b"previous font")

    def test_reinstalls_a_registered_official_font_package_with_missing_family(self):
        features = {"shell": {"repo": ["ttf-hack-nerd", "noto-fonts"]}}
        with patch.object(velora, "missing_packages", return_value=[]), \
                patch.object(velora, "font_tool", return_value="fc-list"), \
                patch.object(velora, "run", return_value="Noto Sans"):
            self.assertEqual(velora.package_plan(features), (["ttf-hack-nerd"], []))

    def test_installer_does_not_link_configuration_after_font_failure(self):
        args = velora.parser().parse_args(["install", "--yes", "--skip-packages"])
        with patch.object(velora, "run"), patch.object(velora, "preflight"), \
                patch.object(velora, "build_native_helper"), \
                patch.object(velora, "build_window_plugin"), \
                patch.object(velora, "build_file_dialog"), \
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
                patch.object(velora, "install_ui_font") as download:
            with self.assertRaisesRegex(velora.VeloraError, "Install fontconfig"):
                velora.install_fonts()
        download.assert_not_called()

    def test_doctor_checks_all_families_even_when_the_main_font_is_installed(self):
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
             patch.object(velora, "service_active", return_value=False), \
             patch.object(velora.shutil, "which", return_value=None), patch.object(velora, "run") as run:
            velora.install_dependencies(args, {"test": {}})
            self.assertTrue(run.call_args_list)
            self.assertTrue(all(call.kwargs.get("dry") for call in run.call_args_list))
            self.assertIn("-Syu", run.call_args_list[0].args[0])

    def test_paru_is_used_when_yay_is_unavailable(self):
        args = velora.parser().parse_args(["deps"])
        with patch.object(velora, "package_plan", return_value=([], ["mpvpaper"])), \
             patch.object(velora, "missing_packages", return_value=[]), \
             patch.object(velora.shutil, "which", side_effect=lambda name: "/usr/bin/paru" if name == "paru" else None), \
             patch.object(velora, "run") as run:
            velora.install_dependencies(args, {})
            self.assertEqual(run.call_args_list[0].args[0][0], "/usr/bin/paru")

    def test_absent_packages_after_a_successful_helper_exit_stop_before_services(self):
        args = velora.parser().parse_args(["deps"])
        with patch.object(velora, "package_plan", return_value=(["git"], ["mpvpaper"])), \
                patch.object(velora.shutil, "which", return_value="/usr/bin/yay"), \
                patch.object(velora, "run"), patch.object(velora, "missing_packages", return_value=["mpvpaper"]), \
                patch.object(velora, "ensure_system_service") as service:
            with self.assertRaisesRegex(velora.VeloraError, "Still missing: mpvpaper"):
                velora.install_dependencies(args, {})
        service.assert_not_called()


class InstallerTests(IsolatedTest):
    def setUp(self):
        super().setUp()
        self.repo = self.base / "checkout with spaces"
        (self.repo / "scripts").mkdir(parents=True)
        shutil.copy(PROJECT / "scripts/install.sh", self.repo / "scripts/install.sh")
        shutil.copy(PROJECT / "scripts/journal.py", self.repo / "scripts/journal.py")
        for name in ("hypr", "quickshell", "kitty", "foot", "fuzzel", "matugen", "fish", "fontconfig", "Kvantum",
                     "kde-material-you-colors", "mpv", "wlogout", "xdg-desktop-portal", "zshrc.d", "tmux", "velora"):
            (self.repo / "dots/.config" / name).mkdir(parents=True)
        files = ["home/.zshrc", "home/.tmux.conf", "dots/.config/starship.toml", "tools/velora-helper/Cargo.toml",
                 "dots/.config/hypr/hyprland.lua", "dots/.config/quickshell/ii/shell.qml",
                 "dots/.config/wireplumber/wireplumber.conf.d/51-auto-audio-routes.conf",
                 "dots/.local/share/wireplumber/scripts/folis/prefer-plugged-routes.lua",
                 "dots/.local/share/org.kde.syntax-highlighting/themes/Velora.theme",
                 "dots/.config/neofetch/velora-ascii.txt", "dots/.config/neofetch/velora.conf",
                 "dots/.config/matugen/templates/btop/Velora.theme", "dots/.config/btop/btop.conf",
                 "dots/.local/share/icons/velora.svg",
                 "dots/.local/share/icons/hicolor/scalable/apps/org.velora.Settings.svg",
                 "dots/.local/share/applications/org.velora.Settings.desktop",
                 "dots/.local/share/kxmlgui5/dolphin/dolphinui.rc",
                 "dots/.config/quickshell/ii/scripts/helper",
                 "dots/.local/share/dbus-1/services/org.freedesktop.FileManager1.service",
                 "dots/.local/share/applications/drracket.desktop",
                 "dots/.config/quickshell/ii/modules/common/widgets/shapes/ShapeCanvas.qml"]
        for name in files:
            path = self.repo / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("fixture\n")
        shutil.copy(PROJECT / "dots/.local/share/kxmlgui5/dolphin/dolphinui.rc",
                    self.repo / "dots/.local/share/kxmlgui5/dolphin/dolphinui.rc")
        (self.repo / "dots/.config/hypr/hyprland.lua").write_text("-- test desktop\n")
        (self.repo / "dots/.config/velora/config.example.json").write_text('{"default": true}\n')
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

    def test_replacement_plan_lists_foreign_targets_and_skips_current_or_unrelated_files(self):
        config = Path(self.env["XDG_CONFIG_HOME"])
        config.mkdir(parents=True)
        (config / "hypr").mkdir()
        (config / "kitty").symlink_to(config / "missing-custom-kitty")
        (config / "foot").symlink_to(self.repo / "dots/.config/foot")
        (config / "personal").write_text("keep")
        service = config / "systemd/user/velora-update.service"
        service.parent.mkdir(parents=True)
        service.write_text("old unit")
        args = velora.parser().parse_args(["install", "--yes", "--skip-packages"])
        with patch.dict(os.environ, self.env), patch.object(velora, "ROOT", self.repo), \
                contextlib.redirect_stdout(io.StringIO()) as plan:
            velora.describe_replacements(args, [])
        self.assertEqual({line.strip() for line in plan.getvalue().splitlines() if line.startswith("    ")},
                         {str(config / "hypr"), str(config / "kitty"), str(service)})
        self.assertIn("replaced in full", plan.getvalue())
        self.assertEqual(self.journal.read_text(), "")
        self.assertEqual(service.read_text(), "old unit")
        self.assertFalse((config / "hypr").is_symlink())

    def test_packaged_preview_can_run_before_the_writable_runtime_exists(self):
        runtime = self.base / "fresh runtime"
        original = self.home / ".zshrc"
        original.write_text("personal")
        self.env["VELORA_SOURCE_ROOT"] = str(runtime)
        result = self.link("--list-replacements")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, str(original) + "\0")
        self.assertFalse(runtime.exists())
        self.assertEqual(original.read_text(), "personal")

    def test_invalid_hyprland_configuration_rolls_back_before_registration(self):
        config = Path(self.env["XDG_CONFIG_HOME"])
        hypr = config / "hypr"
        hypr.mkdir(parents=True)
        (hypr / "custom.lua").write_text("old settings")
        args = velora.parser().parse_args(["install", "--no-reload"])
        real_run = velora.run
        def run(command, **options):
            if "--verify-config" in command:
                self.assertEqual(command[-1], hypr / "hyprland.lua")
                self.assertTrue(hypr.is_symlink())
                raise velora.VeloraError("configuration parse failed")
            return real_run(command, **options)
        with patch.dict(os.environ, self.env), patch.object(velora, "ROOT", self.repo), \
                patch.object(velora, "system_tool", return_value="/usr/bin/Hyprland"), \
                patch.object(velora, "run", side_effect=run), patch.object(velora, "register_installation") as register, \
                self.assertRaisesRegex(velora.VeloraError, "configuration parse failed"):
            velora.link_configuration(args, [])
        self.assertFalse(hypr.is_symlink())
        self.assertEqual((hypr / "custom.lua").read_text(), "old settings")
        register.assert_not_called()

    def test_install_and_repeat_preserve_existing_shell_settings(self):
        config = Path(self.env["XDG_CONFIG_HOME"]) / "velora"
        config.mkdir(parents=True)
        (config / "config.json").write_text('{"personal": true}\n')
        self.assertEqual(self.link().returncode, 0)
        self.assertEqual(json.loads((config / "config.json").read_text()), {"personal": True})
        before = self.journal.read_text()
        self.assertEqual(self.link().returncode, 0)
        self.assertEqual(self.journal.read_text(), before)
        self.assertEqual(json.loads((config / "config.json").read_text()), {"personal": True})

    def test_linked_legacy_settings_migrate_and_old_shortcuts_still_work(self):
        config = Path(self.env["XDG_CONFIG_HOME"])
        config.mkdir(parents=True)
        legacy = config / "illogical-impulse"
        previous = self.repo / "dots/.config/illogical-impulse"
        previous.mkdir()
        legacy.symlink_to(previous)
        (legacy / "config.json").write_text('{"wallpaper": "my photo.jpg"}')
        (legacy / "presets/personal").mkdir(parents=True)
        (legacy / "presets/personal/preset.json").write_text("my preset")
        (legacy / "actions").mkdir()
        (legacy / "actions/.hidden").write_text("my action")
        (legacy / "config.example.json").write_text("obsolete example")
        current = config / "velora"
        dry = self.link("--dry-run")
        self.assertEqual(dry.returncode, 0, dry.stderr)
        self.assertFalse(current.exists())
        self.assertEqual(legacy.resolve(), previous)

        result = self.link()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads((current / "config.json").read_text()), {"wallpaper": "my photo.jpg"})
        self.assertEqual((current / "presets/personal/preset.json").read_text(), "my preset")
        self.assertEqual((current / "actions/.hidden").read_text(), "my action")
        self.assertFalse((current / "config.example.json").exists())
        self.assertEqual(legacy.resolve(), current)
        (current / "actions/.hidden").unlink()
        before = self.journal.read_text()
        self.assertEqual(self.link().returncode, 0)
        self.assertEqual(self.journal.read_text(), before)
        self.assertFalse((current / "actions/.hidden").exists())
        velora.restore_journal(self.journal)
        self.assertEqual(legacy.resolve(), previous)
        self.assertEqual((legacy / "actions/.hidden").read_text(), "my action")

    def test_existing_velora_settings_win_when_merging_legacy_directories(self):
        config = Path(self.env["XDG_CONFIG_HOME"])
        current, legacy = config / "velora", config / "illogical-impulse"
        for directory in (current, legacy):
            (directory / "presets").mkdir(parents=True)
            (directory / "config.json").write_text(directory.name)
            (directory / "presets/shared").write_text(directory.name)
        (legacy / "presets/older").write_text("older preset")
        outside = self.base / "personal actions"
        outside.mkdir()
        (current / "actions").symlink_to(outside)
        (legacy / "actions").mkdir()
        (legacy / "actions/imported").write_text("action")
        result = self.link()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((current / "config.json").read_text(), "velora")
        self.assertEqual((current / "presets/shared").read_text(), "velora")
        self.assertEqual((current / "presets/older").read_text(), "older preset")
        self.assertFalse((outside / "imported").exists())
        velora.restore_journal(self.journal)
        self.assertFalse(legacy.is_symlink())
        self.assertEqual((legacy / "actions/imported").read_text(), "action")
        self.assertFalse((current / "presets/older").exists())

    def test_update_repairs_the_old_link_when_git_removed_its_last_template(self):
        config = Path(self.env["XDG_CONFIG_HOME"])
        config.mkdir(parents=True)
        legacy = config / "illogical-impulse"
        previous = self.repo / "dots/.config/illogical-impulse"
        legacy.symlink_to(previous)
        self.assertTrue(velora.installation_pending("current"))
        result = self.link("--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"Link {legacy} -> {config / 'velora'}", result.stdout)
        self.assertFalse(legacy.exists())
        self.assertFalse((config / "velora").exists())
        result = self.link()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(legacy.resolve(), config / "velora")
        self.assertEqual(json.loads((legacy / "config.json").read_text()), {"default": True})
        self.assertFalse(velora.installation_pending("current"))
        velora.restore_journal(self.journal)
        self.assertEqual(legacy.readlink(), previous)
        self.assertFalse(legacy.exists())

    def test_checkout_migration_keeps_internal_and_external_relative_links_working(self):
        config = Path(self.env["XDG_CONFIG_HOME"])
        config.mkdir(parents=True)
        previous = self.repo / "dots/.config/illogical-impulse"
        actions = previous / "actions"
        actions.mkdir(parents=True)
        (config / "illogical-impulse").symlink_to(previous)
        external = previous.parent / "shared dotfiles"
        external.mkdir()
        (external / "light.json").write_text("light")
        (external / "dark.json").write_text("dark")
        selected = external / "selected.json"
        selected.symlink_to("light.json")
        (previous / "config.json").symlink_to("../shared dotfiles/selected.json")
        (actions / "external").symlink_to("../../shared dotfiles/selected.json")
        (actions / "internal").symlink_to("external")
        actions.chmod(0o555)
        result = self.link()
        self.assertEqual(result.returncode, 0, result.stderr)
        current = config / "velora"
        self.assertEqual((current / "config.json").read_text(), "light")
        self.assertEqual((current / "actions/internal").readlink(), Path("external"))
        self.assertEqual((current / "actions").stat().st_mode & 0o777, 0o555)
        selected.unlink()
        selected.symlink_to("dark.json")
        self.assertEqual((current / "config.json").read_text(), "dark")
        self.assertEqual((current / "actions/internal").read_text(), "dark")
        self.assertFalse(velora.installation_pending("current"))
        velora.restore_journal(self.journal)
        self.assertEqual((config / "illogical-impulse").resolve(), previous)
        self.assertEqual((previous / "config.json").read_text(), "dark")
        self.assertEqual(actions.stat().st_mode & 0o777, 0o555)

    def test_update_after_git_pull_finishes_the_migration_once(self):
        # Stand in for system package installation while exercising the real linker,
        # Git status, update lock, saved options and CLI dispatch.
        launcher = self.repo / "velora"
        launcher.write_text('#!/bin/sh\nset -eu\n[ "$1" = install ]\n'
                            'printf "%s\\n" "$@" >> "$XDG_STATE_HOME/installer-args"\n'
                            'exec bash "$(dirname "$0")/scripts/install.sh" --no-reload > "$XDG_STATE_HOME/link.log"\n')
        launcher.chmod(0o755)
        old_example = self.repo / "dots/.config/illogical-impulse/config.example.json"
        old_example.parent.mkdir()
        new_example = self.repo / "dots/.config/velora/config.example.json"
        new_example.rename(old_example)
        git(self.repo, "init", "--initial-branch=main")
        git(self.repo, "add", ".")
        git(self.repo, "commit", "-m", "Previous installation")
        remote = self.base / "remote.git"
        git(self.base, "clone", "--bare", str(self.repo), str(remote))
        git(self.repo, "remote", "add", "origin", str(remote))
        git(self.repo, "push", "-u", "origin", "main")
        author = self.base / "author"
        git(self.base, "clone", str(remote), str(author))
        new_path = author / new_example.relative_to(self.repo)
        new_path.parent.mkdir()
        (author / old_example.relative_to(self.repo)).rename(new_path)
        (author / ".gitignore").write_text("/dots/.config/illogical-impulse/\n")
        git(author, "add", "-A")
        git(author, "commit", "-m", "Rename personal settings")
        git(author, "push")

        config = Path(self.env["XDG_CONFIG_HOME"])
        config.mkdir(parents=True)
        legacy = config / "illogical-impulse"
        legacy.symlink_to(old_example.parent)
        (legacy / "config.json").write_text('{"personal": true}\n')
        (legacy / "actions").mkdir()
        (legacy / "actions/translate").write_text("personal action")
        git(self.repo, "pull", "--ff-only")
        current = git(self.repo, "rev-parse", "HEAD")
        velora.write_json(velora.state_dir() / "installation.json",
                          {"without": ["toolbox"], "skip_aur": True, "skip_packages": True})
        with patch.object(velora, "ROOT", self.repo), patch.dict(os.environ, self.env):
            for flags in (["--dry-run"], ["--check", "--json"]):
                self.assertEqual(velora.main(["update", *flags]), 0)
                self.assertFalse((config / "velora").exists())
            status = velora.read_json(velora.state_dir() / "update.json")
            self.assertTrue(status["available"] and status["installation_pending"])
            self.assertEqual(status["behind"], 0)
            self.assertEqual(velora.main(["update"]), 0)
            self.assertEqual(git(self.repo, "rev-parse", "HEAD"), current)
            self.assertEqual(legacy.resolve(), config / "velora")
            self.assertEqual((config / "velora/actions/translate").read_text(), "personal action")
            self.assertEqual(json.loads((config / "velora/config.json").read_text()), {"personal": True})
            self.assertFalse(velora.read_json(velora.state_dir() / "update.json")["available"])
            with patch.object(velora, "native_tools_current", return_value=True):
                self.assertEqual(velora.main(["update"]), 0)
            calls = (Path(self.env["XDG_STATE_HOME"]) / "installer-args").read_text().splitlines()
            self.assertEqual(calls.count("install"), 1)
            for option in ("toolbox", "--skip-aur", "--skip-packages"):
                self.assertIn(option, calls)

    def test_update_after_a_package_upgrade_imports_settings_from_the_previous_runtime(self):
        runtime = Path(self.env["XDG_DATA_HOME"]) / "velora/runtime"
        shutil.copytree(self.repo / "dots", runtime / "dots")
        old_package = self.base / "previous package"
        legacy_path = Path("dots/.config/illogical-impulse")
        (old_package / legacy_path / "actions").mkdir(parents=True)
        (old_package / legacy_path / "config.example.json").write_text("{}")
        (old_package / legacy_path / "actions/personal").write_text("my action")
        velora.sync_runtime(old_package, runtime)
        config = Path(self.env["XDG_CONFIG_HOME"])
        config.mkdir(parents=True)
        legacy = config / "illogical-impulse"
        legacy.symlink_to(runtime / legacy_path)
        (legacy / "config.json").write_text('{"theme":"personal"}')
        revision = "a" * 40
        velora.write_json(self.repo / ".velora-package.json",
                          {"source_revision": revision, "source_branch": "main", "source_repository": "test", "version": "1"})
        (self.repo / "velora").touch()
        actual_run = velora.run

        def run(command, **kwargs):
            if command[:2] == ["git", "ls-remote"]:
                return revision + "\trefs/heads/main"
            if command[0] == Path("/usr/bin/velora"):
                options = velora.parser().parse_args(command[1:])
                self.assertEqual(options.command, "install")
                velora.link_configuration(options, [])
                return ""
            if command[0] == "systemctl":
                return ""
            if command[:2] == ["bash", self.repo / "scripts/install.sh"]:
                return actual_run(command, capture=True, **kwargs)
            return actual_run(command, **kwargs)

        with patch.object(velora, "ROOT", self.repo), patch.dict(os.environ, dict(self.env, HYPRLAND_INSTANCE_SIGNATURE="")), \
                patch.object(velora, "run", side_effect=run), patch.object(velora.builds, "build_package") as build:
            self.assertEqual(velora.main(["update", "--check"]), 0)
            status = velora.read_json(velora.state_dir() / "update.json")
            self.assertTrue(status["installation_pending"])
            self.assertFalse((config / "velora").exists())
            self.assertEqual(velora.main(["update"]), 0)
            build.assert_not_called()
            self.assertEqual(legacy.resolve(), config / "velora")
            self.assertEqual((legacy / "actions/personal").read_text(), "my action")
            self.assertEqual(json.loads((legacy / "config.json").read_text()), {"theme": "personal"})
            self.assertFalse(velora.update_status()["available"])
            velora.write_json(velora.state_dir() / "update.json", dict(status, current="b" * 40, target="c" * 40, behind=1))
            cached = velora.update_status(fetch=False)
            self.assertFalse(cached["available"])
            self.assertEqual(cached["target"], revision)

    def test_btop_migrates_only_the_stock_theme_on_first_install(self):
        directory = Path(self.env["XDG_CONFIG_HOME"]) / "btop"
        directory.mkdir(parents=True)
        config = directory / "btop.conf"
        config.write_text('color_theme = "Default"\nupdate_ms = 543\n')
        install = self.link()
        self.assertEqual(install.returncode, 0, install.stderr)
        self.assertEqual(config.read_text(), 'color_theme = "Velora"\nupdate_ms = 543\n')
        theme = directory / "themes/Velora.theme"
        self.assertFalse(theme.is_symlink())
        theme.write_text("live wallpaper colors\n")
        config.write_text('color_theme = "Default"\n')
        self.assertEqual(self.link().returncode, 0)
        self.assertEqual(theme.read_text(), "live wallpaper colors\n")
        self.assertEqual(config.read_text(), 'color_theme = "Default"\n')

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
        self.assertIn("clickfinger_behavior = true", touchpad)
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
        self.assertFalse((self.repo / "dots/.config/velora/config.json").exists())

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
             patch.object(velora, "build_window_plugin"), \
             patch.object(velora, "build_file_dialog"), \
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

    def test_retry_finishes_installation_after_sources_were_already_updated(self):
        current = git(self.checkout, 'rev-parse', 'HEAD')
        velora.write_json(velora.state_dir() / 'last-update.json',
                          {'previous': 'previous', 'target': current, 'complete': False})
        with patch.object(velora, 'install_updated_tree') as install:
            velora.update(self.args('--check'))
            self.assertTrue(velora.read_json(velora.state_dir() / 'update.json')['available'])
            install.assert_not_called()
            velora.update(self.args())
        install.assert_called_once_with(None)
        self.assertTrue(velora.read_json(velora.state_dir() / 'last-update.json')['complete'])
        self.assertFalse(velora.read_json(velora.state_dir() / 'update.json')['available'])

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
    def test_right_click_defaults_to_two_finger_press_or_tap_with_corner_optional(self):
        source = (PROJECT / "dots/.config/hypr/hyprland/general.lua").read_text()
        touchpad = source.split("touchpad = {", 1)[1].split("}", 1)[0]
        self.assertIn("tap_to_click = true", touchpad)
        self.assertIn("clickfinger_behavior = true", touchpad)

        settings = (PROJECT / "dots/.config/quickshell/ii/modules/settings/MouseConfig.qml").read_text()
        self.assertRegex(settings, r'option: "input:touchpad:tap_to_click"\s+fallback: true')
        self.assertRegex(settings, r'option: "input:touchpad:clickfinger_behavior"\s+fallback: true')
        self.assertIn('title: Translation.tr("Physical right click")', settings)
        self.assertRegex(settings, r'displayName: Translation.tr\("Bottom-right corner"\).*value: false')
        self.assertRegex(settings, r'displayName: Translation.tr\("Two-finger click"\).*value: true')


if __name__ == "__main__":
    unittest.main()
