{
  config,
  pkgs,
  ...
}:
{
  networking.naru.ed25519PrivateKeyFile =
    config.clan.core.vars.generators.naru.files.private-key.path;

  services.tincr.networks.naru.extraConfig = "StrictSubnets = yes";

  clan.core.vars.generators.naru = {
    files.private-key = {
      secret = true;
      owner = "root";
      group = "wheel";
      mode = "0400";
    };
    prompts.private-key = {
      description = "Naru Ed25519 private key";
      type = "multiline-hidden";
      persist = true;
    };
    script = ''
      cp "$prompts/private-key" "$out/private-key"
    '';
  };

  environment.systemPackages = [
    (pkgs.writeShellScriptBin "tinc.naru" ''
      exec ${config.services.tincr.networks.naru.package}/bin/tinc \
        --pidfile=/var/run/tincr-naru.pid \
        --config=/etc/tinc/naru "$@"
    '')
  ];
}
