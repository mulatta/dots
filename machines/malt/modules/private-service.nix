{
  config,
  self,
  ...
}:
let
  mediaDir = "/srv/media/job-01";
  vars = config.clan.core.vars.generators;
  # Gitea is served by cask's sshd, so its host key is cask's.
  giteaKnownHosts = builtins.toFile "gitea-known-hosts" ''
    git.mulatta.io ${builtins.readFile ../../../vars/per-machine/cask/openssh/ssh.id_ed25519.pub/value}
  '';
in
{
  imports = [ self.inputs.flakelet.nixosModules.flakelet ];

  clan.core.vars.generators.ntfy-job-01 = {
    files.credential.secret = true;
    prompts.token = {
      description = "ntfy token (tk_…) issued as job-01 in the web UI";
      type = "hidden";
    };
    script = ''
      printf ':' > "$out/credential"
      tr -d '\r\n' < "$prompts/token" >> "$out/credential"
      printf '\n' >> "$out/credential"
    '';
  };

  # Register the public key in Gitea with read-only access.
  clan.core.vars.generators.flakelet-deploy-key = {
    files.key = {
      secret = true;
      owner = "flakelet";
    };
    files."key.pub".secret = false;
    runtimeInputs = [ config.programs.ssh.package ];
    script = ''
      ssh-keygen -q -t ed25519 -N "" -C "flakelet@malt" -f "$out/key"
    '';
  };

  users.users.job-01 = {
    # Preserve existing media ownership.
    uid = 950;
    isSystemUser = true;
    group = "media";
  };

  systemd.tmpfiles.rules = [ "d ${mediaDir} 2750 job-01 media -" ];

  services.flakelets = {
    enable = true;
    credentials = {
      sshKeyFile = vars.flakelet-deploy-key.files.key.path;
      sshKnownHostsFile = giteaKnownHosts;
    };
    services.job-01 = {
      flake = "git+ssh://gitea@git.mulatta.io/mulatta/private-services?ref=main";
      output = "flakelets.job-01";
      autoUpdate.enable = false;
      settings = {
        inherit mediaDir;
        browserUnits = [ "podman-neko.service" ];
        triggerUrl = "https://ntfy.mulatta.io/job-01";
        reportUrl = "https://ntfy.mulatta.io/automation";
        ntfyCredentialFile = vars.ntfy-job-01.files.credential.path;
      };
    };
  };
}
