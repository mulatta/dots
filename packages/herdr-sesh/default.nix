{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule (finalAttrs: {
  pname = "herdr-sesh";
  version = "0.16.0";

  src = fetchFromGitHub {
    owner = "fullerzz";
    repo = "herdr-plugin-sesh";
    rev = "v${finalAttrs.version}";
    hash = "sha256-w7a6mSxxAhrU7lXTPGjawXx+ZBRAgc8VqjrY9y5Ybjc=";
  };

  vendorHash = "sha256-z8ni2u80UH4WfpmeS3x7KBN2IUb8F6sSOjQB5v1mM/E=";

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
