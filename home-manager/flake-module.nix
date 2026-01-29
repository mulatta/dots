{
  self,
  inputs,
  ...
}:
{
  perSystem =
    {
      config,
      pkgs,
      lib,
      system,
      ...
    }:
    let
      mkHomeConfig =
        {
          extraModules ? [ ],
        }:
        inputs.home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            {
              _module.args.self = self;
              _module.args.inputs = self.inputs;
              _module.args.system = system;
              imports = extraModules ++ [
                ./profiles/base.nix
                inputs.sops-nix.homeManagerModules.sops
                inputs.nix-index-database.homeModules.nix-index
                { programs.nix-index-database.comma.enable = true; }
              ];
            }
          ];
        };
    in
    {
      apps.hm = {
        type = "app";
        program = "${pkgs.writeShellScriptBin "hm" ''
          set -euo pipefail
          export PATH=${
            lib.makeBinPath [
              pkgs.coreutils
              pkgs.findutils
              pkgs.hostname
              pkgs.stow
              pkgs.nixVersions.latest
              inputs.home-manager.packages.${pkgs.stdenv.hostPlatform.system}.home-manager
            ]
          }
          declare -A profiles=(
            ["rhesus"]="macos"
            ["psi"]="psi"
            ["malt"]="base"
          )
          host=$(hostname -s)
          profile=''${profiles[$host]:-base}

          if [[ "''${1:-}" == "profile" ]]; then
            echo "$profile"
            exit 0
          fi

          if [[ "''${1:-}" == "switch" ]] && [[ -d "$HOME/dots/home" ]]; then
            echo "==> Stowing dotfiles..."
            stow -d "$HOME/dots" -t "$HOME" --restow --no-folding home
          fi

          echo "==> Running home-manager with profile: $profile"
          home-manager --flake "$HOME/dots#$profile" "$@"
        ''}/bin/hm";
      };

      apps.bootstrap = {
        type = "app";
        program = "${pkgs.writeShellScriptBin "bootstrap" ''
          set -euo pipefail
          export PATH=${
            lib.makeBinPath [
              pkgs.gitMinimal
              pkgs.coreutils
              pkgs.findutils
              pkgs.jq
              pkgs.unixtools.hostname
              pkgs.nixVersions.latest
            ]
          }
          if [[ ! -d "$HOME/dots" ]]; then
            echo "==> Cloning dotfiles..."
            git clone https://github.com/mulatta/dots.git "$HOME/dots"
          else
            echo "==> Dotfiles exist, pulling latest..."
            git -C "$HOME/dots" pull --rebase || true
          fi

          echo "==> Stowing dotfiles..."
          stow -d "$HOME/dots" -t "$HOME" --restow --no-folding home

          echo "==> Activating home-manager..."
          nix run "$HOME/dots#hm" -- switch

          echo "==> Done! You may need to restart your shell."
        ''}/bin/bootstrap";
      };

      apps.default = config.apps.bootstrap;

      legacyPackages.homeConfigurations = {
        base = mkHomeConfig { };
      }
      // lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "aarch64-darwin") {
        macos = mkHomeConfig { extraModules = [ ./profiles/macos.nix ]; };
      }
      //
        lib.optionalAttrs
          (
            pkgs.stdenv.hostPlatform.system == "x86_64-linux"
            || pkgs.stdenv.hostPlatform.system == "aarch64-linux"
          )
          {
            desktop = mkHomeConfig { extraModules = [ ./profiles/desktop.nix ]; };
            psi = mkHomeConfig { extraModules = [ ./profiles/psi.nix ]; };
          };
    };
}
