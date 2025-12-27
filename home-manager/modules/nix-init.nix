{
  programs.nix-init = {
    enable = true;
    settings = {
      maintainers = [ "mulatta" ];
      nixpkgs = "<nixpkgs>";
    };
  };
}
