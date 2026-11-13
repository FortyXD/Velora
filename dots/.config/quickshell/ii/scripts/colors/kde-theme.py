#!/usr/bin/env python3
"""Apply Velora's already generated palette to KDE, without a Plasma/KWin daemon."""
import configparser
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


def palette(colors):
    def color(key, fallback=None):
        value = colors.get(key, colors.get(fallback))
        if not isinstance(value, str) or not re.fullmatch(r'#[0-9a-fA-F]{6}', value):
            raise ValueError(f'Invalid palette color: {key}')
        return value

    groups = {}
    for name, background, foreground in [
        ('Window', 'surface_container_low', 'on_surface'),
        ('View', 'surface_container_lowest', 'on_surface'),
        ('Button', 'surface_container_high', 'on_surface'),
        ('Header', 'surface_container', 'on_surface'),
        ('Complementary', 'surface_container', 'on_surface'),
        ('Selection', 'primary', 'on_primary'),
        ('Tooltip', 'inverse_surface', 'inverse_on_surface'),
    ]:
        groups['Colors:' + name] = {
            'BackgroundNormal': color(background, 'background'),
            'BackgroundAlternate': color(background if name in ('Selection', 'Tooltip') else 'surface_container', 'background'),
            'ForegroundNormal': color(foreground),
            'ForegroundActive': color(foreground if name in ('Selection', 'Tooltip') else 'primary'),
            'ForegroundInactive': color(foreground if name in ('Selection', 'Tooltip') else 'on_surface_variant'),
            'ForegroundLink': color('primary'), 'ForegroundVisited': color('tertiary'),
            'ForegroundNegative': color('error'), 'ForegroundNeutral': color('secondary'),
            'ForegroundPositive': color('tertiary'),
            'DecorationFocus': color('primary'), 'DecorationHover': color('primary'),
        }
    groups['ColorEffects:Inactive'] = {'Enable': 'false'}
    groups['General'] = {'Name': 'Velora', 'ColorScheme': 'Velora'}
    return groups


def main():
    config = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config'))
    state = Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state'))
    data = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share'))
    settings = config / 'illogical-impulse/config.json'
    if settings.exists() and not json.loads(settings.read_text()).get('appearance', {}).get('wallpaperTheming', {}).get('enableQtApps', True):
        return
    groups = palette(json.loads((state / 'quickshell/user/generated/colors.json').read_text()))
    scheme = configparser.ConfigParser(interpolation=None)
    scheme.optionxform = str
    scheme.read_dict(groups)
    destination = data / 'color-schemes/Velora.colors'
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode='w', dir=destination.parent, delete=False) as output:
        temporary = Path(output.name)
        try:
            scheme.write(output, space_around_delimiters=False)
            output.flush()
            os.replace(temporary, destination)
        finally:
            temporary.unlink(missing_ok=True)
    # KConfig merges individual keys, retaining fonts, shortcuts, icons and unrelated settings.
    # Applying the same scheme again must also update its colors, which some Plasma CLI
    # versions skip when the scheme's name has not changed.
    for group, values in groups.items():
        for key, value in values.items():
            if group == 'General' and key == 'Name':
                continue
            subprocess.run(['kwriteconfig6', '--file', str(config / 'kdeglobals'), '--group', group,
                            '--key', key, value], check=True)
    subprocess.run(['dbus-send', '--session', '--type=signal', '/KGlobalSettings',
                    'org.kde.KGlobalSettings.notifyChange', 'int32:0', 'int32:0'], check=True)


if __name__ == '__main__':
    main()
