{
  lib,
  ...
}:
{
  programs.rbw = {
    enable = true;
    settings = {
      email = lib.mkDefault "seungwon@mulatta.io";
      base_url = "https://bitwarden.mulatta.io";
    };
  };
}
