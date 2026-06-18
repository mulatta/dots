{
  config,
  pkgs,
  self,
  ...
}:
let
  wgPrefix = self.lib.wgPrefix;
  maltWgIP = "${wgPrefix}:${config.clan.core.vars.generators.wireguard-network-wireguard.files.suffix.value}";
  n8nApiUrl = "http://[${maltWgIP}]:5678";
  restateIngressUrl = "http://[${maltWgIP}]:8081";

  system = pkgs.stdenv.hostPlatform.system;

  n8nProvision = pkgs.callPackage ../../pkgs/n8n-provision {
    n8nCli = self.inputs.skillz.packages.${system}.n8n-cli;
  };

  n8nCredentialDeclarations = pkgs.writeText "n8n-credential-declarations.json" (
    builtins.toJSON [
      {
        kind = "httpHeaderAuth";
        name = "n8n-hooks-token";
        tokenFile = "n8n-hooks-token";
      }
      {
        kind = "httpBasicAuth";
        name = "miniflux-webhook-basic";
        user = "miniflux";
        passwordFile = "miniflux-webhook-basic-password";
      }
      {
        kind = "httpHeaderAuth";
        name = "miniflux-api";
        tokenFile = "miniflux-api-token";
        headerName = "X-Auth-Token";
        valuePrefix = "";
        allowedHttpRequestDomains = "domains";
        allowedDomains = "rss.mulatta.io";
      }
      {
        kind = "httpHeaderAuth";
        name = "vikunja-api";
        tokenFile = "vikunja-api-token";
        allowedHttpRequestDomains = "domains";
        allowedDomains = "tasks.mulatta.io";
      }
      {
        kind = "httpHeaderAuth";
        name = "linkwarden-api";
        tokenFile = "linkwarden-api-token";
        allowedHttpRequestDomains = "domains";
        allowedDomains = "links.mulatta.io";
      }
      {
        kind = "restateApi";
        name = "restate-ingress";
        baseUrl = restateIngressUrl;
      }
    ]
  );

  n8nApiEnvironment = ''
    export N8N_API_URL=${builtins.toJSON n8nApiUrl}
    N8N_API_KEY="$(cat "$CREDENTIALS_DIRECTORY/n8n-api-key")"
    export N8N_API_KEY
  '';

  waitForN8n = ''
    for attempt in $(seq 1 120); do
      if curl \
        --fail \
        --silent \
        --show-error \
        --max-time 2 \
        --header "X-N8N-API-KEY: $N8N_API_KEY" \
        "$N8N_API_URL/api/v1/credentials" >/dev/null; then
        break
      fi
      if [ "$attempt" -eq 120 ]; then
        echo "n8n API did not become ready at $N8N_API_URL" >&2
        exit 1
      fi
      sleep 1
    done
  '';

  provisionN8nCredentials = pkgs.writeShellScript "provision-n8n-credentials" ''
    set -euo pipefail

    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT

    export HOME="$tmp"
    ${n8nApiEnvironment}
    ${waitForN8n}

    ${n8nProvision}/bin/n8n-provision credentials ${n8nCredentialDeclarations}
  '';

  n8nWorkflowsRepo = "git@github.com-n8n-workflows:mulatta/n8n-workflows.git";
  n8nProvisionHome = "/var/lib/n8n-provision";
  n8nWorkflowsDir = "${n8nProvisionHome}/n8n-workflows";

  n8nWorkflowsSshConfig = pkgs.writeText "n8n-workflows-ssh-config" ''
    Host github.com-n8n-workflows
      HostName github.com
      User git
      IdentityFile ${n8nProvisionHome}/.ssh/id_ed25519
      IdentitiesOnly yes
      StrictHostKeyChecking accept-new
  '';

  provisionN8nWorkflows = pkgs.writeShellScript "provision-n8n-workflows" ''
    set -euo pipefail

    export HOME=${n8nProvisionHome}

    install -d -m 0700 "$HOME/.ssh"
    install -m 0600 "$CREDENTIALS_DIRECTORY/n8n-workflows-ssh-private-key" "$HOME/.ssh/id_ed25519"
    install -m 0600 ${n8nWorkflowsSshConfig} "$HOME/.ssh/config"

    if [ ! -d ${n8nWorkflowsDir}/.git ]; then
      git clone ${n8nWorkflowsRepo} ${n8nWorkflowsDir}
    else
      git -C ${n8nWorkflowsDir} fetch origin main
      git -C ${n8nWorkflowsDir} reset --hard origin/main
      git -C ${n8nWorkflowsDir} clean -fd
    fi

    ${n8nApiEnvironment}
    ${waitForN8n}
    n8n-cli apply -d ${n8nWorkflowsDir}/definitions
  '';
