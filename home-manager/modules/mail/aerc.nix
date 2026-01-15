# aerc - config managed by stow (home/.config/aerc/)
# This module only provides packages and helper scripts
{
  pkgs,
  ...
}:
let
  open-in-thunderbird = pkgs.writeShellScriptBin "open-in-thunderbird" ''
    tmpfile=$(mktemp).eml
    cat > "$tmpfile"
    ${
      if pkgs.stdenv.isDarwin then
        "/usr/bin/open -a Thunderbird \"$tmpfile\""
      else
        "${pkgs.thunderbird}/bin/thunderbird \"$tmpfile\""
    }
    (sleep 10 && rm -f "$tmpfile") &
  '';
in
{
  home.packages = [
    pkgs.aerc
    pkgs.mblaze
    pkgs.w3m
    open-in-thunderbird
  ];
}
