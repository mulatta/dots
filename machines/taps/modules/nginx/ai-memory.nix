{
  config,
  pkgs,
  securityHeadersConfig,
  wgLib,
  ...
}:
let
  malt = wgLib.wgHost "malt";
  webDomain = "memory.mulatta.io";
  apiDomain = "memory-api.mulatta.io";
  port = 49374;
  oauth2Port = 4184;
  actorProxyConfig = config.clan.core.vars.generators.ai-memory-actor-proxy.files.nginx-config.path;

  upstreamConfig = ''
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header Connection "";
    proxy_buffering off;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
    client_max_body_size 10M;
  '';
  webProxyConfig = ''
    auth_request /oauth2/auth;
    error_page 401 = @redirectToAiMemoryLogin;

    auth_request_set $memory_actor_user $upstream_http_x_auth_request_user;
    auth_request_set $memory_actor_email $upstream_http_x_auth_request_email;
    auth_request_set $memory_auth_cookie $upstream_http_set_cookie;
    add_header Set-Cookie $memory_auth_cookie always;
    ${securityHeadersConfig}

    # Replace, rather than append, every client-controlled actor header.
    proxy_set_header X-Memory-Actor-User $memory_actor_user;
    proxy_set_header X-Memory-Actor-Email $memory_actor_email;
    proxy_set_header X-Memory-Actor-Name "";
    proxy_set_header X-Memory-Actor-Issuer "";
    proxy_set_header X-Memory-Actor-Sub "";
    proxy_set_header X-Memory-Actor-Agent "";
    proxy_set_header X-Memory-Actor-Client "";
    proxy_set_header X-Memory-Actor-Session-Id "";
    proxy_set_header X-Memory-Skip-Admission-Chain "";
    include ${actorProxyConfig};

    ${upstreamConfig}
  '';
  apiProxyConfig = ''
    # Direct API users authenticate with ai-memory-issued bearer tokens.
    # Never let public callers reach trusted-proxy identity assertion.
    proxy_set_header Authorization $http_authorization;
    proxy_set_header X-Memory-Actor-User "";
    proxy_set_header X-Memory-Actor-Email "";
    proxy_set_header X-Memory-Actor-Name "";
    proxy_set_header X-Memory-Actor-Issuer "";
    proxy_set_header X-Memory-Actor-Sub "";
    proxy_set_header X-Memory-Actor-Agent "";
    proxy_set_header X-Memory-Actor-Client "";
    proxy_set_header X-Memory-Actor-Session-Id "";
    proxy_set_header X-Memory-Skip-Admission-Chain "";
    limit_req zone=ai_memory_api burst=100 nodelay;

    ${upstreamConfig}
  '';
  proxyLocation = extraConfig: {
    proxyPass = "http://${malt.url}:${toString port}";
    inherit extraConfig;
  };
in
{
  clan.core.vars.generators.ai-memory-actor-proxy = {
    share = true;
    files.token.secret = true;
    files.nginx-config = {
      secret = true;
      owner = "nginx";
      group = "nginx";
      mode = "0440";
      restartUnits = [ "nginx.service" ];
    };
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      token=$(openssl rand -hex 32)
      printf '%s\n' "$token" > "$out/token"
      printf 'proxy_set_header Authorization "Bearer %s";\n' "$token" > "$out/nginx-config"
    '';
  };

  services.nginx.appendHttpConfig = ''
    limit_req_zone $binary_remote_addr zone=ai_memory_api:10m rate=30r/s;
  '';

  services.nginx.virtualHosts.${webDomain} = {
    forceSSL = true;
    enableACME = true;
    extraConfig = securityHeadersConfig;

    locations."= /".return = "302 /web";
    locations."= /oauth2/auth" = {
      proxyPass = "http://127.0.0.1:${toString oauth2Port}/oauth2/auth";
      recommendedProxySettings = false;
      extraConfig = ''
        internal;
        proxy_pass_request_body off;
        proxy_set_header Content-Length "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
      '';
    };
    locations."^~ /oauth2/" = {
      proxyPass = "http://127.0.0.1:${toString oauth2Port}";
      recommendedProxySettings = false;
      extraConfig = ''
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Uri $request_uri;
        proxy_set_header X-Auth-Request-Redirect $scheme://$host$request_uri;
      '';
    };
    locations."@redirectToAiMemoryLogin" = {
      return = "307 https://${webDomain}/oauth2/start?rd=$scheme://$host$request_uri";
      extraConfig = ''
        auth_request off;
      '';
    };
    locations."~ ^/(?:web(?:/|$)|api/v1(?:/|$)|favicon[.]ico$)" = proxyLocation webProxyConfig;
    locations."/".return = "404";
  };

  services.nginx.virtualHosts.${apiDomain} = {
    forceSSL = true;
    enableACME = true;
    extraConfig = securityHeadersConfig;

    locations."~ ^/(?:admin(?:/|$)|mcp(?:/|$)|hook(?:/|$)|handoff$|workstream(?:/|$)|api/v1(?:/|$))" =
      proxyLocation apiProxyConfig;

    # Browser cookies remain on the OIDC-protected hostname.
    locations."/".return = "404";
  };

  systemd.services.nginx.restartTriggers = [ actorProxyConfig ];
}
