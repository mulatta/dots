# Close Neko pages nobody has used for IDLE_SECONDS; reads CDP_URL and UI_PORT.
cdp=$CDP_URL
state="$STATE_DIRECTORY/seen.json"

# A viewer may be reading any tab, so skip the whole run while one is connected.
pid=$(podman inspect --format '{{.State.Pid}}' neko)
if [ -n "$(nsenter -t "$pid" -n ss -Htn state established "( sport = :$UI_PORT )")" ]; then
  exit 0
fi

ws=$(curl -fsS "$cdp/json/version" | jq -r .webSocketDebuggerUrl)
pages=$(echo '{"id":1,"method":"Target.getTargets"}' |
  websocat -n1 -B 16777216 "$ws" |
  jq '[.result.targetInfos[] | select(.type == "page")]')
prev=$(cat "$state" 2>/dev/null || echo '{}')

# A page is in use while a CDP client is attached or its URL or title changes.
seen=$(jq -n --argjson pages "$pages" --argjson prev "$prev" --argjson now "$(date +%s)" '
  $pages | map(
    (.url + "\n" + .title) as $fp
    | {key: .targetId, value: {
        fp: $fp,
        blank: (.url == "about:blank"),
        since: (if (.attached | not) and $prev[.targetId].fp == $fp then $prev[.targetId].since else $now end)
      }}
  ) | from_entries')
echo "$seen" >"$state"

mapfile -t idle < <(jq -r --argjson now "$(date +%s)" --argjson limit "$IDLE_SECONDS" '
  to_entries[] | select((.value.blank | not) and $now - .value.since >= $limit) | .key' <<<"$seen")
[ ${#idle[@]} -gt 0 ] || exit 0

# Closing the last tab would close the window, so leave a blank one.
if [ "${#idle[@]}" -eq "$(jq length <<<"$seen")" ]; then
  curl -fsS -X PUT "$cdp/json/new?about:blank" >/dev/null
fi
for id in "${idle[@]}"; do
  curl -fsS "$cdp/json/close/$id" >/dev/null
done
