#!/bin/bash
# nostr-chat-shot — capture a screen region and send it to the chat peer.
#
# macOS replacement for the upstream slurp/grim keybind flow: hide the
# panel so it stays out of the capture, run the interactive selection,
# hand the file to the daemon (which unlinks it after caching), bring
# the panel back. Panel control uses the bar's control socket; the
# file transfer talks straight to the daemon socket — both are plain
# NDJSON over unix sockets.
set -euo pipefail

usage() {
  echo "usage: nostr-chat-shot [--socket PATH] [--control-socket PATH]"
}

socket="${NOSTR_CHAT_SOCKET:-}"
ctl="${NOSTR_CHAT_BAR_CONTROL_SOCKET:-}"

while [ $# -gt 0 ]; do
  case "$1" in
  --socket)
    if [ $# -lt 2 ]; then
      echo "missing value for --socket" >&2
      usage >&2
      exit 1
    fi
    socket="$2"
    shift 2
    ;;
  --control-socket)
    if [ $# -lt 2 ]; then
      echo "missing value for --control-socket" >&2
      usage >&2
      exit 1
    fi
    ctl="$2"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "unknown option: $1" >&2
    usage >&2
    exit 1
    ;;
  esac
done

# Same defaults as the app, plus the Home Manager state-dir layout.
if [ -z "$socket" ]; then
  tmpdir="${TMPDIR:-/tmp}"
  tmpdir="${tmpdir%/}"
  for candidate in \
    "${XDG_RUNTIME_DIR:-/nonexistent}/nostr-chatd.sock" \
    "$tmpdir/nostr-chatd.sock" \
    "${XDG_STATE_HOME:-$HOME/.local/state}/nostr-chatd/nostr-chatd.sock"; do
    if [ -S "$candidate" ]; then
      socket="$candidate"
      break
    fi
  done
fi
if [ -z "$socket" ] || [ ! -S "$socket" ]; then
  echo "nostr-chat-shot: daemon socket not found; pass --socket" >&2
  exit 1
fi
: "${ctl:=$(dirname "$socket")/nostr-chat-bar-ctl.sock}"

# Best-effort panel control: the bar may not be running, and a capture
# without panel choreography is still a capture. -w 1 because both
# daemons hold their connection open; nc must not wait for EOF.
ctl_send() {
  [ -S "$ctl" ] || return 0
  printf '{"cmd":"%s"}\n' "$1" | nc -w 1 -U "$ctl" >/dev/null 2>&1 || true
}

# Whatever happens after hiding — cancel, daemon error, ^C — bring the
# panel back.
trap 'ctl_send present' EXIT

tmpdir="${TMPDIR:-/tmp}"
tmpdir="${tmpdir%/}"
shot="$(mktemp "$tmpdir/nostr-chat-shot.XXXXXX.png")"

ctl_send hide
sleep 0.3 # let the slide-out finish so the panel is not in the capture

if ! screencapture -i "$shot" || [ ! -s "$shot" ]; then
  rm -f "$shot"
  exit 0 # selection cancelled
fi

# jq builds the JSON so the path can never break out of the string.
# shellcheck disable=SC2016 # $path is jq syntax, not shell
@jq@ -cn --arg path "$shot" '{cmd: "send-file", path: $path, unlink: true}' |
  nc -w 1 -U "$socket" >/dev/null
