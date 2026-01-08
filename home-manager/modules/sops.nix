{
  config,
  pkgs,
  ...
}:
{
  sops.age = {
    generateKey = false;
    keyFile = "${config.xdg.configHome}/sops/age/keys.txt";
    sshKeyPaths = [ "${config.xdg.configHome}/.ssh/id_ed25519" ];
  };
  sops.defaultSopsFile = ./secrets.yml;

  home.packages = with pkgs; [
    age
    age-plugin-yubikey
    sops
  ];
}
