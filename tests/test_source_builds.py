"""Source package and user-template behavior without installing host packages."""
import io
import json
from pathlib import Path
import subprocess
from unittest.mock import patch

from test_velora import IsolatedTest, PROJECT, velora
import builds
from runtime import sync_runtime


class SourceBuildTests(IsolatedTest):
    def test_core_source_option_excludes_binary_package_installation(self):
        args = velora.parser().parse_args(["install", "--build-from-source"])
        features, _ = velora.selected_features(args)
        selected = velora.source_selection(args, features)
        self.assertEqual(selected, ["hyprland", "quickshell"])
        with patch.object(velora.shutil, "which", return_value="pacman"), patch.object(velora, "run", return_value=""):
            repo, _ = velora.package_plan(features, source_packages=selected)
        self.assertNotIn("hyprland", repo)
        self.assertNotIn("quickshell", repo)

    def test_saved_source_builds_can_be_disabled(self):
        velora.write_json(velora.state_dir() / "installation.json", {"build_from_source": ["quickshell"]})
        args = velora.parser().parse_args(["install", "--no-source-builds"])
        features, _ = velora.selected_features(args)
        self.assertEqual(velora.source_selection(args, features), [])

    def test_unknown_and_binary_only_source_packages_are_rejected(self):
        for name in ("unknown-package", "darkly-bin"):
            args = velora.parser().parse_args(["install", "--build-from-source", name])
            features, _ = velora.selected_features(args)
            with self.assertRaises(velora.VeloraError):
                velora.source_selection(args, features)

    def test_skip_aur_cannot_be_bypassed_by_source_builds(self):
        args = velora.parser().parse_args(["install", "--skip-aur", "--build-from-source", "mpvpaper"])
        features, _ = velora.selected_features(args)
        with self.assertRaisesRegex(velora.VeloraError, "conflicts"):
            velora.source_selection(args, features)

    def test_official_source_recipe_is_fetched_built_and_recorded(self):
        commands = []

        def run(command, **kwargs):
            commands.append([str(part) for part in command])
            if command[:3] == ["git", "rev-parse", "HEAD"]:
                return "recipe-revision"
            if command == ["pacman", "-Qq"]:
                return "quickshell"
            if command == ["pacman", "-Q", "quickshell"]:
                return "quickshell 0.3.0-1"
            return ""

        state = self.base / "source-state"
        builds.build_dependency("quickshell", official=True, run=run, state=state, cache=self.base / "packages")
        self.assertTrue(any(command[:5] == ["pkgctl", "repo", "clone", "--protocol", "https"] for command in commands))
        self.assertTrue(any(command[:3] == ["makepkg", "--syncdeps", "--install"] for command in commands))
        self.assertEqual(json.loads((state / "quickshell.json").read_text())["recipe"], "recipe-revision")
        commands.clear()
        builds.build_dependency("quickshell", official=True, run=run, state=state, cache=self.base / "packages")
        self.assertFalse(any(command[0] == "makepkg" for command in commands))

    def test_failed_native_build_does_not_record_success(self):
        def run(command, **kwargs):
            if command[0] == "makepkg":
                raise velora.VeloraError("build failed")
            return "revision" if command[0] == "git" else ""

        state = self.base / "source-state"
        with self.assertRaisesRegex(velora.VeloraError, "build failed"):
            builds.build_dependency("mpvpaper", official=False, run=run, state=state, cache=self.base / "packages")
        self.assertFalse((state / "mpvpaper.json").exists())

    def test_package_dry_run_creates_no_build_files(self):
        output = self.base / "packages"
        with patch.object(velora, "run") as run:
            builds.build_package(PROJECT, output, {}, run, dry=True, install=True)
            self.assertTrue(all(call.kwargs.get("dry") for call in run.call_args_list))
        self.assertFalse(output.exists())

    def test_package_snapshot_contains_sources_and_omits_runtime_settings(self):
        source = self.base / "source"
        (source / "packaging/arch").mkdir(parents=True)
        (source / "packaging/arch/PKGBUILD.in").write_text((PROJECT / "packaging/arch/PKGBUILD.in").read_text())
        private = source / "dots/.config/illogical-impulse"
        private.mkdir(parents=True)
        (private / "config.json").write_text('{"private": true}')
        (private / "config.example.json").write_text('{}')
        (source / "VERSION").write_text("0.1.0")
        (source / "LICENSE").write_text("license")
        (source / "NOTICE").write_text("notice")
        (source / "velora").write_text("#!/bin/sh\n")
        metadata = {"version": "0.1.0", "source_revision": "a" * 40, "commit_count": 1}
        build = self.base / "build"
        recipe = builds.prepare_package(source, build, metadata, velora.run)
        snapshot = build / "snapshot/velora"
        self.assertFalse((snapshot / "dots/.config/illogical-impulse/config.json").exists())
        self.assertTrue((snapshot / "dots/.config/illogical-impulse/config.example.json").exists())
        self.assertEqual(json.loads((snapshot / ".velora-package.json").read_text()), metadata)
        self.assertNotIn("@SHA256@", recipe.read_text())
        subprocess.run(["bash", "-n", str(recipe)], check=True)

    def test_packaged_source_rejects_symlinks_outside_the_project(self):
        source = self.base / "source"
        source.mkdir()
        outside = self.base / "private"
        outside.write_text("private data")
        (source / "link").symlink_to(outside)
        with self.assertRaisesRegex(ValueError, "outside the project"):
            builds.copy_source(source / "link", self.base / "copy", source)


