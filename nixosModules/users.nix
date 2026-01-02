{
  config,
  pkgs,
  ...
}:
let
  seungwonKey = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINkKJdIzvxlWcry+brNiCGLBNkxrMxFDyo1anE4xRNkL"
  ];
in
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
    openssh.authorizedKeys.keys = seungwonKey;
  };

  users.users.root = {
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    hashedPasswordFile = config.clan.core.vars.generators.root-password.files.password-hash.path;
    shell = "/run/current-system/sw/bin/bash";
    openssh.authorizedKeys.keys = seungwonKey;
  };

  clan.core.vars.generators.root-password = {
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
