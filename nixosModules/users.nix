{
  config,
  pkgs,
  ...
}:
{
  users.users.seungwon = {
    home = "/home/seungwon";
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    hashedPasswordFile = config.clan.core.vars.generators.seungwon-password.files.password-hash.path;
    shell = "/run/current-system/sw/bin/fish";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINkKJdIzvxlWcry+brNiCGLBNkxrMxFDyo1anE4xRNkL"
    ];
  };

  # root user SSH keys and password managed via clan.inventory.instances.admin
  users.users.root = {
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    shell = "/run/current-system/sw/bin/bash";
  };

  clan.core.vars.generators.seungwon-password = {
    files.password-hash.neededFor = "users";
    files.password.deploy = false;
    runtimeInputs = [
      pkgs.mkpasswd
      pkgs.xkcdpass
    ];
    prompts.password.type = "hidden";
    script = ''
       prompt_value="$(cat "$prompts"/password)"
      if [[ -n "''${prompt_value-}" ]]; then
        echo "$prompt_value" | tr -d "\n" > "$out"/password
      else
        xkcdpass --numwords 4 --delimiter - --count 1 | tr -d "\n" > "$out"/password
      fi
      mkpasswd -s -m sha-512 < "$out"/password | tr -d "\n" > "$out"/password-hash
    '';
  };
}
