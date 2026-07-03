{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.ompProfiles;
  yaml = pkgs.formats.yaml { };

  profileType = lib.types.submodule (
    { name, ... }:
    {
      options = {
        backend = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = cfg.backend;
          description = "OMP executable used by this profile.";
        };

        commands = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Command shims that run this profile.";
        };

        agentDir = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = "${config.home.homeDirectory}/.omp/state/${name}/agent";
          description = "PI_CODING_AGENT_DIR for this profile.";
        };

        sessionDir = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = "${config.home.homeDirectory}/.omp/state/${name}/sessions";
          description = "OMP session directory for this profile.";
        };

        runtimeDir = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = "${config.home.homeDirectory}/.cache/omp/profiles/${name}/runtime";
          description = "Directory for generated runtime files.";
        };

        toolPackages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
          description = "Packages whose bin directories are prepended to PATH.";
        };

        toolPath = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Extra PATH entries prepended before running OMP.";
        };

        enabledTools = lib.mkOption {
          type = lib.types.nullOr (lib.types.listOf lib.types.str);
          default = null;
          description = "OMP tools enabled for launch sessions.";
        };

        skillPackages = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
          description = "Packages whose share/skills directories are added.";
        };

        skillDirectories = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Extra skill directories.";
        };

        includeSkills = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Skill names to include in the generated OMP config.";
        };

        config = lib.mkOption {
          type = lib.types.attrs;
          default = { };
          description = "Extra OMP config.yml content for this profile.";
        };

        prompt = {
          text = lib.mkOption {
            type = lib.types.nullOr lib.types.lines;
            default = null;
            description = "System prompt text appended for launch sessions.";
          };

          file = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "System prompt file appended for launch sessions.";
          };
        };

        env = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = "Environment variables added by this profile.";
        };

        ensureDirs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Directories created before launching OMP.";
        };

        passthroughCommands = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "OMP management commands that skip launch-only flags.";
        };

        sandbox = {
          linuxBubblewrap = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Run launch sessions in bubblewrap on Linux.";
          };

          rw = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Read-write paths bound into the Linux sandbox.";
          };

          ro = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Read-only paths bound into the Linux sandbox.";
          };

          envKeys = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Additional environment variables preserved in sandbox.";
          };
        };
      };
    }
  );

  skillConfig = profile: {
    skills = {
      enableClaudeUser = false;
      enableClaudeProject = false;
      enablePiUser = false;
      enablePiProject = false;
      enableAgentsUser = false;
      enableAgentsProject = false;
      customDirectories =
        (map (pkg: "${pkg}/share/skills") profile.skillPackages) ++ profile.skillDirectories;
      includeSkills = profile.includeSkills;
    };
  };

  mkProfileConfig =
    _name: profile:
    let
      hasSkillScope =
        profile.skillPackages != [ ] || profile.skillDirectories != [ ] || profile.includeSkills != [ ];
    in
    lib.filterAttrs (_: value: value != null && value != [ ] && value != { }) {
      inherit (profile)
        backend
        agentDir
        sessionDir
        runtimeDir
        enabledTools
        env
        ensureDirs
        passthroughCommands
        sandbox
        ;
      toolPath = (map (pkg: "${pkg}/bin") profile.toolPackages) ++ profile.toolPath;
      config = lib.recursiveUpdate (lib.optionalAttrs hasSkillScope (skillConfig profile)) profile.config;
      prompt = lib.filterAttrs (_: value: value != null) profile.prompt;
    };

  profileFiles = lib.mapAttrs' (
    name: profile:
    lib.nameValuePair ".omp/profiles/${name}.yml" {
      source = yaml.generate "omp-profile-${name}.yml" (mkProfileConfig name profile);
    }
  ) cfg.profiles;

  commandPackages = lib.flatten (
    lib.mapAttrsToList (
      name: profile:
      map (
        command:
        pkgs.writeShellScriptBin command ''
          exec ${lib.getExe cfg.package} --profile ${lib.escapeShellArg name} "$@"
        ''
      ) profile.commands
    ) cfg.profiles
  );
in
{
  options.programs.ompProfiles = {
    enable = lib.mkEnableOption "profile-aware OMP wrapper";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.omp-profile;
      description = "Profile-aware OMP wrapper package.";
    };

    backend = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Default upstream OMP executable for profiles.";
    };

    profiles = lib.mkOption {
      type = lib.types.attrsOf profileType;
      default = { };
      description = "Declarative OMP profiles written under ~/.omp/profiles.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ] ++ commandPackages;
    home.file = profileFiles;
  };
}
