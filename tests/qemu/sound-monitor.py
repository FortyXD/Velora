#!/usr/bin/env python3
"""Exercise the Sound page with an actual microphone-to-speaker PipeWire connection."""
from array import array
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import wave

if not Path('/var/lib/velora-qemu-ready').exists():
    raise SystemExit('Run through in-session.py in the disposable guest')


def output(*args):
    return subprocess.check_output(args, text=True).strip()


def wait_for(check, seconds=8):
    until = time.monotonic() + seconds
    while time.monotonic() < until:
        if check():
            return
        time.sleep(.1)
    raise AssertionError(f'Timed out waiting for {check}')


PROBE = '''
    function locate(node, predicate) {
        if (predicate(node)) return node;
        for (const child of node.children ?? []) {
            const result = locate(child, predicate);
            if (result) return result;
        }
        return null;
    }
    IpcHandler {
        target: "monitorTest"
        function page(key: string): void { root.openPage(key); }
        function toggle(): void { root.locate(root.currentPageItem, n => n.enabled && n.text === Translation.tr("Hear my microphone")).clicked(); }
        function history(): string {
            const meter = root.locate(root.currentPageItem, n => n.bucketCount !== undefined && n.history !== undefined);
            return JSON.stringify(meter?.history ?? []);
        }
    }
'''


def run():
    original_source = output('pactl', 'get-default-source')
    original_sink = output('pactl', 'get-default-sink')
    modules = []
    settings = None
    with tempfile.TemporaryDirectory() as directory:
        tmp = Path(directory)
        shell = tmp / 'ii'
        shutil.copytree(Path(__file__).resolve().parents[2] / 'dots/.config/quickshell/ii', shell, symlinks=True)
        entry = shell / 'settings.qml'
        entry.write_text(entry.read_text().replace('    id: root\n', '    id: root\n' + PROBE, 1))
        try:
            for kind, args in [('module-null-sink', ['sink_name=velora_test_mic_bus']),
                               ('module-null-sink', ['sink_name=velora_test_speakers']),
                               ('module-remap-source', ['master=velora_test_mic_bus.monitor', 'source_name=velora_test_microphone'])]:
                modules.append(output('pactl', 'load-module', kind, *args))
            output('pactl', 'set-default-source', 'velora_test_microphone')
            output('pactl', 'set-default-sink', 'velora_test_speakers')
            for kind, device in [('source', 'velora_test_microphone'), ('sink', 'velora_test_mic_bus'), ('sink', 'velora_test_speakers')]:
                output('pactl', f'set-{kind}-volume', device, '100%')
                output('pactl', f'set-{kind}-mute', device, 'false')
            env = {**os.environ, 'XDG_CONFIG_HOME': str(tmp / 'config'), 'QS_SETTINGS_PAGE': 'sound'}
            settings = subprocess.Popen(['qs', '-p', str(entry)], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

            def ipc(method, *args):
                return output('qs', 'ipc', '--pid', str(settings.pid), 'call', 'monitorTest', method, *args)

            def connected():
                ports = output('pw-link', '-l')
                return ('velora_test_microphone:capture_FL\n  |-> velora_settings_monitor_capture:' in ports
                        and 'velora_test_speakers:playback_FL\n  |<- velora_settings_monitor_playback:' in ports)

            wait_for(connected)
            rate = 16000
            tone = tmp / 'tone.wav'
            with wave.open(str(tone), 'wb') as audio:
                audio.setparams((1, 2, rate, 0, 'NONE', 'not compressed'))
                audio.writeframes(array('h', (round(12000 * math.sin(2 * math.pi * 440 * i / rate)) for i in range(rate * 3))).tobytes())
            recording = tmp / 'heard.raw'
            with recording.open('wb') as raw:
                recorder = subprocess.Popen(['parec', '-d', 'velora_test_speakers.monitor', '--raw', '--format=s16le', '--channels=1', '--rate=16000', '--latency-msec=40'], stdout=raw)
                try:
                    subprocess.run(['paplay', '-d', 'velora_test_mic_bus', '--latency-msec=40', str(tone)], check=True, timeout=12)
                    time.sleep(.3)
                finally:
                    recorder.terminate()
                    recorder.wait(timeout=5)
            heard = array('h')
            heard.frombytes(recording.read_bytes())
            # Compare the known tone against neighbouring frequencies on a voiced block.
            start = next((i for i, sample in enumerate(heard) if abs(sample) > 100), None)
            if start is None:
                raise AssertionError(f'Silent speaker monitor, {len(heard)} samples. Defaults '
                                     f'{output("pactl", "get-default-source")} / {output("pactl", "get-default-sink")}\n'
                                     + output('pw-link', '-l'))
            block = heard[start:start + rate // 4]
            assert len(block) == rate // 4
            def magnitude(freq):
                return abs(sum(sample * complex(math.cos(2 * math.pi * freq * i / rate), math.sin(2 * math.pi * freq * i / rate)) for i, sample in enumerate(block)))
            assert magnitude(440) > 10 * max(magnitude(400), magnitude(480), 1)
            assert any(json.loads(ipc('history'))), 'level history vanished on silence'
            wait_for(lambda: not any(json.loads(ipc('history'))), seconds=12)
            ipc('toggle')
            wait_for(lambda: not connected())
            ipc('page', 'desktop')
            time.sleep(.4)
            ipc('page', 'sound')
            time.sleep(.6)
            assert not connected(), 'explicit Off was lost when reopening Sound'
            ipc('toggle')
            wait_for(connected)
            ipc('page', 'desktop')
            wait_for(lambda: not connected())
            ipc('page', 'sound')
            wait_for(connected)
            settings.terminate()
            settings.wait(timeout=8)
            wait_for(lambda: not connected())
            result = {'mic_tone_hz_at_speaker': 440, 'history_reaches_baseline': True, 'toggle_persisted': True,
                      'stopped_on_navigation': True, 'stopped_on_exit': True}
            (Path.home() / 'evidence/sound-monitor.json').write_text(json.dumps(result, indent=2) + '\n')
            print(json.dumps(result))
        finally:
            if settings is not None:
                settings.terminate()
                settings.wait(timeout=8)
            output('pactl', 'set-default-source', original_source)
            output('pactl', 'set-default-sink', original_sink)
            for module in reversed(modules):
                output('pactl', 'unload-module', module)


run()
