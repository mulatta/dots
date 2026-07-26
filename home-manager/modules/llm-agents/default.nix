{
  inputs,
  self,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  aiPkgs = inputs.llm-agents.packages.${system};
  # herdr 0.7.5 drops kitty-protocol printable keys (#1746); build fixed master
  # commit on Linux until the next release. Darwin uses the upstream binary.
  herdrPackage =
    if pkgs.stdenv.isDarwin then
      aiPkgs.herdr
    else
      aiPkgs.herdr.overrideAttrs (_old: rec {
        version = "0.7.5-unstable-2026-07-23";
        src = pkgs.fetchFromGitHub {
          owner = "ogulcancelik";
          repo = "herdr";
          rev = "e7fc85bfdb51f89488430adbfe5bbced3be79c2f";
          hash = "sha256-m5jEDImymgu84HXgeeLjOz6KhWP5+is8RNA5Ww+z5BI=";
        };
        cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
          inherit src;
          name = "herdr-${version}-vendor";
          hash = "sha256-lWnc0Ka0hp7bbm+dkKKj22Dbk+Cwrld86romXs3lzBs=";
        };
        # versionCheckHook compares against the pre-release Cargo version.
        doInstallCheck = false;
      });
in
{
  disabledModules = [ "programs/herdr.nix" ];

  imports = [
    inputs.skillz.homeModules.default
    ./packages.nix
    ./pi.nix
    ./skills.nix
    ../herdr
  ];

  _module.args.selfPkgs = self.packages.${system};

  programs.herdr = {
    enable = true;
    package = herdrPackage;
    plugins = [
      self.packages.${system}.herdr-autoname
      self.packages.${system}.herdr-sesh
    ];
  };
  _module.args.llmAgents = {
    inherit system;
    inherit (inputs) pi-agent-extensions;
    inherit aiPkgs herdrPackage;
    skillzPkgs = inputs.skillz.packages.${system};
    claudeCode = self.packages.${system}.claude-code;
  };
}
