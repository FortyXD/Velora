#!/usr/bin/env python3
"""Guest-only delayed/failed capture fixture and live popup readiness assertions.

Install before starting qs, inspect `qs -c ii ipc call previewTest state`, then
--restore while unlocked. Delay/failure marker files only affect this fixture.
"""
import argparse
import json
from pathlib import Path
import shutil

if not Path('/var/lib/velora-qemu-ready').exists():
    raise SystemExit('Only run inside the disposable QEMU guest')
parser = argparse.ArgumentParser()
parser.add_argument('--restore', action='store_true')
args = parser.parse_args()
root = Path.home() / 'Velora/dots/.config/quickshell/ii'
backup = Path('/tmp/velora-ready-fixture')
paths = [root / relative for relative in (
    'modules/ii/dock/DockPreviews.qml', 'modules/waffle/bar/tasks/TaskPreview.qml',
    'modules/waffle/bar/tasks/WindowPreview.qml', 'scripts/helper')]
config = Path.home() / '.config/velora/config.json'
markers = [Path('/tmp/velora-preview-test-delay'), Path('/tmp/velora-preview-test-fail')]
if args.restore:
    for path in paths + [config]:
        shutil.copyfile(backup / path.name, path)
    for marker in markers:
        marker.unlink(missing_ok=True)
    shutil.rmtree(backup)
    print('Restored product files and guest configuration')
    raise SystemExit(0)
backup.mkdir()
for path in paths + [config]:
    shutil.copyfile(path, backup / path.name)

def replace(source, old, new):
    if old not in source:
        raise RuntimeError(f'Fixture insertion point missing: {old}')
    return source.replace(old, new, 1)

diagnostics = '''
    property int testSamples: 0
    property int testInvalid: 0
    function testState() {
        const cards = [];
        for (let i = 0; i < testRepeater.count; ++i) {
            const item = testRepeater.itemAt(i);
            if (!item?.visible) continue;
            const preview = item.testPreview;
            cards.push({id:preview.stableId, ready:preview.hasContent, selectable:item.enabled,
                matched:previewPool.windows.includes(preview.toplevel),
                fallback:preview.showFallback && preview.showFallbackIcon});
        }
        return {visible:root.visible, samples:testSamples, invalid:testInvalid,
            requested:previewPool.current.length, presented:previewPool.windows.length,
            preparing:previewPool.active, cards};
    }
    IpcHandler {
        target: "previewTest"
        function state(): string { return JSON.stringify(root.testState()); }
    }
    Timer {
        interval: 16; running: true; repeat: true
        onTriggered: {
            root.testSamples++;
            const state = root.testState();
            if (!GlobalStates.screenLocked && state.visible && (state.cards.length !== state.presented
                || state.cards.some(card => !card.selectable || !card.matched || (!card.ready && !card.fallback)))) {
                root.testInvalid++;
                console.warn("PREVIEW_INVALID", JSON.stringify(state));
            }
        }
    }
'''
for path in paths[:2]:
    source = path.read_text()
    source = replace(source, 'import Quickshell\n', 'import Quickshell\nimport Quickshell.Io\n')
    source = replace(source, '    id: root', '    id: root\n' + diagnostics)
    source = replace(source, '                Repeater {', '                Repeater {\n                    id: testRepeater')
    if path.name == 'DockPreviews.qml':
        source = replace(source, 'id: windowButton', 'id: windowButton\n                        property alias testPreview: screencopyView')
    path.write_text(source)
path = paths[2]
path.write_text(replace(path.read_text(), '    id: root', '    id: root\n    property alias testPreview: screencopyView'))
path = paths[3]
shim = backup / 'grim'
shim.write_text("""#!/bin/sh
if [ -f /tmp/velora-preview-test-delay ]; then
    read -r seconds id < /tmp/velora-preview-test-delay
    if [ -z "$id" ] || [ "$id" = "$2" ]; then sleep "$seconds"; fi
fi
[ ! -e /tmp/velora-preview-test-fail ] || exit 1
exec /usr/bin/grim "$@"
""")
shim.chmod(0o755)
path.write_text(replace(path.read_text(), '#!/bin/sh', f'#!/bin/sh\nif [ "$1" = window-previews ]; then export PATH="{backup}:$PATH"; fi'))
markers[0].write_text('1.2')
options = json.loads(config.read_text())
options['panelFamily'] = 'velora'
options['dock']['enable'] = True
options['dock']['pinnedApps'] = ['firefox', 'org.kde.dolphin']
config.write_text(json.dumps(options, indent=2) + '\n')
print('Installed 1.2 s capture delay and per-frame popup checks; no host files affected')
