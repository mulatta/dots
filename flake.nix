{
  inputs = {
    # Shared roots. Other flakes follow these to avoid duplicate lock nodes.
    nixpkgs.url = "git+https://github.com/mulatta/nixpkgs?shallow=1&ref=main";

    systems.url = "github:nix-systems/default";

    flake-utils.url = "github:numtide/flake-utils";
    flake-utils.inputs.systems.follows = "systems";

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

    tincr = {
      url = "github:Mic92/tincr";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    dure = {
      url = "github:dure-net/dure";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.tincr.follows = "tincr";
    };

    # Core modules and system integrations.
    clan-core = {
      url = "git+https://git.clan.lol/clan/clan-core?ref=main";
      inputs.disko.follows = "disko";
      inputs.flake-parts.follows = "flake-parts";
      inputs.nix-darwin.follows = "nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.sops-nix.follows = "sops-nix";
      inputs.systems.follows = "systems";
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

    nix-grpc-store = {
      url = "github:Mic92/nix-grpc-store";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Package sources
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.flake-parts.follows = "flake-parts";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "systems";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    # Infra-level modules sources
    fast-nix-gc = {
      url = "github:Mic92/fast-nix-gc";
      inputs.nix-darwin.follows = "nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    niks3 = {
      url = "github:Mic92/niks3";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    nixbot = {
      url = "github:Mic92/nixbot";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    gitea-mq = {
      url = "github:Mic92/gitea-mq";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    radicle-mirror = {
      url = "github:Mic92/radicle-mirror";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    zhost = {
      url = "github:mulatta/zhost";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    n8n-nodes = {
      url = "github:mulatta/n8n-nodes";
      inputs.flake-parts.follows = "flake-parts";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    automation-runtime = {
      url = "github:mulatta/automation-runtime";
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
      url = "github:karinushka/paneru/v0.4.4";
      inputs.flake-parts.follows = "flake-parts";
      inputs.nix-darwin.follows = "nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-minecraft = {
      url = "github:Infinidoge/nix-minecraft";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "systems";
    };

    noctalia-plugins = {
      url = "github:mulatta/noctalia-plugins";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    rhwp = {
      url = "github:mulatta/rhwp.nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.home-manager.follows = "home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zsh-helix-mode = {
      url = "github:Multirious/zsh-helix-mode";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Agentic tools
    research-skills = {
      url = "github:mulatta/research-skills";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    cherri = {
      url = "github:electrikmilk/cherri";
      inputs.flake-utils.follows = "flake-utils";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    skillz = {
      url = "github:mulatta/skillz";
      inputs.cherri.follows = "cherri";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };
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
        ./clanServices/flake-module.nix
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

      flake.nixosModules.default = ./nixosModules;
      flake.herculesCI = import ./checks/effects.nix { inherit inputs; };
    };
}
