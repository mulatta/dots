{
  self,
  config,
  pkgs,
  ...
}:
let
  domain = "auth.mulatta.io";
  baseDomain = "mulatta.io";

  stalwartOidcSecretPath = config.clan.core.vars.generators.stalwart-oidc.files."client-secret".path;
  adminPasswordPath = config.clan.core.vars.generators.authentik-admin.files."password".path;

  # Use version-2025.10 branch HEAD which includes fix for docs build (PR #19148)
  fixedAuthentikSrc = pkgs.fetchFromGitHub {
    owner = "goauthentik";
    repo = "authentik";
    rev = "cd04a205b43bc787586e788d09762ffb24c8a225";
    hash = "sha256-Mty9SITtyGvnVxFpJd4X9qS+5/nOp9cfUpB0le1RkDs=";
  };

  # Override authentik source for docs build fix
  patchedAuthentikScope =
    let
      baseScope = self.inputs.authentik-nix.lib.mkAuthentikScope { inherit pkgs; };
    in
    baseScope.overrideScope (
      _final: _prev: {
        authentik-src = fixedAuthentikSrc;
        buildGo124Module = pkgs.buildGo125Module;
      }
    );

  # Merge default blueprints with custom blueprints
  mergedBlueprints = pkgs.runCommand "authentik-merged-blueprints" { } ''
    mkdir -p $out
    # Copy default blueprints from authentik source
    cp -r ${fixedAuthentikSrc}/blueprints/* $out/
    # Add custom blueprints
    mkdir -p $out/custom
    cp ${./blueprints/stalwart.yaml} $out/custom/stalwart.yaml
    cp ${./blueprints/users.yaml} $out/custom/users.yaml
  '';
in
{
  imports = [ self.inputs.authentik-nix.nixosModules.default ];

  clan.core.vars.generators.authentik-secrets = {
    files."env".secret = true;
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      SECRET_KEY=$(openssl rand -base64 60 | tr -d '\n')
      POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d '\n')
      cat > "$out/env" << EOF
      AUTHENTIK_SECRET_KEY=$SECRET_KEY
      AUTHENTIK_POSTGRESQL__PASSWORD=$POSTGRES_PASSWORD
      EOF
    '';
  };

  clan.core.vars.generators.authentik-admin = {
    files."password".secret = true;
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      openssl rand -base64 24 | tr -d '\n' > "$out/password"
    '';
  };

  # Generate environment file with secrets at runtime
  systemd.services.authentik-env = {
    description = "Generate Authentik environment with secrets";
    before = [
      "authentik.service"
      "authentik-worker.service"
    ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      cat > /run/authentik-blueprints.env << EOF
      STALWART_OIDC_CLIENT_SECRET=$(cat ${stalwartOidcSecretPath})
      AUTHENTIK_ADMIN_PASSWORD=$(cat ${adminPasswordPath})
      EOF
      chmod 400 /run/authentik-blueprints.env
    '';
  };

  services.authentik = {
    enable = true;
    environmentFile = config.clan.core.vars.generators.authentik-secrets.files."env".path;

    # Use patched components
    inherit (patchedAuthentikScope) authentikComponents;

    settings = {
      disable_startup_analytics = true;
      avatars = "initials";

      # Use merged blueprints (default + custom)
      blueprints_dir = mergedBlueprints;

      email = {
        host = "mail.${baseDomain}";
        port = 587;
        use_tls = true;
        from = "authentik@${baseDomain}";
      };
    };
  };

  # Add blueprint secrets env to authentik services
  systemd.services.authentik.serviceConfig.EnvironmentFile = [
    config.clan.core.vars.generators.authentik-secrets.files."env".path
    "/run/authentik-blueprints.env"
  ];
  systemd.services.authentik-worker.serviceConfig.EnvironmentFile = [
    config.clan.core.vars.generators.authentik-secrets.files."env".path
    "/run/authentik-blueprints.env"
  ];

  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    enableACME = true;

    locations."/" = {
      proxyPass = "http://127.0.0.1:9000";
      proxyWebsockets = true;
    };
  };
}
