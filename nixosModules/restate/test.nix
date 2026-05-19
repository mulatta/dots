{ pkgs, ... }:

let
  fakeRestate = pkgs.writeShellScriptBin "restate-server" ''
    echo fake restate-server
  '';

  evaluated = import "${pkgs.path}/nixos/lib/eval-config.nix" {
    system = pkgs.stdenv.hostPlatform.system;
    modules = [
      ./default.nix
      (
        { ... }:
        {
          services.restate = {
            enable = true;
            package = fakeRestate;
            dataDir = "/srv/restate";
            bindAddress = "127.0.0.1:5122";
            ingressBindAddress = "127.0.0.1:18080";
            adminBindAddress = "127.0.0.1:19070";
            settings = {
              cluster-name = "opencrow";
              disable-telemetry = true;
              admin.disable-web-ui = true;
            };
          };

          system.stateVersion = "25.11";
        }
      )
    ];
  };

  config = evaluated.config;
  service = config.systemd.services.restate;
  serviceConfig = service.serviceConfig;
  configFile = service.environment.RESTATE_CONFIG;
in
assert pkgs.lib.assertMsg (
  serviceConfig.ExecStart == "${fakeRestate}/bin/restate-server"
) "restate service must execute restate-server from configured package";
assert pkgs.lib.assertMsg (
  serviceConfig.User == "restate"
) "restate service must run as restate user";
assert pkgs.lib.assertMsg (
  serviceConfig.Group == "restate"
) "restate service must run as restate group";
assert pkgs.lib.assertMsg (
  serviceConfig.WorkingDirectory == "/srv/restate"
) "restate service must work from dataDir";
assert pkgs.lib.assertMsg (
  serviceConfig.ReadWritePaths == [ "/srv/restate" ]
) "restate service must only write to dataDir";
pkgs.runCommand "restate-module-test" { } ''
  grep -Fx 'base-dir = "/srv/restate"' ${configFile}
  grep -Fx 'bind-address = "127.0.0.1:5122"' ${configFile}
  grep -Fx 'cluster-name = "opencrow"' ${configFile}
  grep -Fx 'disable-telemetry = true' ${configFile}
  grep -Fx 'bind-address = "127.0.0.1:19070"' ${configFile}
  grep -Fx 'disable-web-ui = true' ${configFile}
  grep -Fx 'bind-address = "127.0.0.1:18080"' ${configFile}
  touch $out
''
