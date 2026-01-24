{
  services.postgresql = {
    enable = true;
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
