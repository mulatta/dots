{
  config,
  pkgs,
  ...
}:
let
  baseDomain = "mulatta.io";
  mailDomain = "mail.${baseDomain}";
  publicDomain = "stalwart.${baseDomain}";

  kanidmTokenFile = "/var/lib/stalwart-mail/kanidm-token";

  bulwarkOauthClient = pkgs.writeShellApplication {
    name = "stalwart-bulwark-oauth-client";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.jq
    ];
    text = ''
      admin_password_file=${config.clan.core.vars.generators.stalwart-admin.files."password".path}
      api_url=http://127.0.0.1:8080/api/principal

      auth=$(printf 'admin:%s' "$(cat "$admin_password_file")" | base64 --wrap=0)

      curl_api() {
        curl \
          --fail \
          --silent \
          --show-error \
          --retry 30 \
          --retry-connrefused \
          --retry-delay 1 \
          --retry-all-errors \
          --header "Authorization: Basic $auth" \
          "$@"
      }

      redirects=$(jq --compact-output --null-input '{
        list: [
          "cs", "en", "fr", "de", "es", "it", "ja", "ko",
          "lv", "nl", "pl", "pt", "ru", "tr", "uk", "zh"
        ] | map("https://mail.mulatta.io/" + . + "/auth/callback")
      } | .list')

      register_client() {
        local client_id=$1
        local description=$2
        local urls=$3
        local current body

        current=$(curl_api "$api_url/$client_id")
        if jq --exit-status '.error == "notFound"' <<<"$current" >/dev/null; then
          body=$(jq --compact-output --null-input \
            --arg client "$client_id" \
            --arg description "$description" \
            --argjson urls "$urls" \
            '{type: "oauthClient", name: $client, description: $description, urls: $urls}')
          curl_api \
            --header 'Content-Type: application/json' \
            --data "$body" \
            "$api_url" >/dev/null
        else
          body=$(jq --compact-output --null-input \
            --arg description "$description" \
            --argjson urls "$urls" \
            '[
              {action: "set", field: "description", value: $description},
              {action: "set", field: "urls", value: $urls}
            ]')
          curl_api \
            --request PATCH \
            --header 'Content-Type: application/json' \
            --data "$body" \
            "$api_url/$client_id" >/dev/null
        fi
      }

      register_client bulwark-webmail "Bulwark Webmail" "$redirects"
      register_client webadmin "Stalwart Webadmin" '["stalwart://auth"]'

      echo "stalwart-bulwark-oauth-client: registered Stalwart OAuth clients"
    '';
  };

  opencrowMailAcl = pkgs.writeShellApplication {
    name = "stalwart-opencrow-mail-acl";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.jq
    ];
    text = ''
      admin_password_file=${config.clan.core.vars.generators.stalwart-admin.files."password".path}
      session_url=http://127.0.0.1:8080/.well-known/jmap
      jmap_url=http://127.0.0.1:8080/jmap/
      core=urn:ietf:params:jmap:core
      mail=urn:ietf:params:jmap:mail
      principals=urn:ietf:params:jmap:principals

      auth=$(printf 'admin:%s' "$(cat "$admin_password_file")" | base64 --wrap=0)

      curl_jmap() {
        curl \
          --fail \
          --silent \
          --show-error \
          --retry 30 \
          --retry-delay 1 \
          --retry-all-errors \
          --header "Authorization: Basic $auth" \
          --header 'Content-Type: application/json' \
          "$jmap_url" \
          --data "$1"
      }

      session=$(curl \
        --fail \
        --location \
        --silent \
        --show-error \
        --retry 30 \
        --retry-delay 1 \
        --retry-all-errors \
        --header "Authorization: Basic $auth" \
        --header 'Accept: application/json' \
        "$session_url")
      admin_account_id=$(jq --raw-output --exit-status --arg principals "$principals" '.primaryAccounts[$principals]' <<<"$session")

      principal_id() {
        local name=$1
        local request response
        request=$(jq --compact-output --null-input \
          --arg core "$core" \
          --arg principals "$principals" \
          --arg account "$admin_account_id" \
          --arg name "$name" \
          '{
            using: [$core, $principals],
            methodCalls: [
              ["Principal/query", {accountId: $account, filter: {text: $name}, limit: 20}, "query"],
              ["Principal/get", {accountId: $account, "#ids": {resultOf: "query", name: "Principal/query", path: "/ids"}, properties: ["id", "name"]}, "get"]
            ]
          }')
        response=$(curl_jmap "$request")
        jq --raw-output --exit-status --arg name "$name" '
          .methodResponses[]
          | select(.[0] == "Principal/get")
          | .[1].list[]
          | select(.name == $name)
          | .id
        ' <<<"$response" | head --lines=1
      }

      seungwon_id=$(principal_id seungwon)
      noa_id=$(principal_id noa)

      request=$(jq --compact-output --null-input \
        --arg core "$core" \
        --arg mail "$mail" \
        --arg account "$seungwon_id" \
        '{
          using: [$core, $mail],
          methodCalls: [["Mailbox/get", {accountId: $account, ids: null, properties: ["id", "name", "role", "shareWith"]}, "mailboxes"]]
        }')
      response=$(curl_jmap "$request")
      inbox_id=$(jq --raw-output --exit-status '
        .methodResponses[0][1].list[]
        | select(.role == "inbox")
        | .id
      ' <<<"$response" | head --lines=1)

      if jq --exit-status --arg inbox "$inbox_id" --arg noa "$noa_id" '
        .methodResponses[0][1].list[]
        | select(.id == $inbox)
        | ((.shareWith[$noa].mayReadItems // false) and (.shareWith[$noa].maySetKeywords // false))
      ' <<<"$response" >/dev/null; then
        echo "stalwart-opencrow-mail-acl: seungwon Inbox already grants Noa readItems+setKeywords"
        exit 0
      fi

      request=$(jq --compact-output --null-input \
        --arg core "$core" \
        --arg mail "$mail" \
        --arg account "$seungwon_id" \
        --arg inbox "$inbox_id" \
        --arg noa "$noa_id" \
        '{
          using: [$core, $mail],
          methodCalls: [[
            "Mailbox/set",
            {
              accountId: $account,
              update: {
                ($inbox): {
                  ("shareWith/" + $noa + "/mayReadItems"): true,
                  ("shareWith/" + $noa + "/maySetKeywords"): true
                }
              }
            },
            "set"
          ]]
        }')
      response=$(curl_jmap "$request")
      jq --exit-status --arg inbox "$inbox_id" '
        .methodResponses[0][0] == "Mailbox/set"
        and (.methodResponses[0][1].updated[$inbox] == null)
        and (((.methodResponses[0][1].notUpdated // {}) | has($inbox)) | not)
      ' <<<"$response" >/dev/null
      echo "stalwart-opencrow-mail-acl: granted Noa readItems+setKeywords on seungwon Inbox"
    '';
  };
in
{
  clan.core.vars.generators = {
    resend = {
      files."api-key" = {
        secret = true;
        owner = "stalwart-mail";
      };
      prompts."api-key" = {
        description = "Resend API key (re_...)";
        type = "hidden";
      };
      script = ''
        cp "$prompts/api-key" "$out/api-key"
      '';
    };

    stalwart-admin = {
      files."password" = {
        secret = true;
        owner = "stalwart-mail";
      };
      runtimeInputs = [ pkgs.openssl ];
      script = ''
        openssl rand -base64 32 | tr -d '\n' > "$out/password"
      '';
    };
  };

  services.stalwart = {
    enable = true;
    stateVersion = "25.05";
    openFirewall = true;

    settings = {
      # Declare NixOS-managed keys as local to suppress DB conflict warnings
      config.local-keys = [
        "store.*"
        "storage.*"
        "directory.*"
        "certificate.*"
        "server.*"
        "authentication.*"
        "http.*"
        "tracer.*"
        "tracing.*"
        "config.*"
        "cluster.*"
        "auth.*"
        "oauth.*"
        "session.*"
        "queue.*"
        "spam-filter.*"
        "sieve.*"
        "jmap.*"
        "webadmin.*"
        "resolver.*"
      ];

      server = {
        hostname = mailDomain;

        tls = {
          enable = true;
          implicit = false;
        };

        listener = {
          smtp = {
            bind = [ "[::]:25" ];
            protocol = "smtp";
          };

          submissions = {
            bind = [ "[::]:465" ];
            protocol = "smtp";
            tls.implicit = true;
          };

          submission = {
            bind = [ "[::]:587" ];
            protocol = "smtp";
            tls.implicit = false;
          };

          imap = {
            bind = [ "[::]:143" ];
            protocol = "imap";
          };

          imaptls = {
            bind = [ "[::]:993" ];
            protocol = "imap";
            tls.implicit = true;
          };

          http = {
            bind = [ "127.0.0.1:8080" ];
            protocol = "http";
            tls.implicit = false;
          };

          managesieve = {
            bind = [ "[::]:4190" ];
            protocol = "managesieve";
            tls.implicit = false;
          };
        };
      };

      certificate.default = {
        cert = "%{file:/var/lib/acme/${mailDomain}/fullchain.pem}%";
        private-key = "%{file:/var/lib/acme/${mailDomain}/key.pem}%";
        default = true;
      };

      # DKIM handled by AWS SES relay
      auth.dkim.sign = false;

      resolver = {
        type = "system";
        public-suffix = [
          "file://${pkgs.publicsuffix-list}/share/publicsuffix/public_suffix_list.dat"
        ];
      };

      storage = {
        data = "postgresql";
        fts = "postgresql";
        blob = "postgresql";
        lookup = "postgresql";
        directory = "kanidm";
      };

      store.postgresql = {
        type = "postgresql";
        host = "/run/postgresql";
        port = 5432;
        database = "stalwart-mail";
        user = "stalwart-mail";
        # Connects over the unix socket with peer authentication, so the
        # password is never used. The field is required, hence the placeholder.
        password = "unused";
        timeout = "15s";
        tls.enable = false;
        pool.max-connections = 3;
      };

      # Kanidm LDAP directory
      directory.kanidm = {
        type = "ldap";
        url = "ldaps://127.0.0.1:3636";
        timeout = "15s";
        tls = {
          enable = true;
          allow-invalid-certs = true;
        };
        base-dn = "dc=idm,dc=mulatta,dc=io";

        bind = {
          dn = "dn=token";
          secret = "%{file:${kanidmTokenFile}}%";
          auth = {
            method = "template";
            template = "spn={username}@idm.mulatta.io,dc=idm,dc=mulatta,dc=io";
            search = false;
          };
        };

        filter = {
          name = "(&(objectClass=person)(|(uid=?)(spn=?)(name=?)(mail=?)))";
          email = "(&(objectClass=person)(mail=?))";
        };

        attributes = {
          name = "name";
          email = "mail";
          description = "displayname";
          # groups = "memberof";  # Disabled: causes unwanted Shared Folders
          # Workaround: Kanidm doesn't expose password via LDAP
          secret = "entryuuid";
          secret-changed = "entryuuid";
        };
      };

      authentication.fallback-admin = {
        user = "admin";
        secret = "%{file:${config.clan.core.vars.generators.stalwart-admin.files."password".path}}%";
      };

      http = {
        url = "'https://${publicDomain}'";
        use-x-forwarded = true;
      };

      oauth.client-registration.require = true;

      session = {
        auth = {
          mechanisms = [
            {
              "if" = "local_port != 25";
              "then" = "[plain, login]";
            }
            { "else" = false; }
          ];
          directory = [
            {
              "if" = "local_port != 25";
              "then" = "'kanidm'";
            }
            { "else" = false; }
          ];
        };

        # Subaddressing: rewrite "user.tag@" and "user+tag@" → "user@" before
        # directory lookup. Allows infinite per-service aliases without
        # explicit alias entries; nonexistent base users still bounce because
        # the kanidm lookup runs after rewriting.
        rcpt.sub-addressing = [
          {
            "if" = "matches('^([^.]+)\\.([^.]+)@(.+)$', rcpt)";
            "then" = "$1 + '@' + $3";
          }
          {
            "if" = "matches('^([^+]+)\\+([^+]+)@(.+)$', rcpt)";
            "then" = "$1 + '@' + $3";
          }
          { "else" = "rcpt"; }
        ];

        timeout = "5m";
        transfer-limit = "262144000";
        duration = "10m";
      };

      queue.strategy.route = [
        {
          "if" = "is_local_domain('', rcpt_domain)";
          "then" = "'local'";
        }
        { "else" = "'resend'"; }
      ];

      queue.route.local = {
        type = "local";
      };

      queue.route.resend = {
        type = "relay";
        address = "smtp.resend.com";
        port = 465;
        protocol = "smtp";

        tls = {
          implicit = true;
          allow-invalid-certs = false;
        };

        auth = {
          enable = true;
          username = "resend";
          secret = "%{file:${config.clan.core.vars.generators.resend.files."api-key".path}}%";
        };
      };

      spam-filter = {
        enable = true;
        resource = "file://${pkgs.stalwart.passthru.spam-filter}/spam-filter.toml";
      };

      # Enable user sieve scripts (uploaded via ManageSieve)
      sieve.untrusted = {
        limits = {
          script-size = 1048576;
          string-length = 4096;
          variable-name-length = 32;
          variable-size = 4096;
          nested-blocks = 15;
          nested-tests = 15;
          nested-foreverypart = 3;
          nested-includes = 10;
          match-variables = 30;
          local-variables = 128;
          header-size = 1024;
          includes = 10;
          received-headers = 10;
          cpu = 5000;
          redirects = 1;
          outgoing-messages = 3;
        };
        disable-capabilities = [ ];
        notification-uris = [ "mailto" ];
        protected-headers = [
          "Original-Subject"
          "Original-From"
          "Received"
          "Auto-Submitted"
        ];
      };

      jmap = {
        email.auto-expunge = "30d";
        account.purge.frequency = "0 3 *";
        protocol.request.max-concurrent = 16;
      };

      # Override only the shared-folder namespace prefix; leaving other
      # special-use folders unset keeps stalwart's built-in defaults
      # (Inbox, Drafts, Sent Items, Junk Mail, Deleted Items). Reason:
      # avoid the whitespace in "Shared Folders" which complicates
      # mbsync Patterns and shell handling on every consumer.
      email.folders.shared.name = "Shared";

      webadmin = {
        enable = true;
        path = "/var/cache/stalwart-mail";
        resource = "file://${pkgs.stalwart.passthru.webadmin}/webadmin.zip";
      };

      tracing.stdout = {
        enable = true;
        level = "info";
        ansi = false;
      };

      tracer.stdout = {
        type = "stdout";
        enable = true;
        level = "info";
        ansi = false;
      };
    };
  };

  # Grant stalwart access to nginx ACME certs
  users.users.stalwart-mail.extraGroups = [ "nginx" ];

  # Reload stalwart when certs are renewed
  security.acme.certs.${mailDomain}.reloadServices = [ "stalwart.service" ];

  systemd.services = {
    stalwart = {
      after = [
        "postgresql.service"
        "acme-${mailDomain}.service"
        "acme-finished-${mailDomain}.target"
        "kanidm.service"
      ];
      wants = [
        "acme-finished-${mailDomain}.target"
        "kanidm.service"
      ];
      environment.STALWART_PUBLIC_URL = "https://${publicDomain}";
      serviceConfig = {
        ProtectClock = true;
        ProtectKernelLogs = true;
        RestrictAddressFamilies = [ "AF_UNIX" ];
      };
    };

    stalwart-bulwark-oauth-client = {
      description = "Register Bulwark Webmail OAuth client in Stalwart";
      wantedBy = [ "multi-user.target" ];
      after = [ "stalwart.service" ];
      wants = [ "stalwart.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "stalwart-mail";
        Group = "stalwart-mail";
        ExecStart = "${bulwarkOauthClient}/bin/stalwart-bulwark-oauth-client";
      };
    };

    stalwart-opencrow-mail-acl = {
      description = "Grant Noa keyword rights on seungwon Inbox";
      wantedBy = [ "multi-user.target" ];
      after = [
        "kanidm.service"
        "stalwart.service"
      ];
      wants = [ "stalwart.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "stalwart-mail";
        Group = "stalwart-mail";
        ExecStart = "${opencrowMailAcl}/bin/stalwart-opencrow-mail-acl";
      };
    };
  };
}
