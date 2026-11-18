# Kitty reads its native theme before painting the first frame.
if [[ -o interactive && -t 1 && -z $KITTY_WINDOW_ID && $TERM != (linux|dumb|xterm-kitty) ]]; then
    typeset _velora_sequences="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/user/generated/terminal/sequences.txt"
    [[ -r $_velora_sequences ]] && cat -- "$_velora_sequences"
    unset _velora_sequences
fi
