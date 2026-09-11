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
          extraSpecialArgs = {
            inherit self system;
            inputs = self.inputs;
          };
          modules = [
            {
              imports = extraModules ++ [
                ./common.nix
                inputs.sops-nix.homeManagerModules.sops
                inputs.nix-index-database.homeModules.nix-index
                { programs.nix-index-database.comma.enable = true; }
              ];
            }
          ];
        };
    in
    {
      apps.pre-stow-mutable =
        let
          files = [
            ".config/openlogi/config.toml"
            ".prime/agent/settings.json"
          ];
        in
        {
          type = "app";
          program = "${
            pkgs.writeShellApplication {
              name = "pre-stow-mutable";
              runtimeInputs = [ pkgs.coreutils ];
              text = ''
                umask 077
                for relative in ${lib.escapeShellArgs files}; do
                  source="$HOME/dots/home/$relative"
                  target="$HOME/$relative"
                  [[ -f "$source" ]] || continue

                  if [[ -L "$target" ]]; then
                    # Only detach links owned by this dotfiles checkout.
                    [[ -f "$target" ]] || continue
                    [[ "$(readlink -f "$target")" == "$(readlink -f "$source")" ]] || continue
                    state="''${XDG_STATE_HOME:-$HOME/.local/state}/pre-stow-mutable"
                    mkdir -p "$state"
                    backup=$(mktemp "$state/$(basename "$target").XXXXXXXX")
                    cp -L -- "$target" "$backup"
                    temporary=$(mktemp "$(dirname "$target")/.pre-stow-mutable.XXXXXXXX")
                    cp -- "$backup" "$temporary"
                    # An app may have replaced the link while it was being copied.
                    if [[ -L "$target" ]] && [[ "$(readlink -f "$target")" == "$(readlink -f "$source")" ]]; then
                      mv -T -- "$temporary" "$target"
                    else
                      rm -- "$temporary"
                    fi
                  elif [[ ! -e "$target" ]]; then
                    mkdir -p "$(dirname "$target")"
                    temporary=$(mktemp "$(dirname "$target")/.pre-stow-mutable.XXXXXXXX")
                    cp -- "$source" "$temporary"
                    # Publish without overwriting a file created concurrently.
                    ln -T -- "$temporary" "$target" || {
                      rm -- "$temporary"
                      exit 1
                    }
                    rm -- "$temporary"
                  fi
                done
              '';
            }
          }/bin/pre-stow-mutable";
        };

      apps.stow-dotfiles = {
        type = "app";
        program = "${
          pkgs.writeShellApplication {
            name = "stow-dotfiles";
            runtimeInputs = [ pkgs.stow ];
            text = ''
              if [[ ! -d "$HOME/dots/home" ]]; then
                exit 0
              fi

              exec stow \
                -d "$HOME/dots" \
                -t "$HOME" \
                --restow \
                --no-folding \
                home
            '';
          }
        }/bin/stow-dotfiles";
      };

      apps.hm = {
        type = "app";
        program = "${pkgs.writeShellScriptBin "hm" ''
          set -euo pipefail
          export PATH=${
            lib.makeBinPath [
              pkgs.coreutils
              pkgs.findutils
              pkgs.unixtools.hostname
              pkgs.nixVersions.latest
              inputs.home-manager.packages.${pkgs.stdenv.hostPlatform.system}.home-manager
            ]
          }
          declare -A profiles=(
            ["rhesus"]="macos"
            ["psi"]="psi"
            ["malt"]="malt"
          )
          host=$(hostname -s)
          profile=''${profiles[$host]:-base}

          if [[ "''${1:-}" == "profile" ]]; then
            echo "$profile"
            exit 0
          fi

          if [[ "''${1:-}" == "switch" ]]; then
            echo "==> Preparing mutable dotfiles..."
            ${config.apps.pre-stow-mutable.program}
            echo "==> Stowing dotfiles..."
            ${config.apps.stow-dotfiles.program}
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

          echo "==> Preparing mutable dotfiles..."
          ${config.apps.pre-stow-mutable.program}
          echo "==> Stowing dotfiles..."
          ${config.apps.stow-dotfiles.program}

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
        macos = mkHomeConfig { extraModules = [ ./macos.nix ]; };
      }
      // lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
        psi = mkHomeConfig { extraModules = [ ./psi.nix ]; };
        malt = mkHomeConfig { extraModules = [ ./malt.nix ]; };
      };
    };
}