class RuntimeTemplateTests(IsolatedTest):
    def setUp(self):
        super().setUp()
        self.source = self.base / "source"
        self.file = self.source / "dots/.config/example/config"
        self.file.parent.mkdir(parents=True)
        self.file.write_text("original")
        (self.source / "home").mkdir()
        self.runtime = self.base / "runtime"

    def test_package_refresh_updates_unedited_templates(self):
        sync_runtime(self.source, self.runtime)
        self.file.write_text("updated upstream")
        self.assertEqual(sync_runtime(self.source, self.runtime), [])
        self.assertEqual((self.runtime / self.file.relative_to(self.source)).read_text(), "updated upstream")

    def test_local_edits_survive_with_incoming_conflict_copy(self):
        sync_runtime(self.source, self.runtime)
        target = self.runtime / self.file.relative_to(self.source)
        target.write_text("local change")
        self.file.write_text("upstream change")
        conflicts = sync_runtime(self.source, self.runtime)
        self.assertEqual(conflicts, ["dots/.config/example/config"])
        self.assertEqual(target.read_text(), "local change")
        self.assertEqual((self.runtime / ".incoming/dots/.config/example/config").read_text(), "upstream change")

    def test_deleted_upstream_templates_are_removed_only_if_unedited(self):
        other = self.file.parent / "local"
        other.write_text("original")
        sync_runtime(self.source, self.runtime)
        local = self.runtime / other.relative_to(self.source)
        local.write_text("local change")
        self.file.unlink()
        other.unlink()
        sync_runtime(self.source, self.runtime)
        self.assertFalse((self.runtime / "dots/.config/example/config").exists())
        self.assertEqual(local.read_text(), "local change")

    def test_external_runtime_directory_link_is_not_written_through(self):
        target = self.runtime / "dots/.config"
        target.mkdir(parents=True)
        external = self.base / "external"
        external.mkdir()
        (target / "example").symlink_to(external)
        with self.assertRaisesRegex(ValueError, "outside the runtime"):
            sync_runtime(self.source, self.runtime)
        self.assertFalse((external / "config").exists())


class GitHubReleaseTests(IsolatedTest):
    def test_no_published_release_is_reported_explicitly(self):
        error = velora.HTTPError("https://api.github.com/", 404, "Not found", {}, None)
        with patch.object(velora, "urlopen", side_effect=error):
            with self.assertRaisesRegex(velora.VeloraError, "No published GitHub release"):
                velora.latest_release("https://github.com/FortyXD/Velora.git")

    def test_release_lookup_uses_the_canonical_repository_and_tag(self):
        data = io.BytesIO(json.dumps({"tag_name": "v0.2.0", "html_url": "https://github.com/FortyXD/Velora/releases/tag/v0.2.0"}).encode())
        with patch.object(velora, "urlopen", return_value=data) as open_url:
            release = velora.latest_release("https://github.com/FortyXD/Velora.git")
        self.assertEqual(open_url.call_args.args[0].full_url, "https://api.github.com/repos/FortyXD/Velora/releases/latest")
        self.assertEqual(release["version"], "v0.2.0")

    def test_release_preferences_are_shared_with_the_cli(self):
        args = velora.parser().parse_args(["update-settings", "--channel", "release"])
        velora.configure_updates(args)
        self.assertEqual(velora.update_options()["channel"], "release")

    def test_failed_timer_configuration_does_not_save_a_successful_setting(self):
        service = Path(velora.xdg("XDG_CONFIG_HOME", ".config")) / "systemd/user/velora-update.service"
        service.parent.mkdir(parents=True)
        service.write_text("fixture")
        args = velora.parser().parse_args(["update-settings", "--automatic-checks", "off"])
        with patch.object(velora, "run", side_effect=velora.VeloraError("no user manager")):
            with self.assertRaises(velora.VeloraError):
                velora.configure_updates(args)
        self.assertTrue(velora.update_options()["automatic_checks"])

    def test_package_updates_do_not_offer_an_older_release(self):
        packaged = {"version": "0.2.0", "source_revision": "a" * 40,
                    "source_repository": "https://github.com/FortyXD/Velora.git", "source_branch": "main"}
        with patch.object(velora, "package_metadata", return_value=packaged), \
             patch.object(velora, "latest_release", return_value={"version": "v0.1.0", "url": ""}), \
             patch.object(velora, "run", return_value="b" * 40 + "\trefs/tags/v0.1.0"), \
             patch.object(velora, "compare_package_revision", return_value=(4, 0)):
            status = velora.update_status(channel="release")
        self.assertFalse(status["available"])
        self.assertEqual(status["ahead"], 4)
