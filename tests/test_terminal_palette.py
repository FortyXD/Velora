import importlib.util
import json
import os
from pathlib import Path
import pty
import re
import select
import shutil
import signal
import subprocess
import tempfile
import time
import unittest
from unittest.mock import Mock, patch


from native_helper import binary

DOTS = Path(__file__).resolve().parents[1] / "dots/.config"
SCRIPT = Path(__file__).parent / "fixtures/legacy/terminal_palette.py"
spec = importlib.util.spec_from_file_location("terminal_palette", SCRIPT)
palette = importlib.util.module_from_spec(spec)
spec.loader.exec_module(palette)


class TerminalPaletteTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="velora terminal ")
        self.addCleanup(temp.cleanup)
        self.home = Path(temp.name)
        self.state = self.home / "custom state"
        self.generated = self.state / "quickshell/user/generated"
        self.generated.mkdir(parents=True)
        self.config = self.home / "config.json"
        self.conf = self.generated / "terminal/kitty-theme.conf"
        self.osc = self.conf.with_name("sequences.txt")
        self.colors = {f"term{i}": f"#{i:02x}2233" for i in range(16)}
        self.colors.update(primary="#ffee99", secondary="#ffaaaa", tertiary="#557799",
                           onPrimary="#332211", onSecondary="#221111", onTertiary="#eeeeee")
        self.wallpaper()
        self.refresh = Mock()

    def wallpaper(self):
        (self.generated / "material_colors.scss").write_text(
            "".join(f"${name}: {color};\n" for name, color in self.colors.items()))

    def apply(self, overrides=None, **theming):
        self.config.write_text(json.dumps({"appearance": {"wallpaperTheming": theming,
                                                          "palette": {"roleOverrides": overrides or {}}}}))
        palette.apply(self.generated, self.config, self.refresh)
        return dict(line.split() for line in self.conf.read_text().splitlines()) if self.conf.exists() else {}

    def test_native_palette_follows_the_shell_config_before_and_after_relink(self):
        config = self.home / 'config'
        env = {**os.environ, 'HOME': str(self.home), 'XDG_STATE_HOME': str(self.state),
               'XDG_CONFIG_HOME': str(config), 'WAYLAND_DISPLAY': '', 'DISPLAY': ''}
        for name, color in [('illogical-impulse', '#147ade'), ('velora', '#aa3377')]:
            directory = config / name
            directory.mkdir(parents=True)
            (directory / 'config.json').write_text(json.dumps({'appearance': {'palette': {'roleOverrides': {'primary': color}}}}))
            subprocess.run([binary(), 'terminal-apply'], env=env, check=True)
            self.assertIn(f'cursor {color}', self.conf.read_text().splitlines())

    def test_native_palette_matches_existing_files_and_skips_identical_writes(self):
        config = self.home / 'config/velora/config.json'
        config.parent.mkdir(parents=True)
        env = {**os.environ, 'XDG_STATE_HOME':str(self.state),'XDG_CONFIG_HOME':str(self.home/'config'),
               'WAYLAND_DISPLAY':'','DISPLAY':''}
        for overrides, options in [({'primary':'#994433','on_surface':'#111100'},{}),
                                   ({'surface_container':'#fcfcfc'}, {'terminalGenerationProps':{'forceDarkMode':True}}),
                                   ({},{'enableTerminal':False})]:
            self.apply(overrides, **options)
            config.write_bytes(self.config.read_bytes())
            def content(path): return path.read_bytes() if path.is_file() else b''
            expected = content(self.conf), content(self.osc)
            self.conf.unlink(missing_ok=True); self.osc.unlink(missing_ok=True)
            subprocess.run([binary(),'terminal-apply'],env=env,check=True)
            self.assertEqual((content(self.conf),content(self.osc)),expected)
            if self.conf.exists():
                stamp = self.conf.stat().st_mtime_ns
                subprocess.run([binary(),'terminal-apply'],env=env,check=True)
                self.assertEqual(stamp,self.conf.stat().st_mtime_ns)

    def test_all_roles_reach_kitty_and_osc_and_reset_to_new_wallpaper(self):
        overrides = dict(primary="#121212", secondary="#334499", tertiary="#B0FFEE",
                         surface_container="#303030", on_surface="#dddddd")
        colors = self.apply(overrides)
        for option, value in {"background": "#303030", "foreground": "#dddddd", "cursor": "#121212",
                              "active_tab_foreground": "#ffffff", "selection_background": "#334499",
                              "color253": "#334499", "color251": "#b0ffee", "url_color": "#b0ffee"}.items():
            self.assertEqual(colors[option], value)
        seq = self.osc.read_bytes()
        self.assertIn(b"\x1b]11;#303030\x1b\\", seq)
        self.assertIn(b"\x1b]4;253;#334499\x1b\\", seq)
        self.assertEqual(re.sub(rb"\x1b\](?:4;\d+|10|11|12|17|19);#[0-9a-f]{6}\x1b\\", b"", seq), b"")
        self.apply(overrides)
        self.refresh.assert_called_once()
        self.colors.update(primary="#abcd12", term0="#111122", term7="#bbbbcc")
        self.wallpaper()
        self.assertEqual(self.apply(overrides)["cursor"], "#121212")
        automatic = self.apply()
        self.assertEqual([automatic[k] for k in ("cursor", "background", "foreground", "color1")],
                         ["#abcd12", "#111122", "#bbbbcc", "#012233"])

    @unittest.skipUnless(all(shutil.which(name) for name in ("btop", "tmux", "matugen")), "needs terminal apps and Matugen")
    def test_open_btop_and_tmux_follow_two_wallpapers(self):
        from PIL import Image
        config = self.home / "configuration files"
        config.mkdir()
        (self.home / ".config").symlink_to(config)
        (config / "matugen").symlink_to(DOTS / "matugen")
        (config / "tmux").symlink_to(DOTS / "tmux")
        (config / "btop").mkdir()
        (config / "btop/btop.conf").write_text('color_theme = "Velora"\ntruecolor = true\n')
        settings = config / "velora/config.json"
        settings.parent.mkdir()
        env = dict(os.environ, HOME=str(self.home), XDG_CONFIG_HOME=str(config), XDG_STATE_HOME=str(self.state),
                   WAYLAND_DISPLAY="", DISPLAY="", TERM="xterm-256color", COLORTERM="truecolor", LC_ALL="C.UTF-8")
        env.pop("TMUX", None)
        sock = self.home / "custom socket"
        helper = binary()

        def run(*args):
            return subprocess.check_output(args, env=env, text=True, timeout=15).strip()

        def wallpaper(rgb, mode):
            path = self.home / f"{mode}.png"
            Image.new("RGB", (64, 64), rgb).save(path)
            staged = run(helper, "theme", "stage", "--cache-root", self.home / "cache", "--image", path,
                         "--matugen-config", config / "matugen/config.toml", "--mode", mode,
                         "--terminal-scheme", DOTS / "quickshell/ii/scripts/colors/terminal/scheme-base.json",
                         "--scss-target", self.generated / "material_colors.scss")
            run(helper, "theme", "commit", staged)
            run(helper, "terminal-apply")
            return re.search(r'^\$primary: (#\w{6});', (self.generated / "material_colors.scss").read_text(), re.M)[1].lower()

        def check_live_color(color):
            self.assertEqual(run("tmux", "-S", sock, "show-options", "-gv", "pane-active-border-style").lower(), "fg=" + color)
            escape = "38;2;" + ";".join(str(int(color[i:i+2], 16)) for i in (1, 3, 5))
            for _ in range(100):
                screen = run("tmux", "-S", sock, "capture-pane", "-ep", "-t", "palette")
                if escape in screen:
                    return
                time.sleep(.05)
            self.fail(f"btop did not redraw its boxes with {color}")

        first = wallpaper("#245cc5", "dark")
        run("tmux", "-S", sock, "-f", DOTS.parent.parent / "home/.tmux.conf", "new-session",
            "-d", "-x", "150", "-y", "50", "-s", "palette", "btop")
        self.addCleanup(subprocess.run, ["tmux", "-S", sock, "kill-server"], env=env, stderr=subprocess.DEVNULL)
        check_live_color(first)
        pid = run("tmux", "-S", sock, "display-message", "-p", "#{pane_pid}")
        second = wallpaper("#e46a22", "light")
        self.assertNotEqual(first, second)
        check_live_color(second)
        self.assertEqual(run("tmux", "-S", sock, "display-message", "-p", "#{pane_pid}"), pid)
        settings.write_text('{"appearance":{"wallpaperTheming":{"enableTerminal":false}}}')
        run(helper, "terminal-apply")
        self.assertEqual((config / "btop/themes/Velora.theme").read_bytes(),
                         (config / "matugen/templates/btop/Velora.theme").read_bytes())
        self.assertEqual(run("tmux", "-S", sock, "show-options", "-gv", "pane-active-border-style"), "fg=cyan")

    def test_opt_out_first_setup_and_invalid_overrides(self):
        self.apply()
        self.assertEqual(self.apply(enableTerminal=False), {})
        self.assertFalse(self.osc.exists())
        self.assertIn(b"\x1b]111\x1b\\", self.refresh.call_args.args[0])
        self.assertEqual(self.apply({"primary": "#ff00ff\ninclude /tmp/example", "secondary": 42})["cursor"], "#ffee99")
        (self.generated / "material_colors.scss").unlink()
        self.assertEqual(self.apply({"surface_container": "#112244"})["background"], "#112244")
        self.assertEqual(self.apply(), {})
        self.wallpaper()
        dark = self.apply({"surface_container": "#fafafa"}, terminalGenerationProps={"forceDarkMode": True})
        self.assertEqual(dark["background"], self.colors["term0"])

    def test_incomplete_inputs_keep_the_last_good_theme(self):
        self.apply({"primary": "#AB1234"})
        previous = self.conf.read_bytes(), self.osc.read_bytes()
        self.config.write_text("")
        with self.assertRaises(ValueError):
            palette.apply(self.generated, self.config, self.refresh)
        (self.generated / "material_colors.scss").write_text("$term0: #224466;\n")
        with self.assertRaises(ValueError):
            self.apply()
        self.assertEqual((self.conf.read_bytes(), self.osc.read_bytes()), previous)
        self.refresh.assert_called_once()

    def test_live_updates_only_reach_open_emulator_windows(self):
        masters = []
        processes = ["11 1 1 ? kitty", "12 1 1 ? foot", "13 1 1 ? unrelated", "14 1 1 ? kitty"]
        for parent in (11, 12, 13):
            master, slave = pty.openpty()
            self.addCleanup(os.close, slave)
            self.addCleanup(os.close, master)
            masters.append(master)
            tty = os.ttyname(slave).removeprefix("/dev/")
            child = parent + 10
            processes.append(f"{child} {parent} {child} {tty} zsh")
        with patch.dict(os.environ, WAYLAND_DISPLAY="test"), patch.object(os, "kill") as kill, \
                patch.object(subprocess, "check_output", return_value="\n".join(processes)):
            palette.refresh_terminals(b"updated", b"reset")
        kill.assert_called_once_with(11, signal.SIGUSR1)
        self.assertEqual(select.select(masters, [], [], 0.5)[0], masters[:2])
        self.assertEqual(os.read(masters[0], 16), b"reset")
        self.assertEqual(os.read(masters[1], 16), b"updated")

    @unittest.skipUnless(shutil.which("kitty"), "needs Kitty's config parser")
    def test_kitty_loads_fallback_and_selected_colors_from_the_xdg_state_directory(self):
        check = ("from kitty.config import load_config; bad=[]; "
                 f"o=load_config({str(DOTS / 'kitty/kitty.conf')!r}, accumulate_bad_lines=bad); "
                 "assert not bad, bad; assert o.font_size == 11; print(o.background.as_sharp, o.foreground.as_sharp, "
                 "getattr(o.color253, 'as_sharp', 'default'))")
        env = {**os.environ, "HOME": str(self.home), "XDG_STATE_HOME": str(self.state)}

        def load():
            return subprocess.check_output(["kitty", "+runpy", check], env=env, text=True).strip().split()

        fallback = load()
        self.assertEqual(fallback[0], "#1e1e2e")
        self.apply({"surface_container": "#513456", "on_surface": "#fcffff", "secondary": "#456789"})
        with self.conf.open("a") as output:
            output.write("font_size 31\n")
        self.assertEqual(load(), ["#513456", "#fcffff", "#456789"])
        self.apply(enableTerminal=False)
        self.assertEqual(load(), fallback)
