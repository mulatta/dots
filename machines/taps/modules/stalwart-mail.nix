{
  config,
  pkgs,
  ...
}:
let
  domain = "mail.mulatta.io";

  kanidmTokenFile = "/var/lib/stalwart-mail/kanidm-token";
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

        allowed-ip."61.84.68.70" = "";

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
        cert = "%{file:/var/lib/acme/${domain}/fullchain.pem}%";
        private-key = "%{file:/var/lib/acme/${domain}/key.pem}%";
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
        data = "rocksdb";
        fts = "rocksdb";
        blob = "rocksdb";
        lookup = "rocksdb";
        directory = "kanidm";
        sieve = "rocksdb";
      };

      store.rocksdb = {
        type = "rocksdb";
        path = "/var/lib/stalwart-mail/data";
        compression = "lz4";
      };

      directory.internal = {
        type = "internal";
        store = "rocksdb";
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
          groups = "memberof";
          # Workaround: Kanidm doesn't expose password via LDAP
          secret = "entryuuid";
          secret-changed = "entryuuid";
        };
      };

      authentication.fallback-admin = {
        user = "admin";
        secret = "%{file:${config.clan.core.vars.generators.stalwart-admin.files."password".path}}%";
      };

      session = {
        auth = {
          mechanisms = [
            {
              "if" = "listener != 'smtp'";
              "then" = "'[plain, login]'";
            }
            { "else" = false; }
          ];
          directory = [
            {
              "if" = "listener != 'smtp'";
              "then" = "'kanidm'";
            }
            { "else" = false; }
          ];
        };

        timeout = "5m";
        transfer-limit = "262144000";
        duration = "10m";
      };

      queue.strategy.route = [
        {
          "if" = "is_local_domain('', rcpt_domain)";
          "then" = "'local'";
        }
        { "else" = "'ses'"; }
      ];

      queue.route.local = {
        type = "local";
      };

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

  # Grant stalwart access to nginx ACME certs
  users.users.stalwart-mail.extraGroups = [ "nginx" ];

  # Reload stalwart when certs are renewed
  security.acme.certs.${domain}.reloadServices = [ "stalwart-mail.service" ];

  systemd.services.stalwart-mail = {
    after = [
      "acme-${domain}.service"
      "acme-finished-${domain}.target"
      "kanidm.service"
    ];
    wants = [
      "acme-finished-${domain}.target"
      "kanidm.service"
    ];
    serviceConfig = {
      ProtectClock = true;
      ProtectKernelLogs = true;
    };
  };
}
