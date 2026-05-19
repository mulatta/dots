{
  inputs = {
    # Shared roots. Other flakes follow these to avoid duplicate lock nodes.
    nixpkgs.url = "git+https://github.com/mulatta/nixpkgs?shallow=1&ref=main";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";

    nix-darwin.url = "github:nix-darwin/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    # Core modules and system integrations.
    clan-core = {
      url = "https://git.clan.lol/clan/clan-core/archive/25.11.tar.gz";
      inputs.disko.follows = "disko";
      inputs.flake-parts.follows = "flake-parts";
      inputs.nix-darwin.follows = "nix-darwin";
      inputs.sops-nix.follows = "sops-nix";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    srvos = {
      url = "github:nix-community/srvos";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware";

    # Package sources
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.flake-parts.follows = "flake-parts";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    # Infra-level modules sources
    fast-nix-gc = {
      url = "github:Mic92/fast-nix-gc";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    niks3 = {
      url = "github:Mic92/niks3";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    n8n-nodes = {
      url = "github:mulatta/n8n-nodes";
      inputs.flake-parts.follows = "flake-parts";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    restate-workflows = {
      url = "github:mulatta/restate-workflows";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    opencrow = {
      url = "github:pinpox/opencrow";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    rhwp-nextcloud = {
      url = "github:mulatta/rhwp-nextcloud";
      inputs.flake-parts.follows = "flake-parts";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rhwp-nix.follows = "rhwp";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    # Applications
    flake-fmt = {
      url = "github:Mic92/flake-fmt";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    direnv-instant = {
      url = "github:Mic92/direnv-instant";
      inputs.flake-parts.follows = "flake-parts";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    paneru = {
      url = "github:karinushka/paneru";
      inputs.flake-parts.follows = "flake-parts";
      inputs.nix-darwin.follows = "nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nitrous = {
      url = "github:pinpox/nitrous";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia-plugins = {
      url = "github:mulatta/noctalia-plugins";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    rhwp = {
      url = "github:mulatta/rhwp-nix/a50cae05ae69748afa9ee7cf5b937cb8375637e8";
      inputs.flake-parts.follows = "flake-parts";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zjstatus.url = "github:dj95/zjstatus";
    zjstatus.inputs.nixpkgs.follows = "nixpkgs";

    zsh-helix-mode.url = "github:Multirious/zsh-helix-mode";

    # Agentic tools
    skillz = {
      url = "github:mulatta/skillz";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    pi-agent-extensions = {
      url = "github:rytswd/pi-agent-extensions";
      flake = false;
    };

    # Pinned overlays
    overlay-nixpkgs-dante-zenity.url = "github:NixOS/nixpkgs/09061f748ee21f68a089cd5d91ec1859cd93d0be";

  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      imports = [
        ./checks/flake-module.nix
        ./formatter/flake-module.nix
        ./home-manager/flake-module.nix
        ./home-manager/modules/helix/flake-module.nix
        ./home-manager/modules/yazi/flake-module.nix
        ./overlays/flake-module.nix
        ./machines/flake-module.nix
        ./packages/flake-module.nix
        ./shells/flake-module.nix
        ./terraform/flake-module.nix
        inputs.clan-core.flakeModules.default
        inputs.home-manager.flakeModules.home-manager
      ];

      flake.nixosModules.imports = [ ./nixosModules ];
      flake.darwinModules.imports = [ ./darwinModules ];
    };
}
