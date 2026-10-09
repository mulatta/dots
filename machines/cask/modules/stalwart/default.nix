{
  config,
  pkgs,
  ...
}:
let
  baseDomain = "mulatta.io";
  mailDomain = "mail.${baseDomain}";
  publicDomain = "stalwart.${baseDomain}";

  cfg = config.services.stalwart;
  kanidmTokenFile = "${cfg.dataDir}/kanidm-token";
  adminPasswordFile = config.clan.core.vars.generators.stalwart-admin.files."password".path;
  resendKeyFile = config.clan.core.vars.generators.resend.files."api-key".path;
  acmeDir = config.security.acme.certs.${mailDomain}.directory;
  credential = name: "%{file:/run/credentials/stalwart.service/${name}}%";
in
{
  imports = [ ./provision ];

  clan.core.vars.generators = {
    resend = {
      files."api-key" = {
        secret = true;
        owner = cfg.user;
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
        owner = cfg.user;
      };
      runtimeInputs = [ pkgs.openssl ];
      script = ''
        openssl rand -base64 32 | tr -d '\n' > "$out/password"
      '';
    };

  };

  services.stalwart = {
    enable = true;
    package = pkgs.stalwart_0_15;
    stateVersion = "25.05";
    # Keep the loopback HTTP listener out of the public firewall allow-list.
    openFirewall = false;
    credentials = {
      admin-password = adminPasswordFile;
      ldap-token = kanidmTokenFile;
      resend-api-key = resendKeyFile;
    };

    settings = {
      # Nix owns service policy; runtime IP bans and exceptions stay in the DB.
      config.local-keys = [
        "store.*"
        "storage.*"
        "directory.*"
        "email.*"
        "certificate.*"
        "server.*"
        "!server.blocked-ip.*"
        "!server.allowed-ip.*"
        "authentication.*"
        "http.*"
        "tracer.*"
        "config.local-keys.*"
        "auth.dkim.sign"
        "oauth.*"
        "session.*"
        "queue.strategy.route.*"
        "queue.route.local.*"
        "queue.route.resend.*"
        "spam-filter.enable"
        "spam-filter.resource"
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
        cert = "%{file:${acmeDir}/fullchain.pem}%";
        private-key = "%{file:${acmeDir}/key.pem}%";
        default = true;
      };

      # Outbound delivery uses Resend's domain signing rather than local keys.
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
        # Keep all durable mail state in one PostgreSQL database so pg_dump
        # captures metadata and referenced message content at one MVCC point.
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
        # Peer authentication ignores this required password field.
        password = "unused";
        timeout = "15s";
        tls.enable = false;
        pool.max-connections = 3;
      };

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
          secret = credential "ldap-token";
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
        secret = credential "admin-password";
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

        # Tagged addresses share the base mailbox; LDAP still rejects unknown users.
        rcpt = {
          sub-addressing = [
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
        };

        timeout = "5m";
        transfer-limit = "262144000";
        duration = "10m";
      };

      queue = {
        strategy.route = [
          {
            "if" = "is_local_domain('', rcpt_domain)";
            "then" = "'local'";
          }
          { "else" = "'resend'"; }
        ];
        route = {
          local.type = "local";
          resend = {
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
              secret = credential "resend-api-key";
            };
          };
        };
      };

      spam-filter = {
        enable = true;
        resource = "file://${cfg.package.passthru.spam-filter}/spam-filter.toml";
      };

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

      # Avoid whitespace in mbsync patterns without renaming standard folders.
      email.folders.shared.name = "Shared";

      webadmin = {
        enable = true;
        resource = "file://${cfg.package.passthru.webadmin}/webadmin.zip";
      };

      tracer.stdout = {
        type = "stdout";
        enable = true;
        level = "info";
        ansi = false;
      };
    };
  };

  networking.firewall.allowedTCPPorts = [
    25
    143
    465
    587
    993
    4190
  ];

  users.users.${cfg.user}.extraGroups = [ "nginx" ];

  security.acme.certs.${mailDomain} = {
    webroot = "/var/lib/acme/acme-challenge";
    group = "nginx";
    reloadServices = [ "stalwart.service" ];
  };

  systemd.services.stalwart = {
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
    };
  };

  services.nginx.virtualHosts.${publicDomain} = {
    useACMEHost = "mulatta.io";
    forceSSL = true;
    mulatta.securityHeaders = "deny";
    locations."/" = {
      proxyPass = "http://127.0.0.1:8080";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        client_max_body_size 50M;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
    };
  };

  services.nginx.virtualHosts."mta-sts.${baseDomain}" = {
    useACMEHost = "mulatta.io";
    forceSSL = true;
    locations."=/.well-known/mta-sts.txt".alias = pkgs.writeText "mta-sts.txt" ''
      version: STSv1
      mode: enforce
      mx: ${mailDomain}
      max_age: 86400
    '';
  };
}
