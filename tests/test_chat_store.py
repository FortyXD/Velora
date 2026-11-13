"""Storage acceptance tests; only synthetic conversations in temporary directories."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("chat_store", ROOT / "dots/.config/quickshell/ii/scripts/chat-store.py")
storage = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(storage)


class ChatStoreTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name)
        self.store = storage.Store(self.path)

    def chat(self, **extra):
        return {"id":"chat-1", "title":"Example", "mode":"assistant", "createdAt":1, "updatedAt":2,
                "draft":"next message", "messages":[{"role":"user","text":"Find report"},
                    {"role":"assistant","text":"Partial answer", "status":"streaming", "hasActions":True,
                     "steps":[{"label":"Read file", "path":"/example/report"}],
                     "approval":{"allow":True}, "preview":"private-image", "functionCall":{"name":"delete"}}], **extra}

    def test_autosaved_partial_is_recoverable_without_live_permissions(self):
        self.store.save(self.chat())
        recovered = storage.Store(self.path).load("chat-1")
        self.assertEqual(recovered["draft"], "next message")
        self.assertEqual(recovered["messages"][-1]["text"], "Partial answer")
        self.assertEqual(recovered["messages"][-1]["status"], "interrupted")
        content = self.store.path("chat-1").read_text()
        self.assertNotIn("private-image", content)
        self.assertNotIn("approval", content)
        self.assertNotIn("functionCall", content)
        self.assertEqual(self.store.path("chat-1").stat().st_mode & 0o777, 0o600)

    def test_failed_atomic_replace_preserves_previous_conversation(self):
        self.store.save(self.chat())
        before = self.store.path("chat-1").read_bytes()
        with patch.object(storage.os, "replace", side_effect=OSError("disk full")):
            with self.assertRaises(OSError): self.store.save(self.chat(draft="new"))
        self.assertEqual(self.store.path("chat-1").read_bytes(), before)
        self.assertFalse(list(self.store.root.glob(".chat-*")))

    def test_truncated_answer_remains_readable_after_restart(self):
        chat = self.chat()
        chat["messages"][-1].update(status="done", truncated=True, error="")
        self.store.save(chat)
        restored = storage.Store(self.path).load("chat-1")["messages"][-1]
        self.assertEqual(restored["text"], "Partial answer")
        self.assertEqual(restored["status"], "done")
        self.assertTrue(restored["truncated"])
        self.assertEqual(restored["error"], "")

    def test_transaction_history_survives_restart_without_grants(self):
        chat = self.chat()
        chat["messages"][-1].update({"submissionId":"submit-1", "transactionId":"tx-1",
            "transactionState":"rollback_conflict", "rollbackAvailable":True, "conflicts":["/example/newer.txt"],
            "changes":[{"path":"/example/report", "change":"modified", "token":"must-not-persist"}],
            "approvalToken":"must-not-persist", "capabilities":["write"], "status":"rolling_back"})
        self.store.save(chat)
        restored = storage.Store(self.path).load("chat-1")["messages"][-1]
        self.assertEqual(restored["submissionId"], "submit-1")
        self.assertEqual(restored["transactionId"], "tx-1")
        self.assertEqual(restored["transactionState"], "rollback_conflict")
        self.assertEqual(restored["conflicts"], ["/example/newer.txt"])
        self.assertEqual(restored["status"], "interrupted")
        self.assertTrue(restored["rollbackAvailable"])
        self.assertNotIn("must-not-persist", self.store.path("chat-1").read_text())

    def test_version_one_remains_readable_and_saves_as_version_two(self):
        self.store.save(self.chat())
        value = json.loads(self.store.path("chat-1").read_text())
        value["version"] = 1
        self.store.path("chat-1").write_text(json.dumps(value))
        self.assertEqual(self.store.load("chat-1")["id"], "chat-1")
        self.store.save(self.store.load("chat-1"))
        self.assertEqual(json.loads(self.store.path("chat-1").read_text())["version"], 2)

    def test_save_fsyncs_file_and_parent_directory(self):
        with patch.object(storage.os, "fsync", wraps=storage.os.fsync) as sync:
            self.store.save(self.chat())
        self.assertEqual(sync.call_count, 2)

    def test_consent_history_is_audit_text_without_a_replayable_grant(self):
        chat = self.chat()
        chat["messages"][-1].update({"functionCall":{"name":"remote_context", "args":{"fingerprint":"private-grant"}},
                                    "functionPending":True})
        self.store.save(chat)
        restored = self.store.load("chat-1")["messages"][-1]
        self.assertTrue(restored["contextExcluded"])
        self.assertNotIn("private-grant", self.store.path("chat-1").read_text())

    def test_legacy_import_is_once_and_deletion_does_not_reimport(self):
        legacy = self.path / "lastSession.json"
        legacy.write_text(json.dumps([{"role":"user","rawContent":"Старый чат"}]))
        original = legacy.read_bytes()
        self.store.migrate(); self.store.migrate()
        chats = self.store.listing("СТАРЫЙ")
        self.assertEqual(len(chats), 1)
        self.store.dispatch({"method":"delete", "params":{"id":chats[0]["id"]}})
        self.store.migrate()
        self.assertEqual(self.store.listing(), [])
        self.assertEqual(legacy.read_bytes(), original)

    def test_search_rename_export_and_invalid_identifiers(self):
        self.store.save(self.chat())
        self.assertEqual(len(self.store.listing("REPORT")), 1)
        self.store.dispatch({"method":"rename", "params":{"id":"chat-1", "title":"Research"}})
        self.assertEqual(self.store.listing("research")[0]["title"], "Research")
        exported = self.path / "export.md"
        self.store.dispatch({"method":"export", "params":{"id":"chat-1", "path":str(exported)}})
        self.assertIn("## User\n\nFind report", exported.read_text())
        for uid in ("../escape", "/absolute", "x/y", ""):
            with self.assertRaises(ValueError): self.store.path(uid)

    def test_invalid_file_does_not_hide_other_conversations(self):
        self.store.save(self.chat())
        (self.store.root / "broken.json").write_text("{")
        (self.path / "invalid-legacy.json").write_text("null")
        self.store.migrate()
        self.assertEqual(len(self.store.listing()), 1)
