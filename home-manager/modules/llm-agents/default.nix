{
  pkgs,
  lib,
  self,
  inputs,
  ...
}:
let
  aiTools = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
  selfPkgs = self.packages.${pkgs.stdenv.hostPlatform.system};
  skillzPkgs = inputs.skillz.packages.${pkgs.stdenv.hostPlatform.system};
  nixbot-cli = inputs.nixbot.packages.${pkgs.stdenv.hostPlatform.system}.nixbot-cli;

  # On GPU hosts pkgs is rebuilt with cudaSupport=true (gpu-support.nix); rebuild
  # qmd with CUDA there, otherwise take the cached upstream build. qmd sources
  # cudaPackages from its own pkgs, so cudaSupport is the only arg it accepts.
  qmd =
    if pkgs.config.cudaSupport or false then
      aiTools.qmd.override { cudaSupport = true; }
    else
      aiTools.qmd;

  aiMemory = pkgs.writeShellApplication {
    name = "ai-memory";
    text = ''
      export AI_MEMORY_SERVER_URL=https://memory-api.mulatta.io
      AI_MEMORY_AUTH_TOKEN="$(${pkgs.rbw}/bin/rbw get ai-memory-token)"
      export AI_MEMORY_AUTH_TOKEN
      exec ${aiTools.ai-memory}/bin/ai-memory "$@"
    '';
  };

  aiMemoryAdmin = pkgs.writeShellApplication {
    name = "ai-memory-admin";
    text = ''
      export AI_MEMORY_SERVER_URL=https://memory-api.mulatta.io
      AI_MEMORY_AUTH_TOKEN="$(${pkgs.rbw}/bin/rbw get ai-memory-admin-token)"
      export AI_MEMORY_AUTH_TOKEN
      exec ${aiTools.ai-memory}/bin/ai-memory "$@"
    '';
  };

  officecliSkill = pkgs.runCommand "officecli-skill-${aiTools.officecli.version}" { } ''
    mkdir -p "$out"
    cp ${aiTools.officecli.src}/SKILL.md "$out/SKILL.md"
  '';
in
{
  imports = [
    inputs.skillz.homeModules.default
    inputs.research-skills.homeModules.default
    ../herdr
  ];

  programs.herdr.enable = true;

  programs.skillz = {
    enable = true;
    skills = [
      "biorefs-cli"
      "calendar-cli"
      "context7-cli"
      "crwl-cli"
      "drawio-cli"
      "kmap-cli"
      "linkwarden-cli"
      "n8n-cli"
      "pexpect-cli"
      "vikunja-cli"
    ]
    ++ lib.optionals pkgs.stdenv.isDarwin [ "shortcuts-cli" ];
    package = skillzPkgs // {
      calendar-cli = skillzPkgs.calendar-cli.override {
        msmtp = selfPkgs.msmtp-with-sent;
      };
    };
  };

  programs.research-skills = {
    enable = true;
    skills = [
      "biomcp"
      "pymol-cli"
    ];
  };

  home.file.".claude/skills/archify".source = "${selfPkgs.archify-cli}/share/skills/archify";

  # nixbot-cli ships its agent skill alongside the binary.
  home.file.".claude/skills/nixbot-cli".source = "${nixbot-cli}/share/skills/nixbot-cli";

  # git-surgeon ships a skill teaching agents how to use its git primitives.
  home.file.".claude/skills/git-surgeon".source =
    "${aiTools.git-surgeon}/share/git-surgeon/skills/git-surgeon";

  # officecli ships its skill text in-source and CI keeps it byte-identical to
  # what the binary emits, so source it from officecli.src instead of vendoring
  # a copy that would drift. Pinning to .src version-locks the skill to the
  # binary and keeps the whole source tree out of the profile closure.
  home.file.".claude/skills/officecli/SKILL.md".source = "${officecliSkill}/SKILL.md";

  home.file.".claude/skills/ctx-agent-history-search/SKILL.md".source =
    "${aiTools.ctx.src}/skills/ctx-agent-history-search/SKILL.md";

  home.file.".claude/skills/zat/SKILL.md".text = ''
    ---
    name: zat
    description: Code outline viewer showing exported symbol signatures with line numbers. Use when you need signatures, not full implementation.
    ---

    Prefer `zat` over `cat`/`Read` when you need signatures, not full implementation. Use the line numbers in the output to `Read(offset, limit)` into specific sections.

    Supported languages: C, C++, C#, Go, Haskell, Java, JavaScript, Kotlin, Markdown, Python, Ruby, Rust, Swift, TypeScript/TSX

    ```
    zat <FILE>
    ```
  '';

  home.file.".pi/agent/extensions/direnv.ts".source = "${inputs.pi-agent-extensions}/direnv/index.ts";
  home.file.".pi/agent/extensions/questionnaire.ts".source =
    "${inputs.pi-agent-extensions}/questionnaire/index.ts";
  home.file.".pi/agent/extensions/slow-mode.ts".source =
    "${inputs.pi-agent-extensions}/slow-mode/index.ts";
  home.file.".pi/agent/extensions/notify.ts".source = "${inputs.pi-agent-extensions}/notify/index.ts";
  home.file.".pi/agent/extensions/fetch".source = "${inputs.pi-agent-extensions}/fetch";
  home.file.".pi/agent/extensions/permission-gate".source =
    "${inputs.pi-agent-extensions}/permission-gate";
  home.file.".pi/agent/extensions/stash".source = "${inputs.pi-agent-extensions}/stash";
  home.file.".pi/agent/extensions/statusline".source = "${inputs.pi-agent-extensions}/statusline";

  home.packages = [
    aiMemory
    aiMemoryAdmin
    qmd
    selfPkgs.archify-cli
    selfPkgs.claude-code
    selfPkgs.claude-md
    selfPkgs.pim
    (pkgs.writeShellApplication {
      name = "pi";
      text = ''
        export AI_MEMORY_SERVER_URL=https://memory-api.mulatta.io
        AI_MEMORY_AUTH_TOKEN="$(${pkgs.rbw}/bin/rbw get ai-memory-token)"
        export AI_MEMORY_AUTH_TOKEN
        ${pkgs.pueue}/bin/pueued -d >/dev/null 2>&1 || true
        exec ${aiTools.pi}/bin/pi "$@"
      '';
    })
    aiTools.apm
    aiTools.ccstatusline
    aiTools.codex
    aiTools.ctx
    aiTools.git-surgeon
    aiTools.jscpd
    aiTools.officecli
    aiTools.prime-agent
    aiTools.tuicr
    aiTools.zat
    nixbot-cli
    pkgs.pueue
  ];
}
