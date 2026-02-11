{
  services.postgresql = {
    enable = true;
    settings = {
      shared_buffers = "64MB";
      effective_cache_size = "1GB";
    };
    ensureDatabases = [
      "stalwart-mail"
      "vaultwarden"
      "step-ca"
    ];
    ensureUsers = [
      {
        name = "stalwart-mail";
        ensureDBOwnership = true;
      }
      {
        name = "vaultwarden";
        ensureDBOwnership = true;
      }
      {
        name = "step-ca";
        ensureDBOwnership = true;
      }
    ];
  };
}
