{
  self,
  pkgs,
  ...
}: let
  cask = self.inputs.nix-casks.packages.${pkgs.stdenv.hostPlatform.system};
in {
  environment.systemPackages = [
    # keep-sorted start
    cask."1password"
    cask.aldente
    cask.claude
    cask.cleanshot
    cask.devonthink
    cask.ghostty
    cask.hazel
    cask.raycast
    cask.secretive
    cask.slack
    cask.zotero
    cask.zen-browser
    # keep-sorted end
  ];
}
