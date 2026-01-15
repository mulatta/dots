{ lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      yazi-plugins =
        let
          plugins = with pkgs.yaziPlugins; {
            inherit chmod full-border toggle-pane diff rsync miller starship glow git piper;
          };
        in
        pkgs.runCommand "yazi-plugins" { } ''
          mkdir -p $out/share/yazi/plugins
          ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: pkg: ''
            ln -s ${pkg} $out/share/yazi/plugins/${name}.yazi
          '') plugins)}
        '';
    in
    {
      packages.yazi-plugins = yazi-plugins;

      packages.yazi = pkgs.callPackage ./yazi-standalone.nix {
        inherit yazi-plugins;
        yazi = pkgs.yazi;
      };
    };
}