in
{
  users.groups.n8n-provision = { };
  users.users.n8n-provision = {
    isSystemUser = true;
    group = "n8n-provision";
    home = n8nProvisionHome;
  };

  clan.core.vars.generators.opencrow-n8n = {
    files.n8n-api-key.secret = true;

    prompts.n8n-api-key = {
      description = "n8n API key for host-side provisioning";
      type = "hidden";
    };

    script = ''
      cp "$prompts/n8n-api-key" "$out/n8n-api-key"
    '';
  };

  clan.core.vars.generators.opencrow-n8n-hooks = {
    files.n8n-hooks-token.secret = true;

    prompts.n8n-hooks-token = {
      description = "Shared bearer token for opencrow-owned n8n webhooks";
      type = "hidden";
    };

    script = ''
      cp "$prompts/n8n-hooks-token" "$out/n8n-hooks-token"
    '';
  };

  clan.core.vars.generators.opencrow-n8n-vikunja-api = {
    files.vikunja-api-token.secret = true;

    prompts.vikunja-api-token = {
      description = "Vikunja API token for n8n task workflows";
      type = "hidden";
    };

    script = ''
      cp "$prompts/vikunja-api-token" "$out/vikunja-api-token"
    '';
  };

  clan.core.vars.generators.opencrow-n8n-linkwarden-api = {
    files.linkwarden-api-token.secret = true;

    prompts.linkwarden-api-token = {
      description = "Linkwarden API token for n8n bookmark workflows";
      type = "hidden";
    };

    script = ''
      cp "$prompts/linkwarden-api-token" "$out/linkwarden-api-token"
    '';
  };

  clan.core.vars.generators.opencrow-n8n-workflows-ssh = {
    files.ssh-private-key.secret = true;
    files.ssh-public-key.secret = false;

    runtimeInputs = [ pkgs.openssh ];

    script = ''
      ssh-keygen -t ed25519 -N "" -f "$out/ssh-private-key" -C "opencrow-n8n-workflows@malt"
      ssh-keygen -y -f "$out/ssh-private-key" > "$out/ssh-public-key"
    '';
  };

  systemd.services.n8n-provision-credentials = {
    after = [
      "network-online.target"
      "n8n.service"
    ];
    wants = [
      "network-online.target"
      "n8n.service"
    ];
    wantedBy = [ "multi-user.target" ];
    path = [
      pkgs.coreutils
      pkgs.curl
    ];
    serviceConfig = {
      Type = "oneshot";
      User = "n8n-provision";
      Group = "n8n-provision";
      StateDirectory = "n8n-provision";
      WorkingDirectory = n8nProvisionHome;
      LoadCredential = [
        "n8n-api-key:${config.clan.core.vars.generators.opencrow-n8n.files.n8n-api-key.path}"
        "n8n-hooks-token:${config.clan.core.vars.generators.opencrow-n8n-hooks.files.n8n-hooks-token.path}"
        "miniflux-webhook-basic-password:${config.clan.core.vars.generators.miniflux-webhook.files.n8n-basic-password.path}"
        "miniflux-api-token:${config.clan.core.vars.generators.miniflux-seungwon.files.api-token.path}"
        "vikunja-api-token:${config.clan.core.vars.generators.opencrow-n8n-vikunja-api.files.vikunja-api-token.path}"
        "linkwarden-api-token:${config.clan.core.vars.generators.opencrow-n8n-linkwarden-api.files.linkwarden-api-token.path}"
      ];
    };
    script = ''
      ${provisionN8nCredentials}
    '';
  };

  systemd.services.n8n-provision-workflows = {
    after = [
      "network-online.target"
      "n8n.service"
      "n8n-provision-credentials.service"
    ];
    wants = [
      "network-online.target"
      "n8n.service"
    ];
    requires = [ "n8n-provision-credentials.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [
      pkgs.coreutils
      pkgs.curl
      pkgs.git
      pkgs.openssh
      self.inputs.skillz.packages.${system}.n8n-cli
    ];
    serviceConfig = {
      Type = "oneshot";
      User = "n8n-provision";
      Group = "n8n-provision";
      StateDirectory = "n8n-provision";
      WorkingDirectory = n8nProvisionHome;
      LoadCredential = [
        "n8n-api-key:${config.clan.core.vars.generators.opencrow-n8n.files.n8n-api-key.path}"
        "n8n-workflows-ssh-private-key:${config.clan.core.vars.generators.opencrow-n8n-workflows-ssh.files.ssh-private-key.path}"
      ];
    };
    script = ''
      ${provisionN8nWorkflows}
    '';
  };
}
