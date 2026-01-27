{ lib, ... }:
{
  perSystem =
    { pkgs, config, ... }:
    let
      yazi-plugins =
        let
          plugins = with pkgs.yaziPlugins; {
            inherit
              chmod
              full-border
              toggle-pane
              diff
              rsync
              miller
              starship
              glow
              git
              piper
              ;
          };
        in
        pkgs.runCommand "yazi-plugins" { } ''
          mkdir -p $out/share/yazi/plugins
          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (name: pkg: ''
              ln -s ${pkg} $out/share/yazi/plugins/${name}.yazi
            '') plugins
          )}
        '';
    in
    {
      packages.yazi-plugins = yazi-plugins;

      # Preview tools for HM installation
      legacyPackages.yazi-preview-tools = pkgs.buildEnv {
        name = "yazi-preview-tools";
        paths = with pkgs; [
          imagemagick
          ffmpegthumbnailer
          unar
          poppler
          glow
        ];
      };

      # Standalone yazi for `nix run` (separate from HM)
      packages.yazi = pkgs.callPackage ./yazi-standalone.nix {
        inherit yazi-plugins;
        inherit (config.legacyPackages) yazi-preview-tools;
        yazi = pkgs.yazi;
      };
    };
}
