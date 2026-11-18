#!/usr/bin/env python3
"""Measure input-to-drawable thumbnail latency on real Velora surfaces in the guest."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

if not Path('/var/lib/velora-qemu-ready').exists():
    raise SystemExit('Run through in-session.py in the regression guest')
parser = argparse.ArgumentParser()
parser.add_argument('before', type=Path, help='baseline ii configuration directory')
parser.add_argument('after', type=Path, help='candidate ii configuration directory')
args = parser.parse_args()
project = Path(__file__).resolve().parent

def fixture(source, target):
    shutil.copytree(source, target, symlinks=True)
    shutil.copyfile(project / 'PreviewLatency.qml', target / 'shell.qml')
    (target / 'PreviewTiming.qml').write_text('''pragma Singleton
import Quickshell
Singleton {
    property double start: 0
    property var frames: ({})
    function report(id) { if (start && frames[id] === undefined) frames[id] = Date.now() - start; }
}
''')
    thumbnail = target / 'modules/common/widgets/WindowThumbnail.qml'
    text = thumbnail.read_text()
    thumbnail.write_text(text.replace('    id: root', '''    id: root
    readonly property bool drawable: hasContent && visible && !!root.Window.window?.visible
    onDrawableChanged: if (drawable && toplevel?.appId === "velora-latency") PreviewTiming.report(stableId)''', 1))
    switcher = target / 'modules/ii/windowSwitcher/WindowSwitcher.qml'
    text = switcher.read_text()
    switcher.write_text(text.replace('root.windows = HyprlandData.windowList',
                                     'root.windows = HyprlandData.windowList.filter(c => c.class === "velora-latency")', 1))

def hypr(command):
    return json.loads(subprocess.check_output(['hyprctl', '-j', command]))

def run():
    result = {}
    original = hypr('activeworkspace')['id']
    subprocess.run(['hyprctl', 'dispatch', 'hl.dsp.focus({workspace="19"})'], check=True)
    windows = []
    try:
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            for label, source in [('before', args.before), ('after', args.after)]:
                fixture(source, base / label)
            for count in (1, 4, 8):
                while len(windows) < count:
                    windows.append(subprocess.Popen(['foot', '--app-id=velora-latency', '--title=Preview timing', 'sleep', '240'],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
                for _ in range(80):
                    clients = [w for w in hypr('clients') if w['class'] == 'velora-latency']
                    if len(clients) == count: break
                    time.sleep(.1)
                assert len(clients) == count
                assert all(w['workspace']['id'] == 19 for w in clients)
                for label in ('before', 'after'):
                    env = {**os.environ, 'LATENCY_WINDOWS':str(count), 'XDG_CONFIG_HOME':str(base/'config'),
                           'XDG_STATE_HOME':str(base/'state'), 'XDG_CACHE_HOME':str(base/'cache')}
                    run = subprocess.run(['qs', '-p', str(base/label/'shell.qml'), '--no-color'],
                        env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=38)
                    rows = [json.loads(line.split('LATENCY_RESULT ',1)[1]) for line in run.stdout.splitlines() if 'LATENCY_RESULT ' in line]
                    if run.returncode or len(rows) != 8:
                        details = [line for line in run.stdout.splitlines() if any(k in line for k in ('LATENCY_', 'ERROR', 'TypeError', 'ReferenceError', 'Binding loop'))]
                        raise RuntimeError(f'{count} {label}: ' + '\n'.join(details[-35:]))
                    print(count, label, json.dumps(rows), flush=True)
                    result.setdefault(count, {})[label] = rows
            out = Path.home() / 'evidence/preview-surface-latency.json'
            out.write_text(json.dumps(result, indent=2) + '\n')
    finally:
        for process in windows:
            process.terminate()
            process.wait(timeout=5)
        subprocess.run(['hyprctl', 'dispatch', f'hl.dsp.focus({{workspace="{original}"}})'])

run()
