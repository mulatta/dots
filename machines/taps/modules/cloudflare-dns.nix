{
  config,
  pkgs,
  ...
}:
let
  domain = "mulatta.io";
  mailDomain = "mail.${domain}";
  cfTokenPath = config.clan.core.vars.generators.cloudflare-api.files."token".path;
  dkimSelectorEd25519 = "202501e";
  dkimSelectorRsa = "202501r";

  syncDnsScript = pkgs.writeShellScript "cloudflare-dns-sync" ''
    set -euo pipefail

    CF_API_TOKEN=$(cat ${cfTokenPath})
    ZONE_NAME="${domain}"

    # Get Zone ID
    ZONE_ID=$(${pkgs.curl}/bin/curl -s -X GET \
      "https://api.cloudflare.com/client/v4/zones?name=$ZONE_NAME" \
      -H "Authorization: Bearer $CF_API_TOKEN" \
      -H "Content-Type: application/json" \
      | ${pkgs.jq}/bin/jq -r '.result[0].id')

    if [ "$ZONE_ID" = "null" ] || [ -z "$ZONE_ID" ]; then
      echo "ERROR: Could not find zone ID for $ZONE_NAME"
      exit 1
    fi

    echo "Zone ID: $ZONE_ID"

    upsert_record() {
      local name="$1"
      local type="$2"
      local content="$3"
      local priority="''${4:-}"
      local proxied="false"
      local ttl="300"

      # Build full name
      if [ "$name" = "@" ]; then
        full_name="$ZONE_NAME"
      else
        full_name="$name.$ZONE_NAME"
      fi

      echo "Processing: $type $full_name"

      existing=$(${pkgs.curl}/bin/curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=$type&name=$full_name" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json")

      record_id=$(echo "$existing" | ${pkgs.jq}/bin/jq -r '.result[0].id // empty')
      existing_content=$(echo "$existing" | ${pkgs.jq}/bin/jq -r '.result[0].content // empty')

      if [ "$type" = "MX" ]; then
        payload=$(${pkgs.jq}/bin/jq -n \
          --arg type "$type" \
          --arg name "$full_name" \
          --arg content "$content" \
          --argjson priority "$priority" \
          --argjson ttl "$ttl" \
          '{type: $type, name: $name, content: $content, priority: $priority, ttl: $ttl}')
      elif [ "$type" = "SRV" ]; then
        IFS=' ' read -r srv_priority srv_weight srv_port srv_target <<< "$content"
        payload=$(${pkgs.jq}/bin/jq -n \
          --arg type "$type" \
          --arg name "$full_name" \
          --argjson priority "$srv_priority" \
          --argjson ttl "$ttl" \
          --arg target "$srv_target" \
          --argjson weight "$srv_weight" \
          --argjson port "$srv_port" \
          '{type: $type, name: $name, ttl: $ttl, data: {priority: $priority, weight: $weight, port: $port, target: $target}}')
      else
        payload=$(${pkgs.jq}/bin/jq -n \
          --arg type "$type" \
          --arg name "$full_name" \
          --arg content "$content" \
          --argjson proxied "$proxied" \
          --argjson ttl "$ttl" \
          '{type: $type, name: $name, content: $content, proxied: $proxied, ttl: $ttl}')
      fi

      if [ -n "$record_id" ]; then
        if [ "$existing_content" != "$content" ]; then
          echo "  Updating record $record_id"
          ${pkgs.curl}/bin/curl -s -X PUT \
            "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$record_id" \
            -H "Authorization: Bearer $CF_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data "$payload" | ${pkgs.jq}/bin/jq -r '.success'
        else
          echo "  Record unchanged, skipping"
        fi
      else
        echo "  Creating new record"
        ${pkgs.curl}/bin/curl -s -X POST \
          "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
          -H "Authorization: Bearer $CF_API_TOKEN" \
          -H "Content-Type: application/json" \
          --data "$payload" | ${pkgs.jq}/bin/jq -r '.success'
      fi
    }

    echo "Syncing DNS records for $ZONE_NAME..."

    upsert_record "@" "MX" "${mailDomain}" "10"

    upsert_record "@" "TXT" "v=spf1 mx ~all"
    upsert_record "_dmarc" "TXT" "v=DMARC1; p=quarantine; rua=mailto:dmarc@${domain}"
    upsert_record "_mta-sts" "TXT" "v=STSv1; id=20250102"
    upsert_record "_smtp._tls" "TXT" "v=TLSRPTv1; rua=mailto:tls-reports@${domain}"

    DKIM_ED25519_FILE="${
      config.clan.core.vars.generators.stalwart-dkim-ed25519.files."public-key".path
    }"
    DKIM_RSA_FILE="${config.clan.core.vars.generators.stalwart-dkim-rsa.files."public-key".path}"

    if [ -f "$DKIM_ED25519_FILE" ]; then
      DKIM_ED25519=$(cat "$DKIM_ED25519_FILE")
      upsert_record "${dkimSelectorEd25519}._domainkey" "TXT" "v=DKIM1; k=ed25519; p=$DKIM_ED25519"
    else
      echo "WARNING: DKIM ed25519 public key not found at $DKIM_ED25519_FILE"
    fi

    if [ -f "$DKIM_RSA_FILE" ]; then
      DKIM_RSA=$(cat "$DKIM_RSA_FILE")
      upsert_record "${dkimSelectorRsa}._domainkey" "TXT" "v=DKIM1; k=rsa; p=$DKIM_RSA"
    else
      echo "WARNING: DKIM RSA public key not found at $DKIM_RSA_FILE"
    fi

    upsert_record "autodiscover" "CNAME" "${mailDomain}"
    upsert_record "autoconfig" "CNAME" "${mailDomain}"

    upsert_record "_caldavs._tcp" "SRV" "0 1 443 ${mailDomain}"
    upsert_record "_carddavs._tcp" "SRV" "0 1 443 ${mailDomain}"

    echo "DNS sync complete!"
  '';
in
{
  clan.core.vars.generators.cloudflare-api = {
    files."token".secret = true;
    prompts.token = {
      description = "Cloudflare API token (same as Terraform's CLOUDFLARE_API_TOKEN)";
      type = "hidden";
    };
    script = ''
      cp "$prompts/token" "$out/token"
    '';
  };

  systemd.services.cloudflare-dns-sync = {
    description = "Sync DNS records to Cloudflare";
    after = [
      "network-online.target"
      "sops-nix.service"
    ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = syncDnsScript;
      Restart = "on-failure";
      RestartSec = "30s";
    };
  };

  systemd.timers.cloudflare-dns-sync = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };
}
