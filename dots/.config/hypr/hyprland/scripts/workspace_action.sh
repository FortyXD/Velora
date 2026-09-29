#!/usr/bin/env bash
dispatcher="$1"
shift ## The target is now in $1, not $2

cursor_monitor=""
curr_workspace=""

get_cursor_workspace() {
  local cursor_json monitors_json cursor_x cursor_y monitor_state

  cursor_json="$(hyprctl cursorpos -j)" || return 1
  monitors_json="$(hyprctl monitors -j)" || return 1
  cursor_x="$(jq -r '.x' <<< "${cursor_json}")"
  cursor_y="$(jq -r '.y' <<< "${cursor_json}")"

  monitor_state="$(jq -r --argjson cursor_x "${cursor_x}" --argjson cursor_y "${cursor_y}" '
    . as $monitors
    | ([
        $monitors[]
        | .logical_width = (if (.transform % 2) == 1 then .height / .scale else .width / .scale end)
        | .logical_height = (if (.transform % 2) == 1 then .width / .scale else .height / .scale end)
        | select(
            $cursor_x >= .x and $cursor_x < (.x + .logical_width)
            and $cursor_y >= .y and $cursor_y < (.y + .logical_height)
          )
      ][0] // [$monitors[] | select(.focused)][0] // $monitors[0])
    | [.name, (.activeWorkspace.id | tostring)]
    | @tsv
  ' <<< "${monitors_json}")" || return 1

  IFS=$'\t' read -r cursor_monitor curr_workspace <<< "${monitor_state}"
  [[ -n "${cursor_monitor}" && "${curr_workspace}" =~ ^[0-9]+$ ]]
}

dispatch_workspace() {
  local target="$1"

  case "${dispatcher}" in
    workspace)
      # Hyprland creates a previously unused workspace on the focused monitor.
      # Focus the monitor under the pointer first, so Win+number follows the
      # mouse instead of stale keyboard focus from the other display.
      if [[ -n "${cursor_monitor}" ]]; then
        hyprctl dispatch "hl.dsp.focus({ monitor = \"${cursor_monitor}\" })" >/dev/null
      fi
      hyprctl dispatch "hl.dsp.focus({ workspace = \"${target}\" })"
      ;;
    movetoworkspacesilent)
      hyprctl dispatch "hl.dsp.window.move({ workspace = \"${target}\", follow = false })"
      ;;
    *)
      echo "Unsupported dispatcher for Lua config: ${dispatcher}" >&2
      return 1
      ;;
  esac
}

if [[ -z "${dispatcher}" || "${dispatcher}" == "--help" || "${dispatcher}" == "-h" || -z "$1" ]]; then
  echo "Usage: $0 <dispatcher> <target>"
  exit 1
fi

if [[ "${dispatcher}" == "workspace" ]]; then
  get_cursor_workspace || curr_workspace="$(hyprctl activeworkspace -j | jq -r '.id')"
else
  curr_workspace="$(hyprctl activeworkspace -j | jq -r '.id')"
fi

if [[ "$1" == *"+"* || "$1" == *"-"* ]]; then ## Is this something like r+1 or -1?
  dispatch_workspace "$1" ## $1 = workspace id since we shifted earlier.
elif [[ "$1" =~ ^[0-9]+$ ]]; then ## Is this just a number?
  target_workspace=$((((curr_workspace - 1) / 10 ) * 10 + $1))
  dispatch_workspace "${target_workspace}"
else
  dispatch_workspace "$1" ## In case the target is a string, required for special workspaces.
fi
