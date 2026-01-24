{
  lib,
  python3Packages,
  makeWrapper,
  sieve-connect,
  rbw,
}:
python3Packages.buildPythonApplication {
  pname = "sieve-sync";
  version = "0.1.0";
  format = "other";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp sieve_sync.py $out/bin/sieve-sync
    chmod +x $out/bin/sieve-sync

    wrapProgram $out/bin/sieve-sync \
      --prefix PATH : ${
        lib.makeBinPath [
          sieve-connect
          rbw
        ]
      }

    runHook postInstall
  '';

  meta = with lib; {
    description = "Sieve synchronization tool";
    license = licenses.mit;
    mainProgram = "sieve-sync";
  };
}
