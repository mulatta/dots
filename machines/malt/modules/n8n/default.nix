{
  self,
  config,
  pkgs,
  ...
}:
let
  wgPrefix = self.lib.wgPrefix;
  maltSuffix = config.clan.core.vars.generators.wireguard-network-wireguard.files.suffix.value;
  maltWgIP = "${wgPrefix}:${maltSuffix}";

  n8nDomain = "n8n.mulatta.io";
  n8nApiDomain = "n8n-api.mulatta.io";

  # Forward-auth hooks for oauth2-proxy header-based authentication
  hooksFile = pkgs.writeText "n8n-hooks.js" ''
    const { resolve } = require('path');
    const fs = require('fs');

    const n8nBasePath = '${pkgs.n8n}/lib/n8n';
    const pnpmDir = resolve(n8nBasePath, 'node_modules/.pnpm');
    const routerDir = fs.readdirSync(pnpmDir).find(dir => dir.startsWith('router@'));

    const Layer = require(resolve(pnpmDir, routerDir, 'node_modules/router/lib/layer'));
    const { issueCookie } = require(resolve(n8nBasePath, 'packages/cli/dist/auth/jwt'));

    const ignoreAuthRegexp = /^\/(assets|healthz|webhook|rest\/oauth2-credential)/
    module.exports = {
        n8n: {
            ready: [
                async function ({ app }, config) {
                    const { stack } = app.router
                    const index = stack.findIndex((l) => l.name === 'cookieParser')
                    stack.splice(index + 1, 0, new Layer('/', {
                        strict: false,
                        end: false
                    }, async (req, res, next) => {
                        if (ignoreAuthRegexp.test(req.url)) return next()
                        if (!config.get('userManagement.isInstanceOwnerSetUp', false)) return next()
                        if (req.cookies?.['n8n-auth']) return next()
                        if (!process.env.N8N_FORWARD_AUTH_HEADER) return next()

                        // SECURITY: Only enable header-based auth for specific hostname
                        const allowedHost = process.env.N8N_SSO_HOSTNAME;
                        if (req.headers.host !== allowedHost) return next()

                        const email = req.headers[process.env.N8N_FORWARD_AUTH_HEADER.toLowerCase()]
                        if (!email) return next()
                        const user = await this.dbCollections.User.findOneBy({email})
                        if (!user) {
                            res.statusCode = 401
                            res.end(`User ${"$"}{email} not found, please have an admin invite the user first.`)
                            return
                        }
                        if (!user.role) {
                            user.role = {}
                        }
                        issueCookie(res, user)
                        return next()
                    }))
                },
            ],
        },
    }
  '';
in
{
  imports = [
    self.inputs.n8n-nodes.nixosModules.default
    ./provisioning.nix
  ];

  n8n-nodes.enableAll = true;

  # Shared auth token between n8n (task broker) and the task-runner launcher.
  # Required by the module assertion when taskRunners.enable = true.
  clan.core.vars.generators.n8n-task-runner-auth = {
    files.token.secret = true;
    runtimeInputs = [ pkgs.openssl ];
    # Strip trailing newline — n8n reads the whole file as the token and
    # warns "contains leading or trailing whitespace" otherwise.
    script = ''
      openssl rand -hex 32 | tr -d '\n' > "$out/token"
    '';
  };

  clan.core.vars.generators.n8n-nextcloud-webdav = {
    files.password.secret = true;

    prompts.password = {
      description = "Nextcloud app password for n8n WebDAV uploads";
      type = "hidden";
    };

    script = ''
      tr -d '\n' < "$prompts/password" > "$out/password"
    '';
  };

  services.n8n = {
    enable = true;
    openFirewall = false;
    customNodes = builtins.attrValues self.inputs.n8n-nodes.packages.${pkgs.stdenv.hostPlatform.system};
    environment = {
      N8N_HOST = maltWgIP;
      N8N_EDITOR_BASE_URL = "https://${n8nDomain}";
      WEBHOOK_URL = "https://${n8nApiDomain}";

      # PostgreSQL database configuration
      DB_TYPE = "postgresdb";
      DB_POSTGRESDB_HOST = "/run/postgresql";
      DB_POSTGRESDB_DATABASE = "n8n";
      DB_POSTGRESDB_USER = "n8n";

      # Executions pruning
      EXECUTIONS_DATA_PRUNE = "true";
      EXECUTIONS_DATA_MAX_AGE = "336"; # 2 weeks in hours

      # Enable Execute Command node (disabled by default since n8n 2.0)
      NODES_EXCLUDE = "[]";

      # Forward-auth hooks configuration
      EXTERNAL_HOOK_FILES = "${hooksFile}";
      N8N_FORWARD_AUTH_HEADER = "X-Auth-Request-Email";
      N8N_SSO_HOSTNAME = n8nDomain;

      # External task-runner mode: n8n exposes a broker on 127.0.0.1:5679
      # and the launcher (separate systemd unit) connects with this token.
      N8N_RUNNERS_AUTH_TOKEN_FILE =
        config.clan.core.vars.generators.n8n-task-runner-auth.files.token.path;

      NEXTCLOUD_WEBDAV_BASE_URL = "https://cloud.mulatta.io/remote.php/dav";
      NEXTCLOUD_WEBDAV_USER = "seungwon";
      NEXTCLOUD_UPLOAD_NODE_BINARY = "${pkgs.nodejs}/bin/node";
    };

    # Run Code nodes in sandboxed runner processes (javascript + python,
    # defaulted by the module). Broker listens on 127.0.0.1:5679.
    taskRunners.enable = true;
  };

  # PostgreSQL database for n8n
  services.postgresql.ensureDatabases = [ "n8n" ];
  services.postgresql.ensureUsers = [
    {
      name = "n8n";
      ensureDBOwnership = true;
    }
  ];

  # The OpenCrow node writes to the trigger FIFO from task runners, not only
  # the main process.
  systemd.services.n8n = {
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
    serviceConfig = {
      SupplementaryGroups = [ "opencrow" ];
      LoadCredential = [
        "nextcloud-webdav-password:${config.clan.core.vars.generators.n8n-nextcloud-webdav.files.password.path}"
      ];
    };
  };

  systemd.services.n8n-task-runner.serviceConfig = {
    SupplementaryGroups = [ "opencrow" ];
    LoadCredential = [
      "nextcloud-webdav-password:${config.clan.core.vars.generators.n8n-nextcloud-webdav.files.password.path}"
    ];
  };

  networking.firewall.interfaces."wireguard".allowedTCPPorts = [ 5678 ];
}
