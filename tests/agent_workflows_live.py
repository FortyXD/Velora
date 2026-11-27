"""Measure a real local assistant and check its work against files in a private desktop."""
import argparse
import csv
import json
import os
from pathlib import Path
import random
import secrets
import shutil
import subprocess
import tempfile
import time
import urllib.request

import test_agent


def submit(fixture, text, name):
    start = time.monotonic()
    task = fixture.send("submit", {"text": text, "desktop_agent": True, "conversation_id": name})
    first = None
    answer = ""
    steps = []
    errors = []
    approvals = []
    rounds = 0
    while True:
        event = fixture.events.get(timeout=600)
        if event.get("task") != task:
            continue
        kind = event["type"]
        if kind == "phase" and event.get("phase") == "loading":
            rounds += 1
        elif kind == "approval":
            approvals.append(event["tool"])
            if event["tool"] == "terminal_run":
                details = event["details"]
                print(json.dumps({"case":name, "working_folder":details["cwd"],
                                  "program":details.get("code", details.get("command"))}, ensure_ascii=False), flush=True)
            fixture.send("approve", {"task":task, "approval":event["approval"], "allow":True})
        elif kind == "delta" and event.get("text", "").strip() and first is None:
            first = time.monotonic() - start
        elif kind == "step" and event["state"] in ("done", "retry", "failed"):
            steps.append([event["tool"], event["state"]])
            if event["state"] == "retry":
                print(json.dumps({"case":name, "retry":event.get("target")}, ensure_ascii=False), flush=True)
        elif kind == "error":
            errors.append(event["message"])
        elif kind == "answer":
            answer = event["text"]
        elif kind == "finished":
            break
    result = {"case":name, "first_text_s":first, "total_s":time.monotonic()-start,
              "rounds":rounds, "steps":steps, "approvals":approvals, "answer":answer, "errors":errors}
    print(json.dumps(result, ensure_ascii=False), flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path)
    parser.add_argument("--model", default="gemma4:e4b")
    parser.add_argument("--case", choices=("latency", "workflows", "lookup", "both"), default="both")
    parser.add_argument("--prewarm", action="store_true")
    parser.add_argument("--seed", type=int, help="Use a reproducible variation of the input table")
    args = parser.parse_args()
    if not os.environ.get("VELORA_TEST_PREBUILT"):
        parser.error("Run with tests/run_isolated.py and installed OLLAMA_MODELS")
    source = Path(os.environ["OLLAMA_MODELS"])
    test_agent.BINARY = args.binary.resolve()
    with tempfile.TemporaryDirectory() as temporary:
        models = Path(temporary)/"models"
        shutil.copytree(source/"manifests", models/"manifests")
        (models/"blobs").symlink_to(source/"blobs")
        os.environ["OLLAMA_MODELS"] = str(models)
        fixture = test_agent.AgentTests()
        fixture.setUp()
        try:
            fixture.fake("curl", """
import subprocess
request = sys.stdin.buffer.read()
proc = subprocess.Popen(['/usr/bin/curl', *sys.argv[1:]], stdin=subprocess.PIPE, stdout=subprocess.PIPE)
proc.stdin.write(request)
proc.stdin.close()
for line in proc.stdout:
    sys.stdout.buffer.write(line)
    sys.stdout.buffer.flush()
    if b'"/api/chat"' in request or b'/api/chat' in request:
        try: part = json.loads(line)
        except ValueError: continue
        if part.get('done'):
            with open(os.environ['TEST_ROOT'] + '/timings', 'a') as log:
                print(json.dumps({k:part.get(k) for k in ('load_duration','prompt_eval_count','prompt_eval_duration','eval_count')}), file=log)
sys.exit(proc.wait())
""")
            profile = {"provider":"ollama", "model":args.model, "endpoint":"http://127.0.0.1:11435",
                       "gpu":False, "context_tokens":16384}
            fixture.configure(profile=profile, on_battery=False)
            if args.prewarm:
                start = time.monotonic()
                probe = fixture.send("probe")
                fixture.until(lambda event: event.get("task")==probe and event["type"]=="finished", seconds=120)
                prefix = json.loads(subprocess.check_output([test_agent.BINARY, "--warmup-prefix"]))
                payload = dict(prefix, model=args.model, stream=False, think=False, keep_alive=3600,
                               options=dict(num_ctx=16384, num_gpu=0, num_batch=32, temperature=0.1, num_predict=1))
                req = urllib.request.Request(profile["endpoint"]+"/api/chat", json.dumps(payload).encode(),
                                             {"Content-Type":"application/json"})
                with urllib.request.urlopen(req, timeout=180) as response:
                    warm = json.load(response)
                    assert warm["done"]
                print(json.dumps({"warmup_s":time.monotonic()-start, "load_s":warm.get("load_duration", 0)/1e9,
                                  "prefill_tokens":warm.get("prompt_eval_count")}), flush=True)
            if args.case in ("latency", "both"):
                for index, city in enumerate(("Франции", "Италии", "Испании")):
                    fixture.send("restore", {"messages":[]})
                    result = submit(fixture, f"Назови столицу {city} одним словом.", f"latency-{index}")
                    assert result["first_text_s"] is not None and not result["errors"], result
            if args.case in ("workflows", "both"):
                folder = fixture.home/"Documents"/"orders"
                folder.mkdir(parents=True)
                rows = [("Lyon",7), ("Rome",5), ("Lyon",4)]
                if args.seed is not None:
                    generator = random.Random(args.seed)
                    rows = [(city, generator.randint(2, 90)) for city in ("Lima", "Brno", "Lima", "Kyoto", "Brno")]
                    generator.shuffle(rows)
                with (folder/"sales.tsv").open("w", newline="") as source_file:
                    writer = csv.writer(source_file, delimiter="\t")
                    writer.writerow(("city","count"))
                    writer.writerows(rows)
                expected = {}
                for city, count in rows: expected[city] = expected.get(city, 0) + count
                fixture.send("restore", {"messages":[]})
                fixture.configure(profile=profile, selection=[str(folder)], on_battery=False)
                result = submit(fixture, "В выбранной папке лежит sales.tsv. Сгруппируй строки по городу и сложи count. "
                                "Сохрани результат рядом в totals.csv со столбцами city,total. Проверь файл.", "aggregate")
                with (folder/"totals.csv").open() as output:
                    records = csv.DictReader(output)
                    assert records.fieldnames == ["city","total"], records.fieldnames
                    actual = [(row["city"],int(row["total"])) for row in records]
                assert not result["errors"] and sorted(actual) == sorted(expected.items()), (result, actual, expected)
            if args.case in ("lookup", "both"):
                folder = fixture.home/"Documents"
                folder.mkdir(exist_ok=True)
                marker = secrets.token_hex(4)
                (folder/"expedicion-norte.txt").write_text("Código de la reserva: " + marker)
                fixture.send("restore", {"messages":[]})
                fixture.configure(profile=profile, on_battery=False)
                result = submit(fixture, "¿Cuál es el código de la reserva en mi nota expedicion-norte.txt? "
                                "Consulta la nota y contesta solo con el código.", "spanish-lookup")
                assert not result["errors"] and not result["approvals"] and marker in result["answer"], result
        finally:
            timings = fixture.root/"timings"
            if timings.exists(): print(timings.read_text(), flush=True)
            fixture.tearDown()


if __name__ == "__main__":
    main()
