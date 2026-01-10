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
      N8N_EDITOR_BASE_URL = "https://n8n.mulatta.io";
      WEBHOOK_URL = "https://n8n.mulatta.io";
      EXTERNAL_HOOK_FILES = "${hooksFile}";
      N8N_FORWARD_AUTH_HEADER = "X-Auth-Request-Email";
      N8N_SSO_HOSTNAME = "n8n.mulatta.io";
    };
  };

  networking.firewall.interfaces."wireguard".allowedTCPPorts = [ 5678 ];
}
