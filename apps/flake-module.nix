{
  self,
  inputs,
  ...
}:
{
  perSystem =
    {
      pkgs,
      system,
      ...
    }:
    let
      runtimeInputs = with pkgs; [
        gitMinimal
        coreutils
        findutils
        hostname
        inputs.home-manager.packages.${system}.home-manager
      ];
    in
    {
      apps.hm = {
        type = "app";
        program =
          let
            script = pkgs.writeShellApplication {
              name = "hm";
              inherit runtimeInputs;
              text = ''
                # Profile mapping (hostname -> profile)
                declare -A profiles=(
                  ["rhesus"]="seungwon@rhesus"
                  ["mulatta"]="seungwon@mulatta"
                  ["psi"]="seungwon@psi"
                )

                # OS-based fallback
                declare -A os_profiles=(
                  ["Darwin"]="macos"
                  ["Linux"]="desktop"
                )

                host=$(hostname -s)
                user=$(id -un)
                os=$(uname -s)

                # Profile selection priority:
                # 1. hostname-user match
                # 2. hostname match
                # 3. OS-based
                # 4. base (fallback)
                if [[ -v "profiles[$host-$user]" ]]; then
                  profile="''${profiles[$host-$user]}"
                elif [[ -v "profiles[$host]" ]]; then
                  profile="''${profiles[$host]}"
                elif [[ -v "os_profiles[$os]" ]]; then
                  profile="''${os_profiles[$os]}"
                else
                  profile="base"
                fi

                # Special command: show profile
                if [[ "''${1:-}" == "profile" ]]; then
                  echo "$profile"
                  exit 0
                fi

                # Run home-manager (uses legacyPackages.homeConfigurations)
                exec home-manager --option keep-going true --flake "${self}#$profile" "$@"
              '';
            };
          in
          "${script}/bin/hm";
      };

      apps.bootstrap = {
        type = "app";
        program =
          let
            script = pkgs.writeShellApplication {
              name = "bootstrap-dotfiles";
              runtimeInputs = runtimeInputs ++ [ pkgs.bash ];
              text = ''
                DOTFILES_DIR="$HOME/.dotfiles"

                echo "==> Cloning dotfiles..."
                if [[ ! -d "$DOTFILES_DIR" ]]; then
                  git clone "https://github.com/seungwon/dots.git" "$DOTFILES_DIR"
                else
                  echo "    Already exists, pulling latest..."
                  git -C "$DOTFILES_DIR" pull
                fi

                echo "==> Activating home-manager..."
                nix run "$DOTFILES_DIR#hm" -- switch

                echo "==> Done! You may need to restart your shell."
              '';
            };
          in
          "${script}/bin/bootstrap-dotfiles";
      };

      apps.default = self.apps.${system}.hm;
    };
}
