#!/usr/bin/env bash
# Converts files from the Dolphin menu without opening the toolbox: quick.sh <target> files…
# Shows a notification when it's done, with a button that shows the result in the file manager.
backend="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/folis_toolbox.py"
target=$1
shift
[[ -n "$target" && $# -gt 0 ]] || exit 1

outputs=()
errors=()
while IFS= read -r line; do
    case $(jq -r '.event // empty' <<<"$line" 2>/dev/null) in
        done) outputs+=("$(jq -r '.output' <<<"$line")") ;;
        error) errors+=("$(jq -r '"\(.file // "" | split("/") | last): \(.message)"' <<<"$line")") ;;
    esac
done < <(/usr/bin/python3 -I "$backend" convert --to "$target" -- "$@" 2>&1)

if ((${#errors[@]} > 0)); then
    notify-send -a "Folis Toolbox" -i dialog-error "Couldn't convert to ${target^^}" "$(printf '%s\n' "${errors[@]}")"
fi
if ((${#outputs[@]} > 0)); then
    title="Converted to ${target^^}"
    ((${#outputs[@]} > 1)) && title="${#outputs[@]} files converted to ${target^^}"
    icon=document-save
    [[ "${outputs[0],,}" =~ \.(png|jpe?g)$ ]] && icon=${outputs[0]}
    action=$(notify-send -a "Folis Toolbox" -i "$icon" -A "show=Show" "$title" "${outputs[0]##*/}")
    if [[ "$action" == "show" ]]; then
        dbus-send --session --dest=org.freedesktop.FileManager1 --type=method_call /org/freedesktop/FileManager1 \
            org.freedesktop.FileManager1.ShowItems "array:string:$(printf 'file://%s,' "${outputs[@]}" | sed 's/,$//')" string:
    fi
fi
