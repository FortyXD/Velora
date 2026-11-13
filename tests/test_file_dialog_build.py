"""Build the addon twice from different source roots using the same installer cache."""
import ctypes
from pathlib import Path
import shutil
import unittest
from unittest.mock import patch

from test_velora import IsolatedTest, velora


@unittest.skipUnless(shutil.which("cmake") and shutil.which("cc"), "CMake and a C compiler are required")
class FileDialogBuildTests(IsolatedTest):
    def test_moved_checkout_reuses_cache_and_replaces_installed_addon(self):
        destination = self.base / "data/velora/qt6/plugins/generic/libvelora-file-dialog.so"
        versions = []
        for index in (1, 2):
            checkout = self.base / f"checkout {index}"
            source = checkout / "tools/velora-file-dialog"
            source.mkdir(parents=True)
            (source / "CMakeLists.txt").write_text(
                "cmake_minimum_required(VERSION 3.24)\n"
                "project(DialogFixture C)\n"
                "add_library(velora-file-dialog SHARED plugin.c)\n")
            (source / "plugin.c").write_text(f"int fixture_version(void) {{ return {index}; }}\n")
            with patch.object(velora, "ROOT", checkout):
                velora.build_file_dialog()
            self.assertTrue(destination.is_file())
            self.assertEqual(destination.stat().st_mode & 0o777, 0o755)
            # Separate filenames avoid dlopen reusing a previously loaded library.
            installed_copy = self.base / f"installed-{index}.so"
            shutil.copy2(destination, installed_copy)
            versions.append(ctypes.CDLL(str(installed_copy)).fixture_version())
        self.assertEqual(versions, [1, 2])
