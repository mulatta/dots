{
  config,
  lib,
  self,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  skillz = self.inputs.skillz;
  skillzPkgs = skillz.packages.${system};

  opencrowModule = import (builtins.toFile "opencrow-module.nix" (
    builtins.replaceStrings [ "pkgs.hostPlatform" ] [ "pkgs.stdenv.hostPlatform" ] (
      builtins.readFile "${self.inputs.opencrow}/nix/module.nix"
    )
  )) { self = self.inputs.opencrow; };

  officecli = self.inputs.llm-agents.packages.${system}.officecli;
  # Use upstream skill text so the skill stays version-locked to the binary
  # without vendoring the full source tree into the runtime closure.
  officecliSkill = pkgs.runCommand "officecli-skill-${officecli.version}" { } ''
    mkdir -p "$out"
    cp ${officecli.src}/SKILL.md "$out/SKILL.md"
  '';
  instanceDefaults = {
    package = lib.mkDefault (
      self.inputs.opencrow.packages.${system}.opencrow.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./nostr-periodic-resubscribe.patch ];
      })
    );
    piPackage = lib.mkDefault self.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.omp;

    extensions = {
      memory = lib.mkDefault true;
      reminders = lib.mkDefault true;
      # Personal-assistant compaction replacing pi's coding-agent default.
      # Feeds higher-quality summaries into the memory extension's sediment
      # store, which is what cross-session recall retrieves from.
      compaction = lib.mkDefault ./extensions/compaction;
    };

    skills = {
      context7-cli = lib.mkDefault "${skillz}/context7-cli/skills";
      crwl-cli = lib.mkDefault "${skillz}/crwl-cli/skills";
      pexpect-cli = lib.mkDefault "${skillz}/pexpect-cli/skills";
      http = lib.mkDefault ./skills/http;
      document-reading = lib.mkDefault ./skills/document-reading;
      source-triage = lib.mkDefault ./skills/source-triage;
      officecli = lib.mkDefault officecliSkill;
    };

    environment = {
      TZ = lib.mkDefault "Asia/Seoul";
      # Container has no outbound network; stop officecli probing for updates.
      OFFICECLI_SKIP_UPDATE = lib.mkDefault "1";
      OPENCROW_PI_PROVIDER = lib.mkDefault "openai-codex";
      OPENCROW_PI_MODEL = lib.mkDefault "gpt-5.5";

      # Periodic awareness check. Noa reads mutable HEARTBEAT.md from
      # the state directory; manage that file out-of-band.
      OPENCROW_HEARTBEAT_INTERVAL = lib.mkDefault "30m";
      OPENCROW_HEARTBEAT_PROMPT = lib.mkDefault ''
        Run through the standing checks below.
        If nothing needs attention, reply exactly HEARTBEAT_OK.

        Report only actionable items.
        Do not summarize normal status.
        Keep output concise, under 10 bullets.
        Use Korean unless source text requires otherwise.

        When reporting, include what needs attention, why it matters, and suggest next action.
      '';

      # Nostr infrastructure is shared by default; identity lives in nostr.nix.
      OPENCROW_BACKEND = lib.mkDefault "nostr";
      OPENCROW_NOSTR_PRIVATE_KEY_FILE = lib.mkDefault "%d/nostr-private-key";
      OPENCROW_NOSTR_RELAYS = lib.mkDefault (lib.concatStringsSep "," config.mulatta.nostr.dmRelays);
      OPENCROW_NOSTR_DM_RELAYS = lib.mkDefault (lib.concatStringsSep "," config.mulatta.nostr.dmRelays);
      OPENCROW_NOSTR_ALLOWED_USERS = lib.mkDefault "npub12ckrqlr7p4tdsx89p37xhxja664r20xtuzrl0mngccwpye6qnz4q26525y";
      OPENCROW_NOSTR_BLOSSOM_SERVERS = lib.mkDefault (
        lib.concatStringsSep "," config.mulatta.nostr.blossomServers
      );
    };

    # Lists merge additively, unlike scalar defaults; keep the baseline
    # packages unconditional so domain modules cannot accidentally drop them.
    extraPackages = with pkgs; [
      coreutils
      curl
      fd
      file
      findutils
      git
      gnugrep
      gnused
      htmlq
      hurl
      jq
      libarchive
      poppler-utils
      python3
      rhwp
      ripgrep
      tree
      unzip
      wget
      yq-go
      zip
      zstd
      python313Packages.pymupdf
      skillzPkgs.context7-cli
      skillzPkgs.crwl-cli
      skillzPkgs.pexpect-cli
      # Resolve to the llm-agents build, not pinned nixpkgs.
      officecli
    ];
  };
in
{
  imports = [
    opencrowModule
    ./noa.nix
  ];

  # Apply the same base runtime to the top-level Noa instance and any
  # future named instances under services.opencrow.instances.*.
  options.services.opencrow = lib.mkOption {
    type = lib.types.submodule {
      options.instances = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule { config = instanceDefaults; });
      };
      config = instanceDefaults;
    };
  };
}
