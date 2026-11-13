"""Small additive KDE configuration updates, using KConfig's own reader/writer."""
import os
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

PREVIEW_ACTION = 'servicemenu_velora-preview.desktop::preview'


def dolphin_toolbar(text):
    root = ET.fromstring(text)
    toolbar = root.find("ToolBar[@name='mainToolBar']")
    if toolbar is None:
        toolbar = ET.SubElement(root, 'ToolBar', {'name': 'mainToolBar'})
    for existing in toolbar.findall("Action[@name='create_dir']"):
        toolbar.remove(existing)
    menu = toolbar.find("Action[@name='hamburger_menu']")
    position = list(toolbar).index(menu) if menu is not None else len(toolbar)
    toolbar.insert(position, ET.Element('Action', {'name': 'create_dir'}))
    properties = root.find('ActionProperties')
    if properties is None:
        properties = ET.SubElement(root, 'ActionProperties', {'scheme': 'Default'})
    for name, shortcut in [('toggle_selection_mode', 'Shift+Space'), (PREVIEW_ACTION, 'Space')]:
        action = properties.find(f"Action[@name='{name}']")
        if action is None:
            action = ET.SubElement(properties, 'Action', {'name': name})
        action.set('shortcut', shortcut)
    return '<?xml version="1.0"?>\n<!DOCTYPE gui SYSTEM "kpartgui.dtd">\n' + ET.tostring(root, encoding='unicode') + '\n'


def configure(config):
    def read(file, group, key, default=''):
        return subprocess.check_output(['kreadconfig6', '--file', str(config / file), '--group', group,
                                        '--key', key, '--default', default], text=True).strip()

    def write(file, group, key, value):
        subprocess.run(['kwriteconfig6', '--file', str(config / file), '--group', group, '--key', key, value], check=True)

    def append(file, group, key, additions, default=''):
        values = [value for value in read(file, group, key, default).split(',') if value]
        write(file, group, key, ','.join(dict.fromkeys([*values, *additions])))

    # Git status badges are opt-in; updates must not enable them automatically.
    if read('dolphinrc', 'General', 'ShowSelectionToggle', '__unset__') == '__unset__':
        write('dolphinrc', 'General', 'ShowSelectionToggle', 'false')
    append('dolphinrc', 'PreviewSettings', 'Plugins',
           ['ffmpegthumbs', 'imagethumbnail', 'jpegthumbnail', 'gsthumbnail', 'svgthumbnail', 'directorythumbnail'],
           'directorythumbnail,imagethumbnail,jpegthumbnail')
    # Keep the user's existing size/network limits and preview visibility preferences.
    write('dolphinrc', 'Shortcuts', 'toggle_selection_mode', 'Shift+Space')
    write('dolphinrc', 'Shortcuts', PREVIEW_ACTION, 'Space')


if __name__ == '__main__':
    configure(Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')))
