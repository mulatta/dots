{
  inputs,
  config,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  pi-ext = inputs.pi-agent-extensions;
  aiPkgs = inputs.llm-agents.packages.${system};
  skillzPkgs = inputs.skillz.packages.${system};
  calendarCli = skillzPkgs.calendar-cli.override {
    msmtp = pkgs.msmtp-with-sent;
  };

  # On GPU hosts pkgs is rebuilt with cudaSupport=true (gpu-support.nix); rebuild
  # qmd with CUDA there, otherwise take the cached upstream build. qmd sources
  # cudaPackages from its own pkgs, so cudaSupport is the only arg it accepts.
  qmd =
    if pkgs.config.cudaSupport or false then
      aiPkgs.qmd.override { cudaSupport = true; }
    else
      aiPkgs.qmd;

  piAgentDeps = pkgs.callPackage ../../../home/.pi/agent/default.nix { };

  # officecli ships its skill text in-source and CI keeps it byte-identical to
  # what the binary emits, so source it from officecli.src instead of vendoring
  # a copy that would drift. Pinning to .src version-locks the skill to the
  # binary and keeps the whole source tree out of the profile closure.
  officecliSkill = pkgs.runCommand "officecli-skill-${aiPkgs.officecli.version}" { } ''
    mkdir -p "$out"
    cp ${aiPkgs.officecli.src}/SKILL.md "$out/SKILL.md"
  '';

  nostorePreload = pkgs.nostore-preload;
in
{
  inherit
    aiPkgs
    calendarCli
    officecliSkill
    piAgentDeps
    qmd
    skillzPkgs
    system
    ;

  nostoreEnvVar = nostorePreload.passthru.envVar;
  nostoreLib = "${nostorePreload}/lib/libnostore${pkgs.stdenv.hostPlatform.extensions.sharedLibrary}";

  commonProfileExtensions = [
    "${pi-ext}/permission-gate"
    "${pi-ext}/slow-mode/index.ts"
    "${pi-ext}/notify/index.ts"
    "${pi-ext}/questionnaire/index.ts"
    "${pi-ext}/statusline"
  ];

  piExtensionFiles = {
    ".pi/agent/extensions/direnv.ts" = "${pi-ext}/direnv/index.ts";
    ".pi/agent/extensions/questionnaire.ts" = "${pi-ext}/questionnaire/index.ts";
    ".pi/agent/extensions/slow-mode.ts" = "${pi-ext}/slow-mode/index.ts";
    ".pi/agent/extensions/notify.ts" = "${pi-ext}/notify/index.ts";
    ".pi/agent/extensions/permission-gate" = "${pi-ext}/permission-gate";
    ".pi/agent/extensions/stash" = "${pi-ext}/stash";
    ".pi/agent/extensions/statusline" = "${pi-ext}/statusline";
  };

  home = config.home.homeDirectory;
}
