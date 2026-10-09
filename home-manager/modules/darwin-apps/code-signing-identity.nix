# This makes side-effects on your MacOS system keychain
# to manage your MacOS Apps with permissions declaratively.
{
  lib,
  writeShellApplication,
  openssl,
}:

writeShellApplication {
  name = "code-signing-identity";
  runtimeInputs = [ openssl ];
  text = ''
    identity="dots local code signing"
    keychain="$HOME/Library/Keychains/login.keychain-db"

    fingerprint() {
      openssl x509 -noout -fingerprint -sha1 | cut -d= -f2 | tr -d : | tr '[:upper:]' '[:lower:]'
    }

    if /usr/bin/security find-certificate -c "$identity" -p "$keychain" > /dev/null 2>&1; then
      echo "Identity \"$identity\" already exists; refusing to rotate it." >&2
      /usr/bin/security find-certificate -c "$identity" -p "$keychain" | fingerprint
      exit 0
    fi

    umask 077
    stage=$(mktemp -d)
    trap 'rm -rf "$stage"' EXIT

    openssl req -x509 -newkey rsa:3072 -nodes -days 3650 -sha256 \
      -subj "/CN=$identity" \
      -addext "basicConstraints=critical,CA:false" \
      -addext "keyUsage=critical,digitalSignature" \
      -addext "extendedKeyUsage=critical,codeSigning" \
      -keyout "$stage/key.pem" -out "$stage/cert.pem" 2> /dev/null

    # The transport password only lives in this process; security(1) rejects
    # OpenSSL 3's default PKCS#12 ciphers, hence -legacy.
    CODE_SIGNING_P12_PASSWORD=$(openssl rand -hex 24)
    export CODE_SIGNING_P12_PASSWORD
    openssl pkcs12 -export -legacy -name "$identity" \
      -inkey "$stage/key.pem" -in "$stage/cert.pem" \
      -out "$stage/identity.p12" -passout env:CODE_SIGNING_P12_PASSWORD
    /usr/bin/security import "$stage/identity.p12" -k "$keychain" \
      -P "$CODE_SIGNING_P12_PASSWORD" -T /usr/bin/codesign
    unset CODE_SIGNING_P12_PASSWORD

    # codesign refuses untrusted leaves; trust it for code signing only.
    /usr/bin/security add-trusted-cert -r trustRoot -p codeSign -k "$keychain" "$stage/cert.pem"
    # Lets codesign use the key during activation without a keychain prompt.
    /usr/bin/security set-key-partition-list -S apple-tool:,apple:,codesign: -s -l "$identity" "$keychain" > /dev/null

    echo "Set targets.darwin.codeSigning.certificateSha1 to:" >&2
    fingerprint < "$stage/cert.pem"
  '';

  meta = {
    description = "Create the login keychain identity used to re-sign TCC-sensitive apps";
    platforms = lib.platforms.darwin;
  };
}
