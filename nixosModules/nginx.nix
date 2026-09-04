{ lib, ... }:
let
  naruOnly = ''
    allow 10.208.0.0/12;
    allow fdec:ca5f::/32;
    deny all;
  '';

  securityHeaders = frameOptions: ''
    add_header X-Frame-Options "${frameOptions}" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
  '';
in
{
  options.services.nginx.virtualHosts = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, config, ... }:
        let
          serverName = if config.serverName != null then config.serverName else name;
          serverNames = [ serverName ] ++ config.serverAliases;
          naruHost = lib.all (lib.hasSuffix ".n") serverNames;
        in
        {
          options.mulatta.securityHeaders = lib.mkOption {
            type = lib.types.nullOr (
              lib.types.enum [
                "deny"
                "sameorigin"
              ]
            );
            default = null;
            description = "Opt-in response security-header policy.";
          };

          config.extraConfig = lib.mkMerge [
            (lib.mkIf (config.mulatta.securityHeaders != null) (
              lib.mkBefore (
                securityHeaders
                  {
                    deny = "DENY";
                    sameorigin = "SAMEORIGIN";
                  }
                  .${config.mulatta.securityHeaders}
              )
            ))

            (lib.mkIf naruHost (lib.mkAfter naruOnly))
          ];
        }
      )
    );
  };
}
