{
  pkgs,
  wgLib,
  securityHeadersConfig,
  ...
}:
let
  domain = "chat.mulatta.io";
  malt = wgLib.wgHost "malt";
  oauth2 = "http://127.0.0.1:4183";

  proxyAuthHeaders = ''
    proxy_set_header X-User $user;
    proxy_set_header X-Email $email;
  '';
in
{
  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    enableACME = true;

    extraConfig = securityHeadersConfig + ''
      auth_request /oauth2/auth;
      error_page 401 = @redirectToOauth2ProxyLogin;

      auth_request_set $user $upstream_http_x_auth_request_user;
      auth_request_set $email $upstream_http_x_auth_request_email;
      auth_request_set $auth_cookie $upstream_http_set_cookie;
      add_header Set-Cookie $auth_cookie;
    '';

    locations = {
      "/oauth2/" = {
        proxyPass = oauth2;
        extraConfig = ''
          auth_request off;
          proxy_set_header X-Scheme $scheme;
          proxy_set_header X-Auth-Request-Redirect $scheme://$host$request_uri;
        '';
      };

      "= /oauth2/auth" = {
        proxyPass = "${oauth2}/oauth2/auth";
        extraConfig = ''
          auth_request off;
          proxy_set_header X-Scheme $scheme;
          proxy_set_header Content-Length "";
          proxy_pass_request_body off;
        '';
      };

      "@redirectToOauth2ProxyLogin" = {
        return = "307 https://${domain}/oauth2/start?rd=$scheme://$host$request_uri";
        extraConfig = ''
          auth_request off;
        '';
      };

      "^~ /weechat" = {
        proxyPass = "http://${malt.url}:4242";
        proxyWebsockets = true;
        extraConfig = proxyAuthHeaders + ''
          proxy_read_timeout 3600s;
          proxy_send_timeout 3600s;
        '';
      };

      "/" = {
        root = pkgs.glowing-bear;
      };
    };
  };
}
