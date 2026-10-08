# Owner-side registration for the agents declared in services.buzz-agents.
# The relay only accepts events authored by the authenticated identity, so
# these steps need the owner key and run on the admin machine.
{
  writeShellApplication,
  jq,
  nak,
  buzz-cli,
  clan-cli,
}:
writeShellApplication {
  name = "buzz-agents-sync";
  runtimeInputs = [
    jq
    nak
    buzz-cli
    clan-cli
  ];
  text = ''
    flake=''${1:-.}

    machines=$(nix eval --json "$flake#nixosConfigurations" --apply '
      configs: builtins.mapAttrs (_: c:
        let b = c.config.services.buzz-agents; in
        if b.agents == { } then null else {
          inherit (b) relayUrl ownerPubkey;
          agents = builtins.mapAttrs (_: a: {
            inherit (a) pubkey displayName respondTo channels;
          }) b.agents;
        }) configs')

    for machine in $(jq -r 'to_entries[] | select(.value != null) | .key' <<<"$machines"); do
      spec=$(jq -c --arg m "$machine" '.[$m]' <<<"$machines")
      owner=$(jq -r .ownerPubkey <<<"$spec")
      relay=$(jq -r .relayUrl <<<"$spec")

      nsec=$(clan vars get --flake "$flake" "$machine" buzz-owner-secret/nsec)
      # Signing with the wrong identity would register a different owner.
      if [ "$(nak decode "$nsec" | nak key public)" != "$owner" ]; then
        echo "$machine: buzz-owner-secret does not belong to $owner" >&2
        exit 1
      fi
      export NOSTR_SECRET_KEY=$nsec BUZZ_PRIVATE_KEY=$nsec BUZZ_RELAY_URL=$relay
      unset nsec

      for agent in $(jq -r '.agents | keys[]' <<<"$spec"); do
        a=$(jq -c --arg n "$agent" '.agents[$n]' <<<"$spec")
        pubkey=$(jq -r .pubkey <<<"$a")
        content=$(jq -c '{name: .displayName, parallelism: 1, respond_to: .respondTo}' <<<"$a")

        echo "$machine/$agent: registering $pubkey"
        nak event --auth -k 30177 -d "$pubkey" -c "$content" "''${relay/https:/wss:}" >/dev/null

        for channel in $(jq -r '.channels[]' <<<"$a"); do
          if buzz channels members --channel "$channel" |
            jq -e --arg p "$pubkey" 'any(.[]; .pubkey == $p)' >/dev/null; then
            echo "$machine/$agent: already in $channel"
          else
            buzz channels add-member --channel "$channel" --pubkey "$pubkey" --role bot >/dev/null
            echo "$machine/$agent: added to $channel"
          fi
        done
      done
      unset NOSTR_SECRET_KEY BUZZ_PRIVATE_KEY
    done
  '';
}
