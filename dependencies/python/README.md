# Shell Python environment

The Velora installer creates a Python 3.12 environment at
`$XDG_STATE_HOME/quickshell/.venv` and synchronizes `requirements.txt` with uv.
This preserves the existing shell's `ILLOGICAL_IMPULSE_VIRTUAL_ENV` integration.

Edit `requirements.in` to change dependencies, then compile and review the lock:

```bash
uv pip compile --python-version 3.12 requirements.in -o requirements.txt
```

From the repository root, run `./velora deps` to reconcile installed packages
and synchronize this environment. Run `./velora doctor` for diagnostics.

See [dependency and update documentation](../../docs/updates.md).
