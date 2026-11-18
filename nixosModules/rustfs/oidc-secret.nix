{
  pkgs,
  owner ? "root",
}:
{
  share = true;
  files.client-secret = {
    secret = true;
    inherit owner;
  };
  files.env.secret = true;
  runtimeInputs = [ pkgs.openssl ];
  script = ''
    client_secret=$(openssl rand -hex 32 | tr -d '\n')
    printf '%s' "$client_secret" > "$out/client-secret"
    printf 'RUSTFS_IDENTITY_OPENID_CLIENT_SECRET_kanidm=%s\n' "$client_secret" > "$out/env"
  '';
}
