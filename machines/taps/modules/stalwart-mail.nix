{
  config,
  pkgs,
  ...
}:
let
  domain = "mail.mulatta.io";
  baseDomain = "mulatta.io";

  # DKIM selectors - must match cloudflare-dns.nix
  dkimSelectorEd25519 = "202501e";
  dkimSelectorRsa = "202501r";
in
{
  clan.core.vars.generators = {
    stalwart-dkim-ed25519 = {
      files."private-key" = {
        secret = true;
        owner = "stalwart-mail";
      };
      files."public-key".secret = false;
      runtimeInputs = [ pkgs.openssl ];
      script = ''
        openssl genpkey -algorithm ED25519 > "$out/private-key"
        openssl pkey -in "$out/private-key" -pubout -outform DER 2>/dev/null \
          | openssl base64 -A > "$out/public-key"
      '';
    };

    stalwart-dkim-rsa = {
      files."private-key" = {
        secret = true;
        owner = "stalwart-mail";
      };
      files."public-key".secret = false;
      runtimeInputs = [ pkgs.openssl ];
      script = ''
        openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 > "$out/private-key"
        openssl rsa -in "$out/private-key" -pubout -outform DER 2>/dev/null \
          | openssl base64 -A > "$out/public-key"
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

    stalwart-oidc = {
      files."client-secret" = {
        secret = true;
        owner = "stalwart-mail";
      };
      runtimeInputs = [ pkgs.openssl ];
      script = ''
        openssl rand -base64 32 | tr -d '\n' > "$out/client-secret"
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

      signature = {
        ed25519 = {
          private-key = "%{file:${
            config.clan.core.vars.generators.stalwart-dkim-ed25519.files."private-key".path
          }}%";
          domain = baseDomain;
          selector = dkimSelectorEd25519;
          algorithm = "ed25519-sha256";
          canonicalization = "relaxed/relaxed";
          headers = [
            "From"
            "To"
            "Cc"
            "Date"
            "Subject"
            "Message-ID"
            "In-Reply-To"
            "References"
            "MIME-Version"
            "Content-Type"
          ];
          set-body-length = false;
          report = true;
        };

        rsa = {
          private-key = "%{file:${
            config.clan.core.vars.generators.stalwart-dkim-rsa.files."private-key".path
          }}%";
          domain = baseDomain;
          selector = dkimSelectorRsa;
          algorithm = "rsa-sha256";
          canonicalization = "relaxed/relaxed";
          headers = [
            "From"
            "To"
            "Cc"
            "Date"
            "Subject"
            "Message-ID"
            "In-Reply-To"
            "References"
            "MIME-Version"
            "Content-Type"
          ];
          set-body-length = false;
          report = true;
        };
      };

      auth.dkim.sign = [
        {
          "if" = "listener != 'smtp'";
          "then" = "['ed25519', 'rsa']";
        }
        { "else" = false; }
      ];

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
        directory = "internal";
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

      directory.authentik = {
        type = "oidc";
        url = "https://auth.${baseDomain}/application/o/stalwart-mail/.well-known/openid-configuration";
        timeout = "15s";

        oauth = {
          client-id = "stalwart-mail";
          client-secret = "%{file:${
            config.clan.core.vars.generators.stalwart-oidc.files."client-secret".path
          }}%";
        };

        attributes = {
          username = "preferred_username";
          email = "email";
          name = "name";
          groups = "groups";
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
              "then" = "'internal'";
            }
            { "else" = false; }
          ];
        };

        timeout = "5m";
        transfer-limit = "262144000";
        duration = "10m";
      };

      queue.notify = [
        {
          "if" = "rcpt_domain = '${baseDomain}'";
          "then" = "[orcpt]";
        }
        { "else" = "[]"; }
      ];

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

  # Grant stalwart access to nginx ACME certs and SOPS secrets
  users.users.stalwart-mail.extraGroups = [ "acme" ];

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
