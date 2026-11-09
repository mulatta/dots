# Shared so cask's knot and the host's lego hold the same TSIG secret.
# clan requires shared files to deploy alike; both hold the same secret.
{ pkgs, host }:
{
  share = true;
  files."knot-key.conf".secret = true;
  files.secret.secret = true;
  runtimeInputs = [ pkgs.openssl ];
  script = ''
    secret=$(openssl rand -base64 32 | tr -d '\n')
    printf '%s' "$secret" > "$out/secret"
    cat > "$out/knot-key.conf" <<EOF
    key:
      - id: ${host}.acme.mulatta.io
        algorithm: hmac-sha256
        secret: $secret
    EOF
  '';
}
