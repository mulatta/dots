{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule (finalAttrs: {
  pname = "herdr-sesh";
  version = "0.14.0";

  src = fetchFromGitHub {
    owner = "fullerzz";
    repo = "herdr-plugin-sesh";
    rev = "v${finalAttrs.version}";
    hash = "sha256-dNFgiZeEbI0ByLXH8PFl1KudalFtYbc6cmgkls8EHn8=";
  };

  vendorHash = "sha256-ZUUMJxW84MBOZ/Xw/FmxFRTSzsvPQM3uhqUi0QSt9Fc=";

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
