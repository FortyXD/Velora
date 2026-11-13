"""Geometry checks for real controls; optional native-font pixel checks at real DPRs.

Only theme/service imports are isolated. Button/GroupButton, layouts, font
rendering and animation code are the production components, not substitutes.
"""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

PROJECT = Path(__file__).resolve().parents[1]
WIDGETS = PROJECT / 'dots/.config/quickshell/ii/modules/common/widgets'
QML_TEST = next((str(p) for p in (
    Path('/usr/lib/qt6/bin/qmltestrunner'), Path('/usr/lib64/qt6/bin/qmltestrunner')
) if p.is_file()), shutil.which('qmltestrunner6'))
COMPONENTS = (
    'MaterialSymbol', 'StyledText', 'RippleButton', 'GroupButton', 'ToolbarButton',
    'RippleButtonWithIcon', 'SelectionGroupButton', 'OptionalMaterialSymbol',
    'IconAndTextToolbarButton', 'ToolbarTabButton', 'NavigationRailButton', 'NavigationRailTabArray',
    'FloatingActionButton', 'Revealer', 'PointingHandInteraction',
)


def isolated_components(root):
    sources = []
    for name in COMPONENTS:
        source = (WIDGETS / f'{name}.qml').read_text()
        source = re.sub(r'^import (qs\..*|Quickshell.*)\n', '', source, flags=re.M)
        source = 'import "theme"\n' + source
        (root / f'{name}.qml').write_text(source)
        sources.append(source)
    theme = root / 'theme'
    theme.mkdir()
    (theme / 'qmldir').write_text('singleton Appearance 1.0 Appearance.qml\nsingleton ColorUtils 1.0 ColorUtils.qml\n')
    combined = '\n'.join(sources)
    palettes = {name: {key: '#ffffff' for key in re.findall(
        r'Appearance\??\.' + name + r'\??\.(\w+)', combined)} for name in ('colors', 'm3colors')}
    (theme / 'Appearance.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
    property Component numberAnimation: NumberAnimation { duration: 0 }
    property Component colorAnimation: ColorAnimation { duration: 0 }
    property var animation: ({elementMoveFast: move, elementMove: move,
        elementMoveEnter: ({numberAnimation: entryAnimation}), clickBounce: move})
    property var move: ({duration: 0, type: Easing.Linear,
        bezierCurve: [0,0,1,1,1,1], numberAnimation, colorAnimation})
    property var font: ({family: {main: "sans-serif", numbers: "sans-serif",
        iconNerd: "monospace", iconMaterial: "Material Symbols Rounded"},
        pixelSize: {small: 16, large: 22, larger: 24}, variableAxes: {main: {}}})
    property Component entryAnimation: NumberAnimation { duration: 160 }
    property var animationCurves: ({standardDecel: [0,0,1,1,1,1],
        expressiveFastSpatialDuration: 100, expressiveFastSpatial: [0,0,1,1,1,1]})
    property var rounding: ({small: 8, verysmall: 4, full: 999})
    property var colors: ''' + json.dumps(palettes['colors']) + '''
    property var m3colors: ''' + json.dumps(palettes['m3colors']) + '\n}\n')
    color_utils = (WIDGETS.parent / 'functions/ColorUtils.qml').read_text()
    (theme / 'ColorUtils.qml').write_text(color_utils.replace('import Quickshell', 'import QtQuick').replace('Singleton {', 'QtObject {', 1))


def environment(**extra):
    return {**os.environ, 'QT_QPA_PLATFORM': 'offscreen', 'QT_QUICK_BACKEND': 'software',
            'QT_QPA_PLATFORMTHEME': 'generic', 'QT_SCALE_FACTOR': '1',
            'QT_LOGGING_TO_CONSOLE': '1', 'QT_LOGGING_RULES': '*.warning=true;*.critical=true', **extra}


class UiAlignmentTests(unittest.TestCase):
    @unittest.skipUnless(QML_TEST, 'Qt Quick Test is not installed')
    def test_control_geometry(self):
        with tempfile.TemporaryDirectory(prefix='velora-alignment-') as directory:
            root = Path(directory)
            isolated_components(root)
            shutil.copy2(PROJECT / 'tests/qml/tst_uialignment.qml', root)
            for style in ('Basic', 'Fusion'):
                with self.subTest(style=style):
                    result = subprocess.run([QML_TEST, '-input', str(root), '-o', '-,txt'],
                        env=environment(QT_QUICK_CONTROLS_STYLE=style), capture_output=True,
                        text=True, timeout=30)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_native_icon_pixels_at_display_scales(self):
        try:
            from PIL import Image
        except ImportError:
            self.skipTest('Pillow is not installed')
        if not all(shutil.which(tool) for tool in ('g++', 'pkg-config', 'fc-match')):
            self.skipTest('Qt development tools/fontconfig are not installed')
        font = subprocess.check_output(['fc-match', '-f', '%{family}', 'Material Symbols Rounded'], text=True)
        if 'Material Symbols Rounded' not in font:
            self.skipTest('Material Symbols Rounded is not installed')
        flags = subprocess.run(['pkg-config', '--cflags', '--libs', 'Qt6Quick', 'Qt6Gui'],
                               capture_output=True, text=True, timeout=10)
        if flags.returncode:
            self.skipTest('Qt 6 Quick development libraries are not installed')
        with tempfile.TemporaryDirectory(prefix='velora-icon-pixels-') as directory:
            root = Path(directory)
            isolated_components(root)
            renderer = root / 'render'
            build = subprocess.run(['g++', '-fPIC', str(PROJECT / 'tests/qml/alignment_render.cpp'),
                '-o', str(renderer), *flags.stdout.split()], capture_output=True, text=True, timeout=60)
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            sizes = (16, 20, 22, 24, 28, 32)
            icons = ('stop_circle', 'add', 'close', 'settings')
            children = []
            cases = [(icon, fill) for fill in (0, 1) for icon in icons]
            for row, size in enumerate(sizes):
                for column, (icon, fill) in enumerate(cases):
                    children.append(f'''Item {{ x: {column * 100}; y: {row * 100}; width:100; height:100
                        MaterialSymbol {{ anchors.centerIn:parent; text:"{icon}";
                            iconSize:{size}; fill:{fill}; color:"white" }} }}''')
            qml = root / 'render.qml'
            qml.write_text('import QtQuick\nRectangle { width:800; height:600; color:"black"\n' + '\n'.join(children) + '\n}')
            for scale in (1, 1.25, 1.666667, 2):
                with self.subTest(scale=scale):
                    image_path = root / 'icons.png'
                    result = subprocess.run([str(renderer), str(qml), str(image_path)],
                        env=environment(QT_SCALE_FACTOR=str(scale)), capture_output=True, text=True, timeout=10)
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    image = Image.open(image_path).convert('RGB')
                    for row, size in enumerate(sizes):
                        for column, (icon, fill) in enumerate(cases):
                            x, y = column * 100 * scale, row * 100 * scale
                            cell = image.crop((round(x), round(y), round(x + 100 * scale), round(y + 100 * scale)))
                            bounds = cell.point(lambda value: 255 if value > 32 else 0).getbbox()
                            self.assertIsNotNone(bounds, (scale, size, icon, fill))
                            left, top, right, bottom = bounds
                            # One physical pixel covers native-rasterizer baseline and
                            # fractional surface-size quantization, not arbitrary nudges.
                            self.assertLessEqual(abs((left + right - cell.width) / 2), 1, (scale, size, icon, fill, bounds))
                            self.assertLessEqual(abs((top + bottom - cell.height) / 2), 1, (scale, size, icon, fill, bounds))


if __name__ == '__main__':
    unittest.main()
