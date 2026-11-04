# agentsview

`services.agentsview` runs [agentsview](https://github.com/kenn-io/agentsview) as a
session archive that collects coding-agent sessions from other machines over SSH.
The package comes from the `llm-agents` input and has no default:

```nix
services.agentsview = {
  enable = true;
  package = self.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.agentsview;
  host = "<wireguard address>";
  authTokenFile = config.clan.core.vars.generators.agentsview.files.auth-token.path;
  sshKeyFile = config.clan.core.vars.generators.agentsview.files.ssh-key.path;
  sshConfig = ''
    Host psi
      HostName psi.example.org
      User seungwon
  '';
  settings.remote_hosts = [
    {
      host = "psi";
      transport = "ssh";
      interval = "15m";
    }
  ];
};
```

agentsview writes `config.toml` itself: it generates `cursor_secret` and stores Settings
page edits there. `settings` is merged over that file on every start, so managed keys win
and the rest survive. Settings page edits to managed keys are lost on restart.

Authentication is a single bearer token; agentsview has no OIDC or user accounts. A
non-loopback `host` requires `authTokenFile`.

SSH sync runs `agentsview` on the remote. Install it there from the same `llm-agents` input
and make sure it is on `PATH` for non-interactive SSH sessions. Otherwise the collector
downloads the matching GitHub release binary and uploads it. Pin remote host keys in
`programs.ssh.knownHosts`; sync uses `BatchMode=yes` and cannot accept a new key.

The module opens no firewall ports; the machine configuration does that per interface.
