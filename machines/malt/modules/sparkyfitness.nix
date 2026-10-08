{
  self,
  config,
  pkgs,
  ...
}:
let
  domain = "fitness.mulatta.io";
in
{
  imports = [ self.inputs.sparkyfitness.nixosModules.sparkyfitness ];

  clan.core.vars.generators.kanidm-sparkyfitness-oidc = {
    share = true;
    files.secret.secret = true;
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      openssl rand -hex 32 > "$out/secret"
    '';
  };

  clan.core.vars.generators.sparkyfitness = {
    dependencies = [ "kanidm-sparkyfitness-oidc" ];
    files.env = {
      secret = true;
      owner = "sparkyfitness";
      group = "sparkyfitness";
    };
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      db_password=$(openssl rand -hex 32)
      app_db_password=$(openssl rand -hex 32)
      encryption_key=$(openssl rand -hex 32)
      auth_secret=$(openssl rand -hex 32)
      oidc_secret=$(cat "$in/kanidm-sparkyfitness-oidc/secret")

      cat > "$out/env" <<EOF
      SPARKY_FITNESS_DB_PASSWORD=$db_password
      SPARKY_FITNESS_APP_DB_PASSWORD=$app_db_password
      SPARKY_FITNESS_API_ENCRYPTION_KEY=$encryption_key
      BETTER_AUTH_SECRET=$auth_secret
      SPARKY_FITNESS_OIDC_AUTH_ENABLED=true
      SPARKY_FITNESS_OIDC_PROVIDER_NAME=Kanidm
      SPARKY_FITNESS_OIDC_PROVIDER_SLUG=kanidm
      SPARKY_FITNESS_OIDC_ISSUER_URL=https://idm.mulatta.io/oauth2/openid/sparkyfitness
      SPARKY_FITNESS_OIDC_CLIENT_ID=sparkyfitness
      SPARKY_FITNESS_OIDC_CLIENT_SECRET=$oidc_secret
      SPARKY_FITNESS_OIDC_ADMIN_GROUP=admins
      SPARKY_FITNESS_OIDC_SCOPE=openid email profile groups
      SPARKY_FITNESS_OIDC_AUTO_REGISTER=true
      SPARKY_FITNESS_OIDC_TOKEN_AUTH_METHOD=client_secret_basic
      EOF
    '';
  };

  # Keep automatic redirect disabled until first login proves end-to-end OIDC.
  # Environment-backed configuration upserts Kanidm on every service start.
  services.sparkyfitness = {
    enable = true;
    frontendUrl = "https://${domain}";
    environmentFile = config.clan.core.vars.generators.sparkyfitness.files.env.path;
    nginx.virtualHost = domain;
    port = 3011;
  };
}
