{
  config,
  pkgs,
  ...
}:
let
  seungwonKey = [
    # Secretive Secure Enclave key on rhesus (daily SSH from laptop).
    "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBAbiIX1IpgsaylNgtDb04IM4jQKlU+RVwDr8YGfXLwuHWn3xydzTYeg3o/T9UX/j2326D7tnL7kMq7XvmhuSd8Y= ssh@secretive.rhesus.local"
    # Legacy ed25519 (~/.ssh/id_ed25519). Kept for the migration window so
    # existing sessions and tooling that still references this key keep
    # working; remove after Secretive access is verified across all hosts.
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINkKJdIzvxlWcry+brNiCGLBNkxrMxFDyo1anE4xRNkL"
  ];

  # Shared definition: prompt for a password, else generate an xkcd passphrase,
  # then store both the plaintext and its sha-512 hash.
  mkPasswordGenerator = {
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
in
{
  programs.zsh.enable = true;
  users.users.seungwon = {
    home = "/home/seungwon";
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    hashedPasswordFile = config.clan.core.vars.generators.seungwon-password.files.password-hash.path;
    shell = "/run/current-system/sw/bin/zsh";
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

  clan.core.vars.generators.root-password = mkPasswordGenerator;
  clan.core.vars.generators.seungwon-password = mkPasswordGenerator;
}
