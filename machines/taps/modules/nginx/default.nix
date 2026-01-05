{
  imports = [
    ./atuin.nix
    ./immich.nix
    ./n8n.nix
    ./radicle.nix
    ./vaultwarden.nix
    ./stalwart.nix
    ./step-ca.nix
    ./vaultwarden.nix
    ./nextcloud.nix
  ];

  services.nginx = {
    enable = true;
    recommendedBrotliSettings = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    # Fix "could not build optimal proxy_headers_hash" warning
    proxyTimeout = "3600s";
    appendHttpConfig = ''
      proxy_headers_hash_max_size 1024;
      proxy_headers_hash_bucket_size 128;
    '';

    commonHttpConfig = ''
      add_header Strict-Transport-Security 'max-age=31536000; includeSubDomains; preload' always;
    '';

    # Reject unknown hosts
    virtualHosts."_" = {
      default = true;
      rejectSSL = true;
      locations."/".return = "444";
    };
  };

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
}
