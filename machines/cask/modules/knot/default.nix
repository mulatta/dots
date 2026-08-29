{
  self,
  config,
  pkgs,
  ...
}:
let
  ipv4 = config.networking.cask.ipv4.address;
  ipv6 = config.networking.cask.ipv6.address;
  publicZone = pkgs.writeText "mulatta.io.zone" (
    builtins.replaceStrings [ "@SERVICE_IPV4@" "@SERVICE_IPV6@" ] [ ipv4 ipv6 ] (
      builtins.readFile ./mulatta.io.zone
    )
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
      server.listen = [
        "${ipv4}@53"
        "${ipv6}@53"
      ];

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
          file = "${self.inputs.dure.packages.${pkgs.stdenv.hostPlatform.system}.n-zone}";
        }
        {
          domain = "i";
          file = "${self.inputs.dure.packages.${pkgs.stdenv.hostPlatform.system}.i-zone}";
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
