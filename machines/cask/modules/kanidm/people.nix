let
  baseDomain = "mulatta.io";
in
{
  # Human accounts. Service access groups in default.nix reference these.
  services.kanidm.provision = {
    groups = {
      # Humans, as opposed to notify and bot identities.
      people.members = [
        "seungwon"
        "friends"
      ];
      friends.members = [
        "mingyu"
        "hyotaek"
        "jinseok"
      ];
    };

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
      mingyu = {
        displayName = "Mingyu";
        mailAddresses = [ "mid169@naver.com" ];
      };
      hyotaek = {
        displayName = "Hyotaek";
        mailAddresses = [ "kht1790@naver.com" ];
      };
      jinseok = {
        displayName = "Jinseok";
        mailAddresses = [ "wlstjr0033@naver.com" ];
      };
    };
  };
}
