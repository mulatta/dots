{
  config,
  pkgs,
  self,
  ...
}:
let
  hindsightClient = self.packages.${pkgs.stdenv.hostPlatform.system}.hindsight-client;
  # Same commit as hermes-agent's plugin-catalog/hindsight.yaml; bump them together.
  hindsightPlugin = pkgs.fetchFromGitHub {
    owner = "vectorize-io";
    repo = "hindsight";
    rev = "176f8c2de1369f569c489b831d143b78128b5535";
    sparseCheckout = [ "hindsight-integrations/hermes" ];
    hash = "sha256-PRr1wG5n1zjwE9NR5UiOm6Qy2jXMfninbg3QiNO3KIM=";
  };
  python = hindsightClient.pythonModule;
in
{
  # The hindsight API runs on this host; Hermes shares its network namespace.
  services.hermes = {
    plugins.hindsight = "${hindsightPlugin}/hindsight-integrations/hermes";
    credentials.hindsight-api-key = {
      file = config.clan.core.vars.generators.hindsight.files.api-key.path;
      env = "HINDSIGHT_API_KEY";
    };
    environment = {
      HINDSIGHT_MODE = "local_external";
      HINDSIGHT_API_URL = "http://127.0.0.1:8890";
      # Hermes' sealed Nix venv appends this read-only tree to sys.path behind its own
      # packages, so the plugin's client imports without shadowing pinned deps.
      # shortcut: assumes Hermes and this flake share one Python minor; pin hindsightClient to Hermes' interpreter if they diverge.
      HERMES_LAZY_INSTALL_TARGET = "${
        python.withPackages (_: [ hindsightClient ])
      }/${python.sitePackages}";
    };
    settings = {
      memory.provider = "hindsight";
      # A lazy-install target lifts the sealed-venv block; the store path is read-only anyway.
      security.allow_lazy_installs = false;
    };
  };
}
