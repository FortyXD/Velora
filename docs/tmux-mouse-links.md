# Optional tmux mouse links

This is an **opt-in convenience**, not a required Velora feature. It leaves the
bundled mouse bindings unchanged until explicitly sourced. A normal left click
or Ctrl+left click opens an OSC 8 HTTP(S) hyperlink or a visible HTTP(S) URL at
the clicked position. In copy mode this needs tmux 3.5 or newer: older
versions handle copy-mode mouse events internally and keep their own selection.
Other normal clicks retain pane selection / forwarding; dragging and clipboard
bindings are not changed.

## Enable

With a standard installation, add this to the end of your personal tmux config:

```tmux
source-file ~/.config/tmux/mouse-links.conf
```

Use your actual tmux configuration directory if `XDG_CONFIG_HOME` is customized.
Reload that config with `tmux source-file /path/to/your/tmux.conf`. No terminal,
shell or desktop restart is required. Removing the source line and restarting
tmux restores its default bindings; alternatively source your original mouse
bindings in the running server. Do not kill a tmux server with valuable sessions.

Requires tmux with `mouse_hyperlink` / `q:` format support (tested on 3.4 and 3.8),
Python 3 and `xdg-open`. The file also teaches tmux that Kitty supports OSC 8,
which applications query before emitting hyperlinks; restart the terminal
application afterwards so it re-reads the capability.

Already-rendered plain text cannot recover a hidden hyperlink target. A visible
URL fallback only opens a complete URL on the clicked physical line; it does not
reconstruct arbitrary wrapped URLs or guess links on nearby lines. Intentional
URL punctuation can be ambiguous in plain text; OSC 8 targets are preserved.

## Safety and checks

The URL is shell-quoted by tmux, validated as HTTP(S), and passed to `xdg-open`
as one argument. No URL is evaluated as shell code, no shared tmux buffer or
clipboard is used, and only one opener is launched per click. A successful
opener launch does not prove the browser loaded the remote page.

Tests use a private tmux socket, pseudo terminal and fake `xdg-open`, never
injecting clicks into an existing client or launching a real browser:

```sh
python -m unittest discover -s tests -p test_tmux_mouse_links.py -v
```
