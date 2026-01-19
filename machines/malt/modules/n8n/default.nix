{
  self,
  config,
  pkgs,
  ...
}:
let
  clanLib = self.inputs.clan-core.lib;
  wgPrefix = clanLib.getPublicValue {
    flake = config.clan.core.settings.directory;
    machine = "taps";
    generator = "wireguard-network-wireguard";
    file = "prefix";
  };
  maltSuffix = config.clan.core.vars.generators.wireguard-network-wireguard.files.suffix.value;
  maltWgIP = "${wgPrefix}:${maltSuffix}";

  n8nDomain = "n8n.mulatta.io";

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
  services.n8n = {
    enable = true;
    openFirewall = false;
    environment = {
      N8N_HOST = maltWgIP;
      N8N_PORT = "5678";
      GENERIC_TIMEZONE = "Asia/Seoul";
      N8N_VERSION_NOTIFICATIONS_ENABLED = "false";
      N8N_DIAGNOSTICS_ENABLED = "false";
      N8N_EDITOR_BASE_URL = "https://${n8nDomain}";
      WEBHOOK_URL = "https://${n8nDomain}";

      # PostgreSQL database configuration
      DB_TYPE = "postgresdb";
      DB_POSTGRESDB_HOST = "/run/postgresql";
      DB_POSTGRESDB_DATABASE = "n8n";
      DB_POSTGRESDB_USER = "n8n";

      # Executions pruning
      EXECUTIONS_DATA_PRUNE = "true";
      EXECUTIONS_DATA_MAX_AGE = "336"; # 2 weeks in hours

      # Forward-auth hooks configuration
      EXTERNAL_HOOK_FILES = "${hooksFile}";
      N8N_FORWARD_AUTH_HEADER = "X-Auth-Request-Email";
      N8N_SSO_HOSTNAME = n8nDomain;
    };
  };

  # PostgreSQL database for n8n
  services.postgresql.ensureDatabases = [ "n8n" ];
  services.postgresql.ensureUsers = [
    {
      name = "n8n";
      ensureDBOwnership = true;
    }
  ];

  # Ensure n8n starts after PostgreSQL
  systemd.services.n8n = {
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
  };

  networking.firewall.interfaces."wireguard".allowedTCPPorts = [ 5678 ];
}
