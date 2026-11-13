"""Model discovery reads only the store used by the local Ollama launcher."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'dots/.config/quickshell/ii/scripts/ai/show-installed-ollama-models.sh'


class OllamaCatalogueTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='ollama-catalogue-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.home = self.root / 'home'
        self.models = self.home / '.ollama/models'
        self.manifest(self.models, 'registry.ollama.ai/library/qwen3.5/latest', 600)

    def manifest(self, directory, name, size):
        path = directory / 'manifests' / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({'layers':[{'size':size}]}))

    def catalogue(self, override=None):
        environment = {**os.environ, 'HOME':str(self.home)}
        environment.pop('OLLAMA_MODELS', None)
        if override is not None:
            environment['OLLAMA_MODELS'] = str(override)
        result = subprocess.run(['bash', str(SCRIPT)], env=environment,
                                capture_output=True, text=True, check=True)
        return json.loads(result.stdout)

    def test_home_store_excludes_other_installations(self):
        self.assertEqual(self.catalogue(), [{'name':'qwen3.5:latest', 'size':600}])
        self.assertEqual(self.catalogue(''), [{'name':'qwen3.5:latest', 'size':600}])

    def test_explicit_store_is_exclusive_and_preserves_names(self):
        custom = self.root / 'custom models'
        self.manifest(custom, 'registry.ollama.ai/author/model/8b', 80)
        self.manifest(custom, 'example.com/team/model/latest', 120)
        self.assertEqual(self.catalogue(custom), [
            {'name':'author/model:8b', 'size':80},
            {'name':'example.com/team/model:latest', 'size':120},
        ])

    def test_empty_or_missing_explicit_store_does_not_fall_back(self):
        custom = self.root / 'empty'
        self.assertEqual(self.catalogue(custom), [])
        (custom / 'manifests').mkdir(parents=True)
        self.assertEqual(self.catalogue(custom), [])

    def test_empty_home_store_does_not_expose_system_models(self):
        for path in (self.models / 'manifests').rglob('*'):
            if path.is_file():
                path.unlink()
        self.assertEqual(self.catalogue(), [])


if __name__ == '__main__':
    unittest.main()
