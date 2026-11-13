"""Opt-in CPU acceptance with installed Ollama weights and a private desktop.

python3 tests/run_isolated.py tests/launcher_ai_cpu.py --models /path/to/models
The model blobs are read-only; Ollama metadata and conversations are disposable.
"""
import argparse
import json
import os
from pathlib import Path
import queue
import shutil
import tempfile
import time
import urllib.request

from test_agent import AgentTests, ROOT


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--models', required=True, type=Path)
    parser.add_argument('--model', default='qwen3.5:latest')
    args = parser.parse_args()
    if not os.environ.get('VELORA_TEST_PREBUILT'):
        parser.error('Run this test through tests/run_isolated.py')
    rows = []
    with tempfile.TemporaryDirectory(prefix='launcher-cpu-models-') as directory:
        models = Path(directory)
        shutil.copytree(args.models / 'manifests', models / 'manifests')
        (models / 'blobs').symlink_to(args.models.resolve() / 'blobs')
        os.environ['OLLAMA_MODELS'] = str(models)
        case = AgentTests()
        case.setUp()

        def receive(task, *, cancel_after_delta=False):
            start = time.monotonic()
            events = []
            stop_started = None
            while time.monotonic() - start < 650:
                try:
                    event = case.events.get(timeout=10)
                except queue.Empty:
                    print(f'CPU request: {time.monotonic()-start:.0f}s', flush=True)
                    continue
                if event.get('task') != task:
                    continue
                events.append(event)
                if event['type'] == 'approval':
                    case.send('approve', {'task':task, 'approval':event['approval'], 'allow':False})
                    raise AssertionError('A synthetic chat question unexpectedly requested an action')
                if cancel_after_delta and stop_started is None and event['type'] == 'delta':
                    stop_started = time.monotonic()
                    case.send('cancel')
                if event['type'] in ('finished', 'cancelled'):
                    if cancel_after_delta:
                        assert event['type'] == 'cancelled' and stop_started is not None, events
                        assert time.monotonic() - stop_started < 5, 'Cancellation exceeded five seconds'
                    else:
                        assert not any(e['type'] == 'error' for e in events), events
                        assert any(e['type'] == 'answer' and e['text'].strip() for e in events), events
                    row = dict(seconds=round(time.monotonic()-start, 2), events=events)
                    rows.append(row)
                    print(json.dumps({'seconds':row['seconds'], 'state':event['type'],
                                      'answers':[e['text'] for e in events if e['type']=='answer']},ensure_ascii=False), flush=True)
                    return
            raise TimeoutError('CPU request exceeded its bounded timeout')

        try:
            # A large desktop catalogue previously exhausted a 4096-token chat
            # before even a one-word request reached the model.
            case.configure(on_battery=False,
                           apps=[{'id':f'fixture-{i}.desktop','name':'Synthetic desktop application '+str(i)*20} for i in range(80)],
                           presets=[{'id':str(i),'name':'Synthetic preset '+str(i)*20} for i in range(60)],
                           profile={'provider':'ollama','endpoint':'http://127.0.0.1:11434',
                                    'model':args.model,'gpu':False,'context_tokens':4096})
            receive(case.send('submit', {'text':'Ответь ровно одним словом: Привет','intent':'chat'}))
            receive(case.send('submit', {'text':'Объясни разницу между оперативной памятью и диском в двух предложениях.','intent':'chat'}))
            with urllib.request.urlopen('http://127.0.0.1:11434/api/ps',timeout=5) as response:
                loaded = json.load(response)['models']
            assert loaded and all(model['size_vram']==0 for model in loaded), loaded
            print('CPU_ONLY_CONFIRMED', flush=True)
            receive(case.send('submit', {'text':'Напиши длинную историю о путешествии к далёкой звезде.','intent':'chat'}), cancel_after_delta=True)
            receive(case.send('submit', {'text':'Сколько будет два плюс два? Ответь только числом.','intent':'chat'}))
        finally:
            case.tearDown()
            (ROOT/'cache/launcher-cpu-acceptance.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n')


if __name__ == '__main__':
    main()
