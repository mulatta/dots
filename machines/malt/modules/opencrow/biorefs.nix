{
  config,
  pkgs,
  self,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  skillz = self.inputs.skillz;
  skillzPkgs = skillz.packages.${system};
  biorefsConfig = (pkgs.formats.json { }).generate "biorefs-cli-config.json" {
    email = "noa@mulatta.io";
  };
  zhostConfig = (pkgs.formats.json { }).generate "zhost-cli-config.json" {
    base_url = "https://zotero.mulatta.io";
    api_key_command = "rbw get zhost-api-key";
    user_id = 1;
  };
in
{
  clan.core.vars.generators.opencrow-zhost = {
    files.zhost-api-key.secret = true;

    prompts.zhost-api-key = {
      description = "zhost API key for OpenCrow Zotero filing";
      type = "hidden";
    };

    script = ''
      cp "$prompts/zhost-api-key" "$out/zhost-api-key"
    '';
  };

  services.opencrow.credentialFiles."zhost-api-key" =
    config.clan.core.vars.generators.opencrow-zhost.files.zhost-api-key.path;

  services.opencrow.rbwEntries."zhost-api-key" = "zhost-api-key";

  services.opencrow.skills.biorefs-cli = "${skillz}/biorefs-cli/skills";
  services.opencrow.skills.paperfetch-cli = "${skillz}/paperfetch-cli/skills";
  services.opencrow.skills.zhost-cli = "${skillz}/zhost-cli/skills";

  services.opencrow.extraPackages = [
    skillzPkgs.biorefs-cli
    skillzPkgs.paperfetch-cli
    skillzPkgs.zhost-cli
  ];

  containers.opencrow.config.systemd.tmpfiles.rules = [
    "d /var/lib/opencrow/.config/biorefs-cli 0750 opencrow opencrow -"
    "d /var/lib/opencrow/.cache/biorefs-cli 0750 opencrow opencrow -"
    "L+ /var/lib/opencrow/.config/biorefs-cli/config.json - - - - ${biorefsConfig}"
    "d /var/lib/opencrow/.config/paperfetch-cli 0750 opencrow opencrow -"
    "d /var/lib/opencrow/.cache/paperfetch-cli 0750 opencrow opencrow -"
    "d /var/lib/opencrow/.config/zhost-cli 0750 opencrow opencrow -"
    "d /var/lib/opencrow/.cache/zhost-cli 0750 opencrow opencrow -"
    "L+ /var/lib/opencrow/.config/zhost-cli/config.json - - - - ${zhostConfig}"
  ];
}
