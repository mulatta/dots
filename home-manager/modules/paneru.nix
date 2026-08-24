{
  config,
  inputs,
  lib,
  pkgs,
  self,
  ...
}:
let
  label = "com.github.karinushka.paneru";
  package = self.packages.${pkgs.stdenv.hostPlatform.system}.paneru-app;
  executable = "${package}/Applications/Paneru.app/Contents/MacOS/paneru";
  agent = pkgs.writeText "${label}.plist" (
    lib.generators.toPlist { escape = true; } {
      Label = label;
      Program = executable;
      KeepAlive = {
        Crashed = true;
        SuccessfulExit = false;
      };
      Nice = -20;
      ProcessType = "Interactive";
      EnvironmentVariables = {
        NO_COLOR = "1";
        XDG_CONFIG_HOME = config.xdg.configHome;
      };
      RunAtLoad = true;
      StandardOutPath = "/tmp/paneru.log";
      StandardErrorPath = "/tmp/paneru.err.log";
    }
  );
in
{
  imports = [ inputs.paneru.homeModules.paneru ];

  services.paneru = {
    enable = true;
    inherit package;
  };

  # Home Manager wraps Nix-store launch agents in /bin/sh. Installing this
  # plist ourselves preserves Paneru.app as the daemon's direct TCC identity.
  launchd.agents.paneru.enable = lib.mkForce false;
  home.activation.setupPaneruLaunchAgent = lib.hm.dag.entryAfter [ "setupLaunchAgents" ] ''
    label=${lib.escapeShellArg label}
    domain="gui/$UID"
    destination="$HOME/Library/LaunchAgents/$label.plist"

    if ! /usr/bin/cmp -s ${agent} "$destination"; then
      if /bin/launchctl print "$domain/$label" >/dev/null 2>&1; then
        if [[ "$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d. -f1)" -ge 26 ]]; then
          run /bin/launchctl bootout --wait "$domain/$label"
        else
          run /bin/launchctl bootout "$domain/$label"
          run /bin/sleep 1
        fi
      fi
      run /bin/mkdir -p "$HOME/Library/LaunchAgents"
      run /usr/bin/install -m 444 ${agent} "$destination"
    fi

    if ! /bin/launchctl print "$domain/$label" >/dev/null 2>&1; then
      run /bin/launchctl bootstrap "$domain" "$destination"
    fi
  '';
}
