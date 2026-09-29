# supergfxctl helper for interactive zsh sessions.

sgfx() {
  emulate -L zsh

  local command="${1:-status}"
  local mode next

  case "$command" in
    status|s|get|-g|--get)
      supergfxctl -g
      ;;
    pending|p|-P|--pending)
      supergfxctl -P
      ;;
    toggle|t)
      mode="$(supergfxctl -g 2>/dev/null)"
      case "${mode:l}" in
        *integrated*) next="Hybrid" ;;
        *hybrid*) next="Integrated" ;;
        *)
          print -u2 "sgfx: unknown supergfxctl mode: ${mode:-empty}"
          return 1
          ;;
      esac
      supergfxctl -m "$next"
      ;;
    integrated|i)
      supergfxctl -m Integrated
      ;;
    hybrid|h)
      supergfxctl -m Hybrid
      ;;
    help|-h|--help)
      print "usage: sgfx [status|pending|toggle|integrated|hybrid]"
      ;;
    *)
      print -u2 "usage: sgfx [status|pending|toggle|integrated|hybrid]"
      return 2
      ;;
  esac
}
