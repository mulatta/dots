{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule (finalAttrs: {
  pname = "herdr-sesh";
  version = "0.15.0";

  src = fetchFromGitHub {
    owner = "fullerzz";
    repo = "herdr-plugin-sesh";
    rev = "v${finalAttrs.version}";
    hash = "sha256-sHqlqQWoPWOJTVBlEvV6js0Wwk6ehMoa6uJx07Cg0+g=";
  };

  vendorHash = "sha256-3v8D4Gblg/4REwiYCCPaDete8K+6ngzvdWnfJjbQ+O4=";

  subPackages = [ "cmd/herdr-sesh" ];

  ldflags = [ "-X=github.com/fullerzz/herdr-plugin-sesh/internal/app.Version=${finalAttrs.version}" ];

  # Ship as a herdr plugin directory: manifest at the root, binary under bin/,
  # matching the "./bin/herdr-sesh" commands in the manifest.
  postInstall = ''
    cp herdr-plugin.toml $out/
  '';

  meta = {
    description = "Sesh-style workspace picker for herdr";
    homepage = "https://github.com/fullerzz/herdr-plugin-sesh";
    license = lib.licenses.mit;
    mainProgram = "herdr-sesh";
  };
})
