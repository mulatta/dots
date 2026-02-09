{
  self,
  inputs,
  pkgs,
  system,
  ...
}:
{
  home.file.".claude/skills".source = "${inputs.skillz}/skills";

  home.packages = [
    pkgs.gemini-cli
    pkgs.ccstatusline
    pkgs.ck
    pkgs.qmd
    pkgs.crwl
    pkgs.pqa
    pkgs.style-review
    pkgs.context7-cli
    self.packages.${system}.claude-code
    self.packages.${system}.claude-md
    pkgs.pueue
  ];
}
