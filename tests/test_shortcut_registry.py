"""Run the shipped Lua registry and modifier release handling with a small compositor adapter."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
LUA = shutil.which('lua')
PRELUDE = r'''
package.path = SOURCE .. '/dots/.config/hypr/?.lua;' .. package.path
local hooks, registered, dispatched = {}, {}, {}
local submap = 'global'
local function dsp(path)
    return setmetatable({}, { __index = function(_, key) return dsp(path .. '.' .. key) end,
        __call = function(_, value) return path .. ':' .. tostring(value) end })
end
hl = {
    dsp = dsp('dsp'),
    bind = function(key, callback, options) registered[#registered + 1] = { key = key, callback = callback, options = options or {}, submap = submap } end,
    unbind = function() end,
    dispatch = function(value) dispatched[#dispatched + 1] = value end,
    on = function(name, callback) hooks[name] = hooks[name] or {}; table.insert(hooks[name], callback) end,
    define_submap = function(name, callback) local previous = submap; submap = name; callback(); submap = previous end,
    get_current_submap = function() return submap end,
    get_config = function() return '' end,
    timer = function() end,
}
package.preload['hyprland.helpers'] = function() return {
    bind = function(mods, key, callback, options) hl.bind((mods ~= '' and mods .. '+' or '') .. key, callback, options) end,
    unbind = hl.unbind,
    exec = function(cmd) return 'exec:' .. cmd end,
} end
package.preload['hyprland.window_mode'] = function() return {current = function() return 'tiling' end} end
package.preload['custom.keybinds'] = function() return {setup = function() end} end
package.preload['custom.keybind_overrides'] = function() return OVERRIDES end
local keymap = require('hyprland.keymap')
require('hyprland.keybinds')
local function input(code, pressed, release_key)
    for _, callback in ipairs(hooks['input.keyboard.key']) do callback(code, 0, pressed and 1 or 0) end
    if release_key then
        for _, bind in ipairs(registered) do
            if bind.submap == submap and bind.key == release_key and bind.options.release and type(bind.callback) == 'function' then bind.callback() end
        end
    end
end
'''

@unittest.skipUnless(LUA, 'needs Lua')
class RegistryTests(unittest.TestCase):
    def run_lua(self, probe='', overrides='{}'):
        with tempfile.TemporaryDirectory(prefix='velora-keymap-') as directory:
            source = 'local SOURCE = ' + json.dumps(str(ROOT)) + '\nlocal OVERRIDES = ' + overrides + '\n' + PRELUDE + probe
            result = subprocess.run([LUA, '-'], input=source, text=True, capture_output=True,
                                    env={**os.environ, 'XDG_RUNTIME_DIR': directory})
            self.assertEqual(result.returncode, 0, result.stderr)
            return json.loads((Path(directory) / 'folis-keybinds.json').read_text())

    def test_every_shown_action_is_remappable_and_concrete(self):
        manifest = self.run_lua()
        self.assertGreater(len(manifest['binds']), 70)
        for bind in manifest['binds']:
            self.assertTrue(bind['id'] and bind['remappable'], bind)
            self.assertNotIn(bind['key'], ['Arrows', '1-0', 'Left/Right', 'Scroll'])
        for key in ['shell.search', 'keyboard.layout', 'window.drag', 'workspace.go_10', 'session.passthrough']:
            self.assertIn(key, {b['id'] for b in manifest['binds']})

    def test_remap_disable_and_build_defaults(self):
        defaults = {b['id']: b for b in self.run_lua()['binds']}
        edited = {b['id']: b for b in self.run_lua(overrides='{remap = {["shell.search"] = {mods="Ctrl",key="Space"}, ["keyboard.layout"] = false, ["workspace.go_1"] = {mods="Super",key="F5"}}}')['binds']}
        self.assertEqual(edited['shell.search']['key'], 'Space')
        self.assertTrue(edited['keyboard.layout']['disabled'])
        self.assertEqual(edited['workspace.go_1']['key'], 'F5')
        for key in edited:
            self.assertEqual(edited[key]['default_key'], defaults[key]['key'])
            self.assertEqual(edited[key]['default_mods'], defaults[key]['mods'])
        self.assertEqual(self.run_lua()['binds'], list(defaults.values()))

    def test_window_switcher_commits_the_remapped_modifier(self):
        self.run_lua(r'''
input(37, true)
for _, bind in ipairs(registered) do
    if bind.options.description == 'Switch between windows' then
        assert(bind.key == 'Ctrl+Tab'); bind.callback()
    end
end
input(37, false, 'Control_L')
assert(#dispatched == 2 and dispatched[2]:find('windowSwitcherCommit', 1, true), 'remapped modifier did not commit')
''', overrides='{remap = {["window.switch_next"] = {mods="Ctrl",key="Tab"}}}')

    def test_reverse_switcher_waits_for_alt_not_shift(self):
        self.run_lua(r'''
input(64, true); input(50, true)
for _, bind in ipairs(registered) do
    if bind.options.description == 'Switch between windows, backwards' then bind.callback() end
end
input(50, false, 'Shift_L')
assert(#dispatched == 1, 'releasing Shift committed while Alt was still held')
input(64, false, 'Alt_L')
assert(#dispatched == 2 and dispatched[2]:find('windowSwitcherCommit', 1, true), 'Alt did not commit')
''')

    def test_modifier_taps_cancel_after_other_keys_and_submaps(self):
        self.run_lua(r'''
input(133, true); input(133, false, 'Super_L')
assert(#dispatched == 1 and dispatched[1]:find('search toggle', 1, true), 'clean Super')
input(133, true); input(38, true); input(38, false); input(133, false, 'Super_L')
assert(#dispatched == 1, 'Super+A also opened search')
input(64, true); input(50, true); input(64, false, 'Alt_L'); input(50, false, 'Shift_L')
assert(#dispatched == 2 and dispatched[2]:find('switchxkblayout', 1, true), 'clean Alt+Shift once')
input(50, true); input(64, true); input(50, false, 'Shift_L'); input(64, false, 'Alt_L')
assert(#dispatched == 3, 'reverse press/release order')
input(64, true); input(50, true); input(53, true); input(53, false); input(50, false, 'Shift_L'); input(64, false, 'Alt_L')
assert(#dispatched == 3, 'Alt+Shift+X switched layouts')
input(133, true); keymap.interrupt_modifiers(); input(133, false, 'Super_L')
assert(#dispatched == 3, 'mouse shortcut opened search')
input(133, true)
for _, cb in ipairs(hooks['keybinds.submap']) do cb() end
input(133, false, 'Super_L')
assert(#dispatched == 3, 'capture transition fired search')
''')

if __name__ == '__main__': unittest.main()
