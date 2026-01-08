{
  pkgs,
  config,
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
    pkgs.mblaze
    pkgs.w3m
    open-in-thunderbird
  ];

  programs.aerc = {
    enable = true;
    extraConfig = {
      general = {
        unsafe-accounts-conf = true;
        pgp-provider = "auto";
        disable-ipc = true;
        log-file = "${config.xdg.stateHome}/aerc.log";
      };
      ui = {
        styleset-name = "dracula";
      };
      openers = {
        "text/html" = "${pkgs.w3m}/bin/w3m -T text/html";
        "message/rfc822" =
          if pkgs.stdenv.isDarwin then
            "/usr/bin/open -a Thunderbird"
          else
            "${pkgs.thunderbird}/bin/thunderbird";
        "*" = if pkgs.stdenv.isDarwin then "/usr/bin/open" else "${pkgs.xdg-utils}/bin/xdg-open";
      };
    };
    stylesets.dracula = builtins.readFile "${pkgs.aerc}/share/aerc/stylesets/dracula";
  };

  xdg.configFile."aerc/binds.conf".text = ''
    ${builtins.readFile "${pkgs.aerc}/share/aerc/binds.conf"}

    [messages]
    Q = :quit<Enter>
    <C-o> = :pipe -m open-in-thunderbird<Enter>
    # Override delete to move to Trash (for mbsync sync)
    d = :move Trash<Enter>
    D = :delete<Enter>

    [view]
    <C-o> = :pipe -m open-in-thunderbird<Enter>
    d = :move Trash<Enter>
    D = :delete<Enter>
  '';
}
