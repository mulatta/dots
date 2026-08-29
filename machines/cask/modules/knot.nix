{
  self,
  config,
  pkgs,
  ...
}:
let
  durePackages = self.inputs.dure.packages.${pkgs.stdenv.hostPlatform.system};
  publicIPv4 = config.networking.cask.ipv4.address;
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

      # These undelegated zones establish cask as a reachable shadow primary
      # before registrar or client resolver changes make answers authoritative.
      zone = [
        {
          domain = "n";
          file = "${durePackages.n-zone}";
        }
        {
          domain = "i";
          file = "${durePackages.i-zone}";
        }
      ];
    };
  };
}
