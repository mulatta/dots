{
  self,
  config,
  pkgs,
  ...
}:
let
  durePackages = self.inputs.dure.packages.${pkgs.stdenv.hostPlatform.system};
  ipv4 = config.networking.cask.ipv4.address;
  publicZone = pkgs.writeText "mulatta.io.zone" (
    builtins.replaceStrings [ "@SERVICE_IP@" ] [ ipv4 ] (builtins.readFile ./mulatta.io.zone)
  );
in
{
  sops.secrets."knot-keys.conf" = {
    owner = "knot";
    restartUnits = [ "knot.service" ];
  };

  services.knot = {
    enable = true;
    keyFiles = [ config.sops.secrets."knot-keys.conf".path ];
    settings = {
      server.listen = [ "${ipv4}@53" ];

      remote = [
        {
          id = "he_ip4";
          address = "216.218.130.2";
        }
      ];

      acl = [
        {
          id = "he_acl";
          key = "52cc052c-fb0c-444c-9056-17c32c18d9bb.uniq.mulatta.io";
          action = "transfer";
        }
      ];

      template = [
        {
          id = "default";
          semantic-checks = "on";
        }
        {
          id = "master";
          semantic-checks = "on";
          notify = [ "he_ip4" ];
          acl = [ "he_acl" ];
          zonefile-sync = "-1";
          zonefile-load = "difference-no-serial";
          serial-policy = "dateserial";
          journal-content = "all";
        }
      ];

      # Shadow answers establish cask before delegation or resolver changes
      # make these zones part of production resolution.
      zone = [
        {
          domain = "n";
          file = "${durePackages.n-zone}";
        }
        {
          domain = "i";
          file = "${durePackages.i-zone}";
        }
        {
          domain = "mulatta.io";
          file = "${publicZone}";
          template = "master";
        }
      ];
    };
  };
}
