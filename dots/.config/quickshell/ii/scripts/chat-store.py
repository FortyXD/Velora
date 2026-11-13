#!/usr/bin/env python3
"""Private, atomic sidebar chat storage. JSON lines on stdin/stdout; no model IO."""
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import tempfile
import time


def atomic_write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, name = tempfile.mkstemp(prefix=".chat-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
        directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def clean_messages(messages):
    if not isinstance(messages, list):
        raise ValueError("Invalid chat messages")
    result = []
    for index, item in enumerate(messages):
        if not isinstance(item, dict) or item.get("role") not in ("user", "assistant"):
            continue
        text = item.get("text", item.get("rawContent", ""))
        if not isinstance(text, str):
            continue
        result.append({
            "uid": str(item.get("uid") or f"message-{index}"),
            "role": item["role"], "text": text,
            "model": str(item.get("model") or ""),
            "status": item.get("status", "done"),
            "truncated": item.get("truncated") is True,
            "hasActions": bool(item.get("hasActions") or item.get("functionCall")),
            "contextExcluded": item.get("contextExcluded") is True or (isinstance(item.get("functionCall"), dict)
                                and item["functionCall"].get("name") == "remote_context"),
            "attachments": [p for p in item.get("attachments", []) if isinstance(p, str)],
            "steps": [{"label": str(s.get("label", "")), "path": str(s.get("path", ""))}
                      for s in item.get("steps", []) if isinstance(s, dict)],
            "error": str(item.get("error") or ""),
            # Historical identifiers are references, never grants or replayable calls.
            "submissionId": str(item.get("submissionId") or "")[:100],
            "transactionId": str(item.get("transactionId") or "")[:100],
            "transactionState": str(item.get("transactionState") or "")[:40],
            "rollbackAvailable": bool(item.get("rollbackAvailable", False)),
            "conflicts": [p for p in item.get("conflicts", []) if isinstance(p, str)][:1000],
            "changes": [{"path": str(c.get("path", "")), "change": str(c.get("change", ""))}
                        for c in item.get("changes", []) if isinstance(c, dict)][:1000],
        })
    return result


class Store:
    def __init__(self, legacy):
        self.legacy = Path(legacy)
        self.root = self.legacy / "conversations"
        self.root.mkdir(parents=True, exist_ok=True, mode=0o700)

    def path(self, uid):
        if not isinstance(uid, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,100}", uid):
            raise ValueError("Invalid chat identifier")
        return self.root / (uid + ".json")

    def save(self, chat):
        path = self.path(chat["id"])
        value = {"version": 2, "id": chat["id"],
                 "title": str(chat.get("title") or "")[:200],
                 "createdAt": chat.get("createdAt", int(time.time() * 1000)),
                 "updatedAt": chat.get("updatedAt", int(time.time() * 1000)),
                 "mode": "assistant" if chat.get("mode") == "assistant" else "chat",
                 "model": str(chat.get("model") or ""),
                 "draft": str(chat.get("draft") or ""),
                 "messages": clean_messages(chat.get("messages", []))}
        atomic_write(path, json.dumps(value, ensure_ascii=False))
        return value

    def load(self, uid):
        value = json.loads(self.path(uid).read_text())
        if value.get("version") not in (1, 2):
            raise ValueError("Unsupported chat version")
        value["messages"] = clean_messages(value.get("messages", []))
        for message in value["messages"]:
            if message["status"] in ("preparing", "streaming", "waiting", "approval", "rolling_back"):
                message["status"] = "interrupted"
        return value

    def migrate(self):
        marker = self.root / ".imported.json"
        imported = json.loads(marker.read_text()) if marker.exists() else []
        for path in sorted(self.legacy.glob("*.json")):
            if path.name in imported:
                continue
            try:
                messages = clean_messages(json.loads(path.read_text()))
                uid = "legacy-" + hashlib.sha256(path.name.encode()).hexdigest()[:24]
                if not self.path(uid).exists():
                    self.save({"id": uid, "title": path.stem,
                               "createdAt": int(path.stat().st_mtime * 1000),
                               "updatedAt": int(path.stat().st_mtime * 1000),
                               "messages": messages})
                imported.append(path.name)
                atomic_write(marker, json.dumps(imported))
            except (ValueError, OSError, TypeError):
                # A malformed old file must not prevent access to other chats.
                continue

    def listing(self, query=""):
        result = []
        query = query.casefold().strip()
        for path in self.root.glob("*.json"):
            try:
                chat = self.load(path.stem)
                text = "\n".join(m["text"] for m in chat["messages"])
                if query and query not in (chat["title"] + "\n" + text).casefold():
                    continue
                result.append({k: chat[k] for k in ("id", "title", "createdAt", "updatedAt", "mode", "model")})
            except (ValueError, OSError, KeyError, TypeError):
                continue
        return sorted(result, key=lambda c: c["updatedAt"], reverse=True)

    def dispatch(self, request):
        op = request["method"]
        data = request.get("params", {})
        if op == "list":
            self.migrate()
            return self.listing(data.get("query", ""))
        if op == "save":
            return self.save(data)["id"]
        if op == "load":
            return self.load(data["id"])
        if op == "delete":
            self.path(data["id"]).unlink(missing_ok=True)
            return True
        if op == "rename":
            chat = self.load(data["id"])
            chat["title"] = data["title"].strip()
            return self.save(chat)["id"]
        if op == "export":
            chat = self.load(data["id"])
            text = "# " + chat["title"] + "\n\n" + "\n\n".join(
                "## " + ("User" if m["role"] == "user" else "Velora") + "\n\n" + m["text"]
                for m in chat["messages"])
            atomic_write(Path(data["path"]), text + "\n")
            return True
        if op == "write":
            atomic_write(Path(data["path"]), data["text"])
            return True
        if op == "files":
            result = []
            for name in data.get("paths", []):
                path = Path(name)
                if not path.is_absolute() or not path.is_file():
                    raise ValueError("Choose an existing local file")
                result.append(str(path))
            return result
        raise ValueError("Unknown chat storage operation")


def main():
    store = Store(sys.argv[1])
    for line in sys.stdin:
        request = {}
        try:
            request = json.loads(line)
            response = {"id": request["id"], "ok": True, "result": store.dispatch(request)}
        except (ValueError, KeyError, OSError, TypeError) as error:
            response = {"id": request.get("id"), "ok": False, "error": str(error)}
        print(json.dumps(response, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
