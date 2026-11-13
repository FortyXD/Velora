"""Exercise Hugging Face's real progress adapter with local synthetic transfers."""
import contextlib
import importlib.util
import io
import itertools
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

try:
    import httpx  # HF imports this lazily; a partially installed exporter is not sufficient.
    import huggingface_hub as hub
    from huggingface_hub.utils._xet_progress_reporting import XetDownloadProgressReporter
    from huggingface_hub.utils.tqdm import _get_progress_bar_context
except ImportError:
    hub = None

SOURCE = Path(__file__).resolve().parents[1] / "tools/velora-searchd/python/prepare_models.py"
spec = importlib.util.spec_from_file_location("lens_prepare", SOURCE)
prepare = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prepare)


@unittest.skipUnless(hub, "Optional model export dependencies unavailable")
class LensDownloadProgressTests(unittest.TestCase):
    def run_download(self, sizes, transfer):
        events = []
        with tempfile.TemporaryDirectory(prefix="lens-download-progress-") as directory:
            root = Path(directory)
            files = [SimpleNamespace(filename=f"part-{i}", file_size=size) for i, size in enumerate(sizes)]
            for file in files:
                (root / file.filename).write_bytes(b"x" * (file.file_size or 100))

            def snapshot(**kwargs):
                return files if kwargs.get("dry_run") else str(root)

            def download(**kwargs):
                transfer(kwargs["tqdm_class"])
                return str(root / kwargs["filename"])

            with patch.object(hub, "snapshot_download", side_effect=snapshot), \
                    patch.object(hub, "hf_hub_download", side_effect=download), \
                    patch.object(prepare, "report", side_effect=lambda **event: events.append(event)), \
                    patch.object(prepare.time, "monotonic", side_effect=itertools.count(100)), \
                    contextlib.redirect_stderr(io.StringIO()):
                prepare.download_model(prepare.SOURCES["e5"], "e5", 1, root)
        return events

    def test_xet_transfer_is_separate_from_file_size_and_accumulates_across_files(self):
        def transfer(progress):
            with XetDownloadProgressReporter(reconstruction_desc="weights: reconstructing file",
                                            transfer_desc="weights: downloading bytes", total=100,
                                            log_level=20, tqdm_class=progress) as reporter:
                for done, received in ((40, 25), (100, 55)):
                    reporter.update_progress(SimpleNamespace(total_bytes_completed=done,
                        total_transfer_bytes_completed=received, total_bytes_completion_rate=10,
                        total_transfer_bytes_completion_rate=5, total_bytes=100))
                    # Transfers in this fixture finish faster than tqdm's display interval.
                    reporter.reconstruction_bar.refresh()
                    reporter.transfer_bar.refresh()

        events = self.run_download([100, 100], transfer)
        self.assertTrue(any(e.get("done") == 40 and e.get("transferred") == 25 for e in events))
        self.assertTrue(any(e.get("done") == 140 and e.get("transferred") == 80 for e in events))
        self.assertEqual((events[-1]["done"], events[-1]["total"], events[-1]["transferred"]), (200, 200, 110))

    def test_http_unknown_total_and_cache_hits_do_not_invent_network_bytes(self):
        def transfer(progress):
            with _get_progress_bar_context(desc="weights", log_level=20, total=None, tqdm_class=progress) as bar:
                bar.update(100)

        events = self.run_download([None], transfer)
        self.assertEqual(events[-1]["done"], 100)
        self.assertIsNone(events[-1]["total"])
        self.assertEqual(events[-1]["transferred"], 100)
        events = self.run_download([100], lambda _progress: None)
        self.assertEqual(events[-1]["done"], events[-1]["total"])
        self.assertEqual(events[-1]["transferred"], 0)
