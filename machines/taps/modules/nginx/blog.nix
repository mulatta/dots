{ securityTxtFile, openpgpkeyDir, ... }:
{
  services.nginx.virtualHosts."blog.mulatta.io" = {
    forceSSL = true;
    enableACME = true;
    root = "/var/lib/radicle-ci/blog/current";
    extraConfig = ''
      if ($block_dotted) { return 404; }
    '';
    # /robots.txt is exempt from the AI UA block so even blocked agents
    # can still read our advisory (Content Signals + Disallow list).
    locations."= /robots.txt".extraConfig = ''
      add_header Cache-Control "public, max-age=3600";
    '';
    locations."= /.well-known/security.txt" = {
      alias = "${securityTxtFile}";
      extraConfig = ''
        default_type "text/plain; charset=utf-8";
      '';
    };
    # WKD (RFC 7929) stub — policy file only today.
    locations."^~ /.well-known/openpgpkey/" = {
      alias = "${openpgpkeyDir}/";
      extraConfig = ''
        default_type "application/octet-stream";
      '';
    };
    locations."/" = {
      tryFiles = "$uri $uri/ /index.html =404";
      extraConfig = ''
        if ($block_ai) {
          return 403;
        }
        add_header Cache-Control "public, max-age=3600";
      '';
    };
  };
}
