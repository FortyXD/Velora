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
            (root / "ChatTextBlock.qml").write_text(support.production("modules/ii/sidebarLeft/aiChat/ChatTextBlock.qml"))
            (root / "StyledTextArea.qml").write_text("import QtQuick.Controls\nTextArea {}")
            (root / "formula.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg" width="20" height="8"><path d="M0 4h20" stroke="black"/></svg>')
            support.write_singletons(root, {
                "Appearance": 'property var font: ({family:{main:"sans",title:"sans"},pixelSize:{normal:12}}); property var m3colors: ({m3onSurface:"black"})',
                "LatexRenderer": '''property var requests: []; property var processedExpressions: ({}); property var renderedImagePaths: ({})
                    signal renderFinished(string hash, string path)
                    function requestRender(expression) {
                        const hash = Qt.md5(expression);
                        requests = requests.concat([expression]);
                        processedExpressions[hash] = expression;
                        return [hash, true];
                    }
                    function finish(expression) {
                        const hash = Qt.md5(expression);
                        renderedImagePaths[hash] = Qt.resolvedUrl("formula.svg").toString();
                        renderFinished(hash, renderedImagePaths[hash]);
                    }''',
            })
            shutil.copy2(support.PROJECT / "tests/qml/tst_chat_markdown.qml", root)
            result = subprocess.run([support.QT_TEST_RUNNER, "-input", str(root), "-o", "-,txt"],
                env={**os.environ,"QT_QPA_PLATFORM":"offscreen","QT_QUICK_BACKEND":"software","QT_QPA_PLATFORMTHEME":"generic"},
                capture_output=True,text=True,timeout=30)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
