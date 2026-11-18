#!/usr/bin/env bash
# Attachment and document identity are conservative proxies for activity, not leases.
set -euo pipefail

update_seen() {
  jq -cn --argjson pages "$1" --argjson prev "$2" --argjson now "$3" '
    $pages | map(
      (.url + "\n" + .title) as $fp
      | {key: .targetId, value: {
          fp: $fp,
          blank: (.url == "about:blank"),
          since: (if .attached == false and $prev[.targetId].fp == $fp
                  then ($prev[.targetId].since // $now) else $now end)
        }}
    ) | from_entries'
}

close_candidate() {
  jq -nr --argjson pages "$1" --argjson seen "$2" --arg id "$3" --argjson now "$4" --argjson limit "$5" '
    any($pages[];
      .targetId == $id and .attached == false and .url != "about:blank"
      and $seen[$id].fp == (.url + "\n" + .title)
      and ($seen[$id].since | type) == "number"
      and $now - $seen[$id].since >= $limit)'
}

viewer_connected() {
  local connections
  # A failed socket inspection is not evidence that the browser is unattended.
  connections=$(nsenter -t "$pid" -n ss -Htn state established "( sport = :$UI_PORT )") || exit 1
  [[ -n $connections ]]
}

read_pages() {
  printf '%s\n' '{"id":1,"method":"Target.getTargets"}' |
    websocat -n1 -B 16777216 "$ws" |
    jq -ce '.result.targetInfos | select(type == "array") | map(select(.type == "page"))'
}

save_seen() {
  local temporary
  temporary=$(mktemp "$STATE_DIRECTORY/seen.XXXXXX")
  printf '%s\n' "$1" >"$temporary"
  mv "$temporary" "$state"
}

main() {
  local cdp state pid ws pages prev seen id current status
  cdp=$CDP_URL
  state="$STATE_DIRECTORY/seen.json"
  pid=$(podman inspect --format '{{.State.Pid}}' neko)

  # A person leaving must get a fresh grace period, not inherit old idle evidence.
  if viewer_connected; then
    save_seen '{}'
    return
  fi

  ws=$(curl -fsS --max-time 5 "$cdp/json/version" | jq -er .webSocketDebuggerUrl)
  pages=$(read_pages)
  prev=$(jq -ce 'select(type == "object")' "$state" 2>/dev/null || printf '{}')
  seen=$(update_seen "$pages" "$prev" "$(date +%s)")
  save_seen "$seen"

  while IFS= read -r id; do
    if [[ $(close_candidate "$pages" "$seen" "$id" "$(date +%s)" "$IDLE_SECONDS") != true ]]; then
      continue
    fi
    current=$(read_pages)
    if viewer_connected; then
      save_seen '{}'
      return
    fi
    # CDP has no atomic "close only if still idle": revalidation is best effort.
    if [[ $(close_candidate "$current" "$seen" "$id" "$(date +%s)" "$IDLE_SECONDS") != true ]]; then
      continue
    fi
    if [[ $(jq length <<<"$current") -eq 1 ]]; then
      curl -fsS --max-time 5 -X PUT "$cdp/json/new?about:blank" >/dev/null
    fi
    status=0
    curl -fsS --max-time 5 "$cdp/json/close/$id" >/dev/null || status=$?
    current=$(read_pages)
    if jq -e --arg id "$id" 'any(.[]; .targetId == $id)' <<<"$current" >/dev/null; then
      printf 'Idle target %s remains after close (curl status %s)\n' "$id" "$status" >&2
    else
      printf 'Closed idle target %s\n' "$id"
    fi
  done < <(jq -r 'keys[]' <<<"$seen")
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
