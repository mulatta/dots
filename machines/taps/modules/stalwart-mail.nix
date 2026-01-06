{
  config,
  pkgs,
  ...
}:
let
  domain = "mail.mulatta.io";
in
{
  clan.core.vars.generators = {
    aws-ses-smtp = {
      files."username" = {
        secret = true;
        owner = "stalwart-mail";
      };
      files."password" = {
        secret = true;
        owner = "stalwart-mail";
      };
      prompts.username = {
        description = "AWS SES SMTP username (from terraform output ses_smtp_username)";
        type = "hidden";
      };
      prompts.password = {
        description = "AWS SES SMTP password (from terraform output ses_smtp_password)";
        type = "hidden";
      };
      script = ''
        cp "$prompts/username" "$out/username"
        cp "$prompts/password" "$out/password"
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

  services.stalwart-mail = {
    enable = true;
    openFirewall = true;

    settings = {
      server = {
        hostname = domain;

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
        };
      };

      certificate.default = {
        cert = "%{file:/var/lib/acme/${domain}/fullchain.pem}%";
        private-key = "%{file:/var/lib/acme/${domain}/key.pem}%";
        default = true;
      };

      # DKIM signing is handled by AWS SES for outbound mail
      # No local DKIM signing needed since we relay through SES
      auth.dkim.sign = false;

      resolver = {
        type = "system";
        public-suffix = [
          "file://${pkgs.publicsuffix-list}/share/publicsuffix/public_suffix_list.dat"
        ];
      };

      storage = {
        data = "rocksdb";
        fts = "rocksdb";
        blob = "rocksdb";
        lookup = "rocksdb";
        directory = "lldap";
      };

      store.rocksdb = {
        type = "rocksdb";
        path = "/var/lib/stalwart-mail/data";
        compression = "lz4";
      };

      store.db = {
        type = "rocksdb";
        path = "/var/lib/stalwart-mail/db";
        compression = "lz4";
      };

      directory.internal = {
        type = "internal";
        store = "rocksdb";
      };

      directory.lldap = {
        type = "ldap";
        url = "ldap://127.0.0.1:3890";
        timeout = "15s";
        base-dn = "dc=mulatta,dc=io";

        bind = {
          dn = "uid=admin,ou=people,dc=mulatta,dc=io";
          secret = "%{file:${config.clan.core.vars.generators.lldap-secrets.files."admin-password".path}}%";
          auth.method = "lookup";
        };

        filter = {
          name = "(&(|(uid=?)(mail=?))(objectClass=person))";
          email = "(&(|(uid=?)(mail=?))(objectClass=person))";
        };

        attributes = {
          name = "uid";
          email = "mail";
          description = "displayName";
          groups = "memberOf";
        };
      };

      # Fallback admin account - uses sops secret
      authentication.fallback-admin = {
        user = "admin";
        secret = "%{file:${config.clan.core.vars.generators.stalwart-admin.files."password".path}}%";
      };

      session = {
        auth = {
          mechanisms = [
            {
              "if" = "listener != 'smtp'";
              "then" = "[plain, login]";
            }
            { "else" = false; }
          ];
          directory = [
            {
              "if" = "listener != 'smtp'";
              "then" = "lldap";
            }
            { "else" = false; }
          ];
        };

        timeout = "5m";
        transfer-limit = "262144000";
        duration = "10m";
      };

      # Routing strategy - local delivery or relay through AWS SES
      queue.strategy.route = [
        {
          "if" = "is_local_domain('', rcpt_domain)";
          "then" = "'local'";
        }
        { "else" = "'ses'"; }
      ];

      # Local delivery route
      queue.route.local = {
        type = "local";
      };

      # AWS SES relay route
      queue.route.ses = {
        type = "relay";
        address = "email-smtp.us-east-1.amazonaws.com";
        port = 587;
        protocol = "smtp";

        tls = {
          implicit = false;
          allow-invalid-certs = false;
        };

        auth = {
          enable = true;
          username = "%{file:${config.clan.core.vars.generators.aws-ses-smtp.files."username".path}}%";
          secret = "%{file:${config.clan.core.vars.generators.aws-ses-smtp.files."password".path}}%";
        };
      };

      spam-filter = {
        enable = true;
        resource = "file://${pkgs.stalwart-mail.passthru.spam-filter}/spam-filter.toml";
      };

      webadmin = {
        enable = true;
        path = "/var/cache/stalwart-mail";
        resource = "file://${pkgs.stalwart-mail.passthru.webadmin}/webadmin.zip";
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

  # Grant stalwart access to nginx ACME certs and LLDAP bind password
  # ACME certs are owned by acme:nginx, so we need nginx group
  users.users.stalwart-mail.extraGroups = [
    "nginx"
    "lldap-bind"
  ];

  # Reload stalwart when certs are renewed
  security.acme.certs.${domain}.reloadServices = [ "stalwart-mail.service" ];

  systemd.services.stalwart-mail = {
    after = [
      "acme-${domain}.service"
      "acme-finished-${domain}.target"
      "sops-nix.service"
    ];
    wants = [ "acme-finished-${domain}.target" ];
    serviceConfig = {
      ProtectClock = true;
      ProtectKernelLogs = true;
    };
  };
}
