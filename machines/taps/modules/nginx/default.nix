{
  imports = [
    ./vaultwarden.nix
  ];

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;

    commonHttpConfig = ''
      add_header Strict-Transport-Security 'max-age=31536000; includeSubDomains; preload' always;
    '';
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "acme@mulatta.io";
  };

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
}
