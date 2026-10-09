{
  config,
  inputs,
  lib,
  ...
}:
let
  cfg = config.services.paneru;
  label = "com.github.karinushka.paneru";
  # Same override finalPackage applies, minus its shell wrapper, so the signed
  # bundle runs the daemon itself.
  daemon = cfg.package.override (
    if cfg.luaConfig.enable then
      {
        enableLua = true;
        inherit (cfg) lua;
      }
    else
      { enableLua = false; }
  );
  version = builtins.head (lib.splitString "+" daemon.version);
in
{
  imports = [ inputs.paneru.homeModules.paneru ];

  services.paneru.enable = true;

  # Home Manager wraps Nix-store launch agents in /bin/sh. The signed copy is
  # launched directly instead, reusing the upstream agent definition.
  launchd.agents.paneru.enable = lib.mkForce false;
  targets.darwin.signedApps.paneru = {
    program = lib.getExe daemon;
    bundle = "Paneru.app";
    identifier = label;
    # The daemon links LuaJIT from the store.
    entitlements."com.apple.security.cs.disable-library-validation" = true;
    tccServices = [ "Accessibility" ];
    infoPlist = {
      CFBundleDisplayName = "Paneru";
      CFBundleShortVersionString = version;
      CFBundleVersion = version;
      LSMinimumSystemVersion = "12.0";
      LSUIElement = true;
      NSHighResolutionCapable = true;
    };
    launchAgent = {
      inherit label;
      config = removeAttrs config.launchd.agents.paneru.config [
        "Program"
        "ProgramArguments"
      ];
    };
  };
}
