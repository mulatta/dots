{ config, ... }:
{
  networking.naru.ed25519PrivateKeyFile =
    config.clan.core.vars.generators.naru.files.private-key.path;

  services.tincr.networks.naru.extraConfig = "StrictSubnets = yes";

  clan.core.vars.generators.naru = {
    files.private-key = {
      secret = true;
      owner = "root";
      group = "root";
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
}
