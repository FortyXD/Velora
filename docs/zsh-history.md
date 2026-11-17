# Zsh history

Velora's `home/.zshrc` stores up to 100,000 commands in `~/.zsh_history`
and keeps up to 100,000 in memory. Extended history includes timestamps and
command durations. Commands are appended during interactive use, and other
kitty, tmux, or TTY shells import them at command boundaries; a restart is not
required. Consecutive duplicates are omitted, redundant whitespace is reduced,
and duplicates expire before unique entries when history fills up.

Shared history changes Up-arrow/history navigation across tabs: commands from
another shell can appear among your current shell's commands, and imports are
not an instantaneous push to an idle prompt. It is not a transactional audit log
or a guarantee against data loss. History expansion (for example `!!`) is
returned to the editing buffer for review before execution.

## Privacy

Start a command with a space to exclude it from saved history. Zsh may retain
that line temporarily until the next command; this is a convenience, not a
security boundary. Avoid putting passwords or tokens on command lines: terminal
scrollback, process arguments, application logs, or other tools can still expose
them. Ordinary commands are persisted and shared across shells using the same
history file; do not enter secrets assuming that a tab has private history.

## Isolated regression tests

```sh
python3 -m unittest discover -s tests -p 'test_zsh_history.py' -v
```

Requires Python 3 and zsh (otherwise the real-shell tests are explicitly
skipped). Tests use temporary HOME/history files and only the history block,
not the rest of `.zshrc`, so conda, zoxide, plugins, and desktop services are not
needed. No real user history is read or modified. Pipes synchronize live shells
without relying on PTY prompts. `zsh -d` disables global startup files except
zsh's unavoidable system `zshenv`; no user startup files are loaded from the
host. The tests verify history settings, persistence across two processes,
live sharing, extended records, leading-space exclusion, duplicate suppression,
and whitespace reduction. Interactive line-editor expansion and retention at
100,000 entries are not simulated.
