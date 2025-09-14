{
  config,
  lib,
  ...
}: {
  homebrew.enable = true;
  system.activationScripts.homebrew.text = lib.mkIf config.homebrew.enable (
    lib.mkBefore ''
      if [[ ! -f "${config.homebrew.brewPrefix}/brew" ]]; then
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrerw/install/HEAD/install.sh)"
      fi
    ''
  );

  # Don't quarantine apps installed by homebrew with gatekeeper
  homebrew.caskArgs.no_quarantine = true;
  # Remove all homebrew packages when they get removed from the configuration
  homebrew.onActivation.cleanup = "uninstall";

  homebrew.taps = [
    "deskflow/homebrew-tap"
  ];
  homebrew.casks = [
    # keep-sorted start
    "1password"
    "aldente"
    "bookends"
    "claude"
    "cleanshot"
    "deskflow"
    "devonthink"
    "ghostty"
    "hancom-word"
    "hazel"
    "hookmark"
    "logi-options+"
    "raycast"
    "slack"
    "yubico-yubikey-manager"
    "zen"
    "zoom"
    "zotero"
    # keep-sorted end
  ];
}
