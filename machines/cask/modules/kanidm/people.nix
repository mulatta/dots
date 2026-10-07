let
  baseDomain = "mulatta.io";
in
{
  # Human accounts. Service access groups in default.nix reference these.
  services.kanidm.provision = {
    persons = {
      seungwon = {
        displayName = "Seungwon";
        mailAddresses = [
          "seungwon@${baseDomain}"
          # Operational aliases terminate in the primary operator mailbox;
          # no service needs separate mailbox credentials for these roles.
          "acme@${baseDomain}"
          "billings@${baseDomain}"
          "postmaster@${baseDomain}"
          "security@${baseDomain}"
        ];
      };
    };
  };
}
