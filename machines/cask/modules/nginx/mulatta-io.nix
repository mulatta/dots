{
  securityTxtFile,
  openpgpkeyDir,
  nostrJsonFile,
  ...
}:
{
  services.nginx.virtualHosts = {
    "mulatta.io" = {
      forceSSL = true;
      enableACME = true;
      locations."= /.well-known/security.txt" = {
        alias = "${securityTxtFile}";
        extraConfig = ''
          default_type "text/plain; charset=utf-8";
        '';
      };
      # WKD (RFC 7929) stub — policy file only today. Drop real key
      # files into openpgpkeyDir and redeploy once a key is generated.
      locations."^~ /.well-known/openpgpkey/" = {
        alias = "${openpgpkeyDir}/";
        extraConfig = ''
          default_type "application/octet-stream";
        '';
      };
      # NIP-05: served from nix-generated file (nip05.nix) so adding an
      # agent only requires a clan vars entry + rebuild, not a homepage
      # repo edit. CORS required for cross-origin fetch by Nostr clients.
      locations."= /.well-known/nostr.json" = {
        alias = "${nostrJsonFile}";
        extraConfig = ''
          add_header Access-Control-Allow-Origin "*" always;
          add_header Cache-Control "public, max-age=3600";
          default_type application/json;
        '';
      };
    };

    "www.mulatta.io" = {
      forceSSL = true;
      enableACME = true;
      globalRedirect = "mulatta.io";
    };
  };
}
