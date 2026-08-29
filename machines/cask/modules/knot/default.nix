{
  self,
  config,
  pkgs,
  ...
}:
let
  durePackages = self.inputs.dure.packages.${pkgs.stdenv.hostPlatform.system};
  publicIPv4 = config.networking.cask.ipv4.address;
  publicZone = pkgs.writeText "mulatta.io.zone" (
    builtins.replaceStrings [ "@SERVICE_IP@" ] [ publicIPv4 ] (builtins.readFile ./mulatta.io.zone)
  );
in
{
  services.knot = {
    enable = true;
    settings = {
      server.listen = [ "${publicIPv4}@53" ];

      template = [
        {
          id = "default";
          semantic-checks = "on";
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
        }
      ];
    };
  };
}
