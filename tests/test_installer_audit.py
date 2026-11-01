"""Filesystem safety regressions, confined to temporary installation roots."""
import json
import shutil
from unittest.mock import patch

from test_velora import IsolatedTest, PROJECT, velora
import builds
from runtime import sync_runtime


class InstallerAuditTests(IsolatedTest):
    def runtime_fixture(self):
        source = self.base / "source"
        template = source / "dots/.config/example/config"
        template.parent.mkdir(parents=True)
        template.write_text("original")
        runtime = self.base / "runtime"
        sync_runtime(source, runtime)
        return source, template, runtime, runtime / template.relative_to(source)

    def test_runtime_conflicts_do_not_follow_external_incoming_directory(self):
        source, template, runtime, target = self.runtime_fixture()
        target.write_text("local edit")
        template.write_text("upstream change")
        external = self.base / "external"
        external.mkdir()
        (runtime / ".incoming").symlink_to(external, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "outside the runtime"):
            sync_runtime(source, runtime)
        self.assertEqual(list(external.iterdir()), [])
        self.assertEqual(target.read_text(), "local edit")

    def test_obsolete_runtime_template_does_not_delete_through_directory_link(self):
        source, template, runtime, target = self.runtime_fixture()
        external = self.base / "external"
        external.mkdir()
        sentinel = external / "config"
        sentinel.write_text("original")
        target.unlink()
        target.parent.rmdir()
        target.parent.symlink_to(external, target_is_directory=True)
        template.unlink()
        with self.assertRaisesRegex(ValueError, "outside the runtime"):
            sync_runtime(source, runtime)
        self.assertEqual(sentinel.read_text(), "original")

    def test_runtime_manifest_temporary_symlink_does_not_overwrite_external_file(self):
        source, template, runtime, target = self.runtime_fixture()
        sentinel = self.base / "external"
        sentinel.write_text("keep")
        (runtime / ".velora-runtime.tmp").symlink_to(sentinel)
        sync_runtime(source, runtime)
        self.assertEqual(sentinel.read_text(), "keep")
        manifest = runtime / ".velora-runtime.json"
        self.assertFalse(manifest.is_symlink())
        self.assertIn("dots/.config/example/config", json.loads(manifest.read_text()))

    def test_packaged_source_retains_rust_build_inputs_without_git_metadata(self):
        source = self.base / "source"
        recipe = source / "packaging/arch/PKGBUILD.in"
        recipe.parent.mkdir(parents=True)
        shutil.copyfile(PROJECT / "packaging/arch/PKGBUILD.in", recipe)
        manifest = source / "tools/Cargo.toml"
        manifest.parent.mkdir()
        manifest.write_text("[workspace]\n")
        crate = source / "tools/velora-helper/src/main.rs"
        crate.parent.mkdir(parents=True)
        crate.write_text("fn main() {}\n")
        build = self.base / "build"
        builds.prepare_package(source, build,
                               {"version": "0.1.0", "source_revision": "a" * 40}, velora.run)
        snapshot = build / "snapshot/velora"
        self.assertEqual((snapshot / "tools/Cargo.toml").read_text(), manifest.read_text())
        self.assertEqual((snapshot / "tools/velora-helper/src/main.rs").read_text(), crate.read_text())

    def test_native_staging_does_not_follow_preexisting_temporary_symlink(self):
        packaged = self.base / "package-bin"
        packaged.mkdir()
        for name in velora.NATIVE_BINARIES:
            (packaged / name).write_text("packaged " + name)
            (packaged / name).chmod(0o755)
        sentinel = self.base / "external"
        sentinel.write_text("keep")
        binary = velora.native_helper_path()
        binary.parent.mkdir(parents=True)
        binary.with_name(".velora-helper.new").symlink_to(sentinel)
        with patch.object(velora, "package_metadata", return_value={"version": "1"}), \
                patch.object(velora, "packaged_native_path", side_effect=lambda name: packaged / name):
            velora.build_native_helper()
        self.assertEqual(sentinel.read_text(), "keep")
        self.assertFalse(binary.is_symlink())
        self.assertEqual(binary.read_text(), "packaged velora-helper")

    def test_packaged_source_omits_cargo_cache_but_keeps_target_named_fixtures(self):
        source = self.base / "source"
        recipe = source / "packaging/arch/PKGBUILD.in"
        recipe.parent.mkdir(parents=True)
        shutil.copyfile(PROJECT / "packaging/arch/PKGBUILD.in", recipe)
        cache = source / "tools/target/debug/build-cache"
        cache.parent.mkdir(parents=True)
        cache.write_text("generated compiler output")
        fixture = source / "tools/velora-helper/tests/target/fixture"
        fixture.parent.mkdir(parents=True)
        fixture.write_text("test source data")
        build = self.base / "build"
        builds.prepare_package(source, build,
                               {"version": "0.1.0", "source_revision": "a" * 40}, velora.run)
        snapshot = build / "snapshot/velora"
        self.assertFalse((snapshot / "tools/target").exists())
        self.assertEqual((snapshot / fixture.relative_to(source)).read_text(), "test source data")

    def test_enabling_updates_repairs_a_missing_or_stale_timer(self):
        units = velora.xdg("XDG_CONFIG_HOME", ".config") / "systemd/user"
        units.mkdir(parents=True)
        service, timer = velora.update_units()
        (units / "velora-update.service").write_text(service)
        target = units / "velora-update.timer"
        args = velora.parser().parse_args(["update-settings", "--automatic-checks", "on"])
        for old in (None, "[Timer]\nOnStartupSec=1sec\n"):
            with self.subTest(previous_timer=old):
                if old is not None:
                    target.write_text(old)
                with patch.object(velora, "run"):
                    velora.configure_updates(args)
                self.assertTrue(target.exists())
                self.assertEqual(target.read_text(), timer)

    def test_doctor_fails_when_the_native_helper_is_missing(self):
        python = velora.xdg("XDG_STATE_HOME", ".local/state") / "quickshell/.venv/bin/python"
        python.parent.mkdir(parents=True)
        python.touch()
        with patch.object(velora, "font_installed", return_value=True), \
                patch.object(velora, "package_plan", return_value=([], [])), \
                patch.object(velora, "stale_links", return_value=[]), \
                patch.object(velora, "runtime_problems", return_value=[]), \
                patch.object(velora, "service_active", return_value=True), \
                patch.object(velora, "connection_service", return_value="/usr/bin/velora-connectivityd"), \
                patch.object(velora.shutil, "which", side_effect=lambda name: None if name == "velora-helper" else "/usr/bin/tool"):
            with self.assertRaises(velora.VeloraError):
                velora.doctor(velora.parser().parse_args(["doctor"]))
