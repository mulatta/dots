{
  lib,
  buildNpmPackage,
}:
buildNpmPackage {
  pname = "dbml-cli";
  version = "8.2.1";

  src = ./.;

  npmDepsHash = "sha256-BsEDaUIZSn3deCHkktHRypTF7PrVY86UpLGhyokneCc=";

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/lib
    cp -r node_modules $out/lib/

    for bin in dbml2sql sql2dbml; do
      cat > $out/bin/$bin <<EOF
    #!/usr/bin/env node
    require('$out/lib/node_modules/@dbml/cli/bin/$bin.js');
    EOF
      chmod +x $out/bin/$bin
    done

    runHook postInstall
  '';

  meta = {
    description = "Database Markup Language CLI - convert between DBML and SQL";
    homepage = "https://dbml.dbdiagram.io";
    license = lib.licenses.asl20;
    mainProgram = "dbml2sql";
  };
}
