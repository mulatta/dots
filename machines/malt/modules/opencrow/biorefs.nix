{
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
in
{
  services.opencrow.skills.biorefs-cli = "${skillz}/biorefs-cli/skills";

  services.opencrow.extraPackages = [ skillzPkgs.biorefs-cli ];

  containers.opencrow.config.systemd.tmpfiles.rules = [
    "d /var/lib/opencrow/.config/biorefs-cli 0750 opencrow opencrow -"
    "d /var/lib/opencrow/.cache/biorefs-cli 0750 opencrow opencrow -"
    "L+ /var/lib/opencrow/.config/biorefs-cli/config.json - - - - ${biorefsConfig}"
  ];
}
