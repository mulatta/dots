#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: loop.sh start <interval: 90s|5m|1h> <prompt> | list | stop <name|all>" >&2
  exit 2
}

seconds() {
  case "$1" in
  *[!0-9smh]* | "" | [smh]*) return 1 ;;
  *s) echo "${1%s}" ;;
  *m) echo $((${1%m} * 60)) ;;
  *h) echo $((${1%h} * 3600)) ;;
  *) echo "$1" ;;
  esac
}

names() {
  hc ls --json | jq -r --arg p "loop-${HC_TERMINAL_ID}-" '.. | objects | select(has("name")) | .name | select(startswith($p))'
}

[ "${1:-}" = tick ] || [ -n "${HC_TERMINAL_ID:-}" ] || {
  echo "loop.sh: not inside an hc terminal, so nothing can deliver the ticks" >&2
  exit 1
}

case "${1:-}" in
tick)
  while sleep "$2"; do
    while :; do
      case $(hc get "$3" --json | jq -r '.status.state // "idle"') in
      working | blocked)
        hc wait "$3" --timeout 600 >/dev/null 2>&1 || true
        sleep 5
        ;;
      *)
        hc send "$3" "$4" >/dev/null 2>&1 || true
        break
        ;;
      esac
    done
  done
  ;;
start)
  [ $# -eq 3 ] || usage
  secs=$(seconds "$2") || usage
  name="loop-${HC_TERMINAL_ID}-$(date +%s)"
  hc run --bg --name "$name" -- "$(cd "$(dirname "$0")" && pwd)/$(basename "$0")" tick "$secs" "$HC_TERMINAL_ID" "$3" >/dev/null
  echo "$name every $2: $3"
  ;;
list)
  names
  ;;
stop)
  [ $# -eq 2 ] || usage
  if [ "$2" = all ]; then targets=$(names); else targets=$2; fi
  for t in $targets; do
    hc kill "$t" >/dev/null 2>&1 || true
    hc rm "$t" >/dev/null 2>&1 || true
    echo "stopped $t"
  done
  ;;
*) usage ;;
esac
