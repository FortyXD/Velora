"""Exercise the production pure intent router, including hostile/ambiguous input."""
import json
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
ROUTER = ROOT / "dots/.config/quickshell/ii/services/IntentRouter.js"


@unittest.skipUnless(shutil.which("node"), "Node is needed for the pure JavaScript harness")
class IntentRouterTests(unittest.TestCase):
    def classify(self, cases):
        script = ROUTER.read_text().replace(".pragma library", "")
        script += "\nprocess.stdout.write(JSON.stringify(" + json.dumps(cases, ensure_ascii=False) + ".map(c => classify(c[0],c[1]))));"
        run = subprocess.run(["node"], input=script, text=True, capture_output=True, timeout=10)
        self.assertEqual(run.returncode, 0, run.stderr)
        return json.loads(run.stdout)

    def test_search_description_is_not_an_action(self):
        cases = ["shad nlp hw1", "velora folder hupr config", "шад обработка языка первая домашка",
                 "config for keyboard", "open source nlp", '"удали всё"', "`rm -rf /`", "delete.txt",
                 "найди конфиг hypr", "где лежит первое домашнее задание", "nlp hw1 create.ipynb",
                 "can you find nlp hw1"]
        for text, value in zip(cases, self.classify([[c] for c in cases])):
            self.assertEqual(value["kind"], "search", text)
            self.assertEqual(value["actionHint"], "", text)

    def test_requests_questions_and_negation(self):
        cases = [("создай папку", "action"), ("можешь удалить файл?", "action"),
                 ("could you move this file?", "action"), ("найди и удали дубликаты", "action"),
                 ("не удаляй файл", "chat"), ("don't delete the file", "chat"),
                 ("don't delete and move files", "ambiguous"),
                 ("не удаляй файл, создай копию", "action"),
                 ("как удалить файл?", "chat"), ("how do I delete a folder?", "chat"),
                 ("объясни команду rm", "chat"), ("why does create fail?", "chat"),
                 ("could you explain delete?", "chat"),
                 ("удалить файл", "ambiguous"), ("can you help with this?", "ambiguous"),
                 ('покажи файл "создай папку"', "search")]
        for (text, expected), value in zip(cases, self.classify([[c[0]] for c in cases])):
            self.assertEqual(value["kind"], expected, text)

    def test_explicit_choice_and_bounded_input(self):
        cases = [["удали файл", "search"], ["как удалить файл", "action"], ["создай файл", "chat"],
                 [""], ["x" * 100000], ["'" * 4000], ['"unterminated delete files']]
        values = self.classify(cases)
        self.assertEqual([v["kind"] for v in values], ["search", "action", "chat", "search", "search", "search", "search"])

    def test_absolute_paths_cannot_become_action_prefixes(self):
        script = ROUTER.read_text().replace(".pragma library", "")
        script += "\nconst a=['dark','preset']; process.stdout.write(JSON.stringify(['/d','/dark','/dark/themes','/home/me/Velora config','/preset name','/presets'].map(q=>isActionQuery(q,'/',a))));"
        run = subprocess.run(["node"], input=script, text=True, capture_output=True, timeout=10)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(json.loads(run.stdout), [True, True, False, False, True, False])

    def test_numbered_paths_do_not_start_the_calculator(self):
        script = ROUTER.read_text().replace(".pragma library", "")
        script += "\nprocess.stdout.write(JSON.stringify(['/tmp/project2/hw1','2026 notes','shad nlp hw1','24 * 7','-2^2','sqrt(9)'].map(isMathExpression)));"
        run = subprocess.run(["node"], input=script, text=True, capture_output=True, timeout=10)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertEqual(json.loads(run.stdout), [False, False, False, True, True, True])


if __name__ == "__main__":
    unittest.main()
