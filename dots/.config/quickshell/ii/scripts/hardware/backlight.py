#!/usr/bin/env python3
"""Find the backlight belonging to a DRM output, including on hybrid laptops."""

import json
from pathlib import Path
import sys


def backlight_for_output(output, backlights=Path('/sys/class/backlight'), drm=Path('/sys/class/drm')):
    connectors = [p for p in drm.glob('card*-*') if (p / 'status').exists()]
    active = [p for p in connectors if p.name.split('-', 1)[1] == output
              and (p / 'status').read_text().strip() == 'connected']
    internal = output.startswith(('eDP-', 'LVDS-', 'DSI-'))
    candidates = []
    for device in backlights.iterdir():
        path = device.resolve()
        owner = (device / 'device').resolve()
        # Native backlights can sit below their connector; NVIDIA's can sit
        # directly below the GPU even when that GPU has no connected panel.
        direct = [p for p in connectors if p.resolve() in path.parents]
        if direct:
            if not any(p in active for p in direct):
                continue
            rank = 0
        else:
            gpu_connectors = [p for p in connectors if (p.resolve().parent / 'device').resolve() == owner]
            if gpu_connectors:
                if not internal or not any(p in active for p in gpu_connectors):
                    continue
                rank = 1
            elif internal and active:
                # ACPI/vendor backlights need not have a DRM parent.
                rank = 2
            else:
                continue
        kind = (device / 'type').read_text().strip()
        candidates.append((rank, {'firmware': 0, 'platform': 1, 'raw': 2}.get(kind, 3), device.name, device))
    if not candidates:
        raise ValueError(f'No backlight for {output}')
    device = min(candidates)[-1]
    current = int((device / 'brightness').read_text())
    maximum = int((device / 'max_brightness').read_text())
    if maximum <= 0 or not 0 <= current <= maximum:
        raise ValueError(f'Invalid brightness reported by {device.name}')
    return {'device': device.name, 'current': current, 'max': maximum}


if __name__ == '__main__':
    try:
        print(json.dumps(backlight_for_output(sys.argv[1])))
    except (OSError, ValueError, IndexError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
