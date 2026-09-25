{
  buildNpmPackage,
  fetchFromGitHub,
  lib,
  makeWrapper,
  pi,
}:
buildNpmPackage rec {
  pname = "pi-acp";
  version = "0.0.34";

  src = fetchFromGitHub {
    owner = "svkozak";
    repo = "pi-acp";
    tag = "v${version}";
    hash = "sha256-QRwxOtTZOY+Np3PkAoy2o2PrUzEqjItM/372sCPlSMo=";
  };

  npmDepsHash = "sha256-BvLNtFfp1cMVjzWcMRSdhTqiJrTfbFoUbWkkPW9200o=";

  nativeBuildInputs = [ makeWrapper ];

  postInstall = ''
    wrapProgram $out/bin/pi-acp \
      --prefix PATH : ${lib.makeBinPath [ pi ]}
  '';

  meta = {
    description = "ACP adapter for pi coding agent";
    homepage = "https://github.com/svkozak/pi-acp";
    license = lib.licenses.mit;
    mainProgram = "pi-acp";
  };
}
