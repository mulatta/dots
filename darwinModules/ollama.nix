{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.ollama;

  ollamaEnv = {
    OLLAMA_HOST = "${cfg.host}:${toString cfg.port}";
  }
  // (lib.optionalAttrs (cfg.home != null) {
    HOME = cfg.home;
  })
  // (lib.optionalAttrs (cfg.models != null) {
    OLLAMA_MODELS = cfg.models;
  })
  // cfg.environmentVariables;

  modelLoaderScript = pkgs.writeShellScript "ollama-model-loader" ''
    export OLLAMA_HOST="${cfg.host}:${toString cfg.port}"

    # Wait for ollama to be ready
    for i in {1..30}; do
      if ${cfg.package}/bin/ollama list >/dev/null 2>&1; then
        break
      fi
      sleep 2
    done

    if ! ${cfg.package}/bin/ollama list >/dev/null 2>&1; then
      echo "ollama server not ready after 60s, giving up"
      exit 1
    fi

    ${lib.optionalString cfg.syncModels ''
      # Remove models not in the declared list
      ${cfg.package}/bin/ollama list | tail -n +2 | awk '{print $1}' | while read -r model; do
        model_name="''${model%%:*}"
        found=0
        for declared in ${lib.escapeShellArgs cfg.loadModels}; do
          declared_name="''${declared%%:*}"
          if [ "$model_name" = "$declared_name" ]; then
            found=1
            break
          fi
        done
        if [ "$found" = "0" ]; then
          echo "Removing undeclared model: $model"
          ${cfg.package}/bin/ollama rm "$model" || true
        fi
      done
    ''}

    ${lib.concatMapStringsSep "\n" (model: ''
      echo "Pulling model: ${model}"
      ${cfg.package}/bin/ollama pull "${model}"
    '') cfg.loadModels}
  '';
in
{
  options.services.ollama = {
    enable = lib.mkEnableOption "ollama server for local large language models";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.ollama;
      defaultText = lib.literalExpression "pkgs.ollama";
      description = "The ollama package to use.";
    };

    home = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/var/lib/ollama";
      description = ''
        The home directory for the ollama service.
        When null, ollama uses its default (~/.ollama).
        Note: launchd plist does not expand shell variables,
        so this must be an absolute path if set.
      '';
    };

    models = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/path/to/ollama/models";
      description = ''
        The directory for ollama models.
        When null, ollama uses its default (~/.ollama/models).
        Note: launchd plist does not expand shell variables,
        so this must be an absolute path if set.
      '';
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "The host address which the ollama server HTTP interface listens to.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 11434;
      description = "Which port the ollama server listens to.";
    };

    environmentVariables = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Set arbitrary environment variables for the ollama service.
        Be aware that these are only seen by the ollama server (launchd service),
        not normal invocations like `ollama run`.
      '';
    };

    loadModels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Download these models using `ollama pull` as soon as the service has started.
        Search for models at: https://ollama.com/library
      '';
    };

    syncModels = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Synchronize all currently installed models with those declared in
        `services.ollama.loadModels`, removing any models that are
        installed but not currently declared there.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    # Ensure directories exist with correct ownership for user agent
    system.activationScripts.postActivation.text = lib.mkIf (cfg.home != null || cfg.models != null) (
      lib.mkAfter ''
        echo "Setting up ollama directories..."
        ${lib.optionalString (cfg.home != null) ''
          mkdir -p "${cfg.home}"
          chown "${config.system.primaryUser}" "${cfg.home}"
        ''}
        ${lib.optionalString (cfg.models != null) ''
          mkdir -p "${cfg.models}"
          chown "${config.system.primaryUser}" "${cfg.models}"
        ''}
      ''
    );

    # Main ollama server as a user agent
    launchd.user.agents.ollama = {
      path = [ config.environment.systemPath ];
      serviceConfig = {
        ProgramArguments = [
          "${cfg.package}/bin/ollama"
          "serve"
        ];
        EnvironmentVariables = ollamaEnv;
        KeepAlive = true;
        RunAtLoad = true;
        StandardOutPath = "/tmp/ollama.stdout.log";
        StandardErrorPath = "/tmp/ollama.stderr.log";
      };
    };

    # Model loader agent (runs once after ollama is available)
    launchd.user.agents.ollama-model-loader = lib.mkIf (cfg.loadModels != [ ] || cfg.syncModels) {
      serviceConfig = {
        ProgramArguments = [ "${modelLoaderScript}" ];
        RunAtLoad = true;
        StandardOutPath = "/tmp/ollama-model-loader.stdout.log";
        StandardErrorPath = "/tmp/ollama-model-loader.stderr.log";
      };
    };
  };
}
