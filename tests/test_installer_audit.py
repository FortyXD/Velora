"""Filesystem safety regressions, confined to temporary installation roots."""
import json
import errno
import os
import shutil
from unittest.mock import patch

from test_velora import IsolatedTest, PROJECT, velora
import builds
from journal import stage_application_files
import journal as install_journal
from runtime import sync_runtime


class InstallerAuditTests(IsolatedTest):
    def test_retry_recovers_committed_changes_after_a_torn_final_append(self):
        directory = velora.state_dir() / "backups/interrupted"
        directory.mkdir(parents=True)
        (directory / "in-progress").touch()
        journal = directory / "journal.jsonl"
        journal.touch()
        target = self.base / "custom"
        target.write_text("original")
        velora.journal_file(journal, target, content="installed")
        with journal.open("ab") as file:
            file.write(b'{"target": "/interrupted')
        velora.recover_interrupted_install()
        self.assertEqual(target.read_text(), "original")
        self.assertFalse((directory / "in-progress").exists())

    def test_partly_removed_cross_filesystem_directory_uses_the_completed_backup(self):
        target = self.base / "personal"
        target.mkdir()
        (target / "one").write_text("first")
        (target / "two").write_text("second")
        journal = self.base / "backup/journal.jsonl"
        journal.parent.mkdir()
        saved = journal.parent / "original"
        velora.record_change(journal, target, saved)
        rename = os.rename
        def cross_device(source, dest):
            if source == target:
                raise OSError(errno.EXDEV, "Cross-device move")
            return rename(source, dest)
        real_run = install_journal.subprocess.run
        def interrupted(args, **kwargs):
            if args[0] == "rm":
                (target / "one").unlink()
                raise InterruptedError("Interrupted removing the old directory")
            return real_run(args, **kwargs)
        with patch.object(install_journal.os, "rename", side_effect=cross_device), \
                patch.object(install_journal.subprocess, "run", side_effect=interrupted), self.assertRaises(InterruptedError):
            install_journal.move_to_backup(target, saved)
        self.assertTrue((saved / "one").exists())
        self.assertFalse((target / "one").exists())
        velora.restore_journal(journal)
        self.assertEqual((target / "one").read_text(), "first")
        self.assertEqual((target / "two").read_text(), "second")

    def test_full_journal_leaves_original_in_place(self):
        target = self.base / "personal"
        target.write_text("original")
        journal = self.base / "backup/journal.jsonl"
        journal.parent.mkdir()
        journal.touch()
        with patch.object(velora, "record_change", side_effect=OSError(errno.ENOSPC, "No space left")), \
                self.assertRaises(OSError):
            velora.journal_file(journal, target, content="incoming")
        self.assertEqual(target.read_text(), "original")
        self.assertEqual(journal.read_bytes(), b"")

    def test_retry_recovers_move_interrupted_before_backup_was_published(self):
        directory = velora.state_dir() / "backups/interrupted"
        directory.mkdir(parents=True)
        journal = directory / "journal.jsonl"
        target = self.base / "config"
        target.mkdir()
        (target / "custom").write_text("original")
        saved = directory / "original"
        (directory / "in-progress").touch()
        velora.record_change(journal, target, saved)
        target.rename(saved.with_suffix(".partial"))
        velora.recover_interrupted_install()
        self.assertEqual((target / "custom").read_text(), "original")
        self.assertFalse((directory / "in-progress").exists())
        self.assertTrue(journal.with_suffix(".restored").is_file())
        velora.recover_interrupted_install()

    def test_manual_restore_can_resume_after_a_write_error(self):
        journal = self.base / "backup/journal.jsonl"
        journal.parent.mkdir()
        journal.touch()
        first, second = self.base / "first", self.base / "second"
        for target in (first, second):
            target.write_text("custom")
            velora.journal_file(journal, target, content="installed")
        real_move = velora.move_journal_entry
        def deny_one_move(source, destination):
            if destination == first:
                raise PermissionError(errno.EACCES, "Permission denied")
            real_move(source, destination)
        with patch.object(velora, "move_journal_entry", side_effect=deny_one_move), self.assertRaises(PermissionError):
            velora.restore_journal(journal)
        self.assertEqual(second.read_text(), "custom")
        velora.restore_journal(journal)
        self.assertEqual(first.read_text(), "custom")
        self.assertEqual(second.read_text(), "custom")

    def test_external_application_edits_restore_the_original_link_and_leave_its_referent_intact(self):
        journal = self.base / "backup/journal.jsonl"
        journal.parent.mkdir()
        journal.touch()
        personal = self.base / "custom KDE settings"
        personal.write_text("original")
        settings = self.base / "kdeglobals"
        settings.symlink_to(personal.name)
        stage_application_files(journal, [settings])
        settings.write_text("application updated the staged copy")
        self.assertEqual(personal.read_text(), "original")
        velora.restore_journal(journal)
        self.assertEqual(settings.readlink().name, personal.name)
        self.assertEqual(settings.read_text(), "original")

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
        caches = ("tools/target", "tools/velora-translate/target")
        for directory in caches:
            cache = source / directory / "debug/build-cache"
            cache.parent.mkdir(parents=True)
            cache.write_text("generated compiler output")
        fixture = source / "tools/velora-helper/tests/target/fixture"
        fixture.parent.mkdir(parents=True)
        fixture.write_text("test source data")
        build = self.base / "build"
        builds.prepare_package(source, build,
                               {"version": "0.1.0", "source_revision": "a" * 40}, velora.run)
        snapshot = build / "snapshot/velora"
        for directory in caches:
            self.assertFalse((snapshot / directory).exists())
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
        with patch.object(velora, "font_installed", return_value=True), \
                patch.object(velora, "package_plan", return_value=([], [])), \
                patch.object(velora, "stale_links", return_value=[]), \
                patch.object(velora, "runtime_problems", return_value=[]), \
                patch.object(velora, "service_active", return_value=True), \
                patch.object(velora, "connection_service", return_value="/usr/bin/velora-connectivityd"), \
                patch.object(velora.shutil, "which", side_effect=lambda name: None if name == "velora-helper" else "/usr/bin/tool"):
            with self.assertRaises(velora.VeloraError):
                velora.doctor(velora.parser().parse_args(["doctor"]))
