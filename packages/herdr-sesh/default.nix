{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule (finalAttrs: {
  pname = "herdr-sesh";
  version = "0.17.0";

  src = fetchFromGitHub {
    owner = "fullerzz";
    repo = "herdr-plugin-sesh";
    rev = "v${finalAttrs.version}";
    hash = "sha256-Rm2BGvAW/D0iNr3RXpcRcQkkLO/Wor48CJ0BhduW35M=";
  };

  vendorHash = "sha256-WfgGf5bTsspAmMii9FdCQCuCuTCPt6aIt8S5B6AMDvs=";

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
