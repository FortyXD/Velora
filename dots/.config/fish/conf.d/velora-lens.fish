# No command history or keystrokes are sent to Lens.
function __velora_lens_directory --on-variable PWD
    status is-interactive; or return
    test -S "$XDG_RUNTIME_DIR/velora-lens/search.sock"; or return
    test -x "$HOME/.local/bin/velora-searchd"; or return
    "$HOME/.local/bin/velora-searchd" record fish </dev/null >/dev/null 2>&1 &
    disown
end
