"""Non-network JSONL peer for the production QML service integration test."""
import json
import os
from pathlib import Path
import sys

state = Path(__file__).with_name('protocol-checks.jsonl')

def record(**data):
    with state.open('a') as stream:
        stream.write(json.dumps(data) + '\n')

def emit(event, **data):
    print(json.dumps(dict(event=event, **data)), flush=True)

record(started=True, safe_argv=all('credential-sentinel' not in x for x in sys.argv),
       safe_environment=all('credential-sentinel' not in x for x in os.environ.values()))
emit('ready')
current = None
for line in sys.stdin:
    data = json.loads(line)
    operation = data['operation']
    if data['command'] == 'connect':
        current = operation
        if data['ssid'] == 'crash':
            sys.exit(1)
        record(hidden=data.get('hidden', False), security=data.get('security', ''), connected=True)
        emit('secret-required', operation=operation, request='1', code='')
    elif data['command'] == 'submit' and operation == current:
        # Only booleans are persisted: never input values or raw request bodies.
        record(secret_ok=data['password'] in (' credential-sentinel-я\n ', 'replacement-credential-sentinel'),
               request=data['request'])
        if data['request'] == '1':
            emit('secret-required', operation=operation, request='2', code='retry')
        else:
            emit('connected', operation=operation, code='')
    elif data['command'] == 'cancel':
        emit('cancelled', operation=operation)
        emit('secret-required', operation=operation, request='stale', code='retry')
        record(cancelled=True)
