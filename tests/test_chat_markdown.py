"""Streaming Markdown parser in Qt's JavaScript engine."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import test_connectivity_qml as support


@unittest.skipUnless(support.QT_TEST_RUNNER, "Qt Quick Test unavailable")
class ChatMarkdownTests(unittest.TestCase):
    def test_streaming_markdown(self):
        with tempfile.TemporaryDirectory(prefix="chat-markdown-") as directory:
            root = Path(directory)
            shutil.copy2(support.SHELL / "modules/ii/sidebarLeft/aiChat/ChatMarkdown.js", root)
            shutil.copy2(support.PROJECT / "tests/qml/tst_chat_markdown.qml", root)
            result = subprocess.run([support.QT_TEST_RUNNER, "-input", str(root), "-o", "-,txt"],
                env={**os.environ,"QT_QPA_PLATFORM":"offscreen","QT_QUICK_BACKEND":"software","QT_QPA_PLATFORMTHEME":"generic"},
                capture_output=True,text=True,timeout=30)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
