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
in
{
  clan.core.vars.generators.opencrow-geo = {
    files = {
      tmap-app-key.secret = true;
      kma-service-key.secret = true;
    };

    prompts = {
      tmap-app-key = {
        description = "TMAP app key for kmap-cli";
        type = "hidden";
      };
      kma-service-key = {
        description = "data.go.kr KMA service key for weather-cli";
        type = "hidden";
      };
    };

    script = ''
      cp "$prompts/tmap-app-key" "$out/tmap-app-key"
      cp "$prompts/kma-service-key" "$out/kma-service-key"
    '';
  };

  services.opencrow.credentialFiles = {
    tmap-app-key = config.clan.core.vars.generators.opencrow-geo.files.tmap-app-key.path;
    kma-service-key = config.clan.core.vars.generators.opencrow-geo.files.kma-service-key.path;
  };

  services.opencrow.rbwEntries = {
    tmap-app-key = "tmap-app-key";
    kma-service-key = "kma-service-key";
  };

  services.opencrow.skills = {
    kmap-cli = "${skillz}/kmap-cli/skills";
    weather-cli = "${skillz}/weather-cli/skills";
  };

  services.opencrow.extraPackages = [
    skillzPkgs.kmap-cli
    skillzPkgs.weather-cli
  ];

  containers.opencrow.config.systemd.tmpfiles.rules = [
    "d /var/lib/opencrow/.config/kmap-cli 0750 opencrow opencrow -"
    ''f /var/lib/opencrow/.config/kmap-cli/config.json 0640 opencrow opencrow - {"tmap_app_key_command":"rbw get tmap-app-key"}''
    "d /var/lib/opencrow/.config/weather-cli 0750 opencrow opencrow -"
    ''f /var/lib/opencrow/.config/weather-cli/config.json 0640 opencrow opencrow - {"service_key_command":"rbw get kma-service-key"}''
  ];
}
