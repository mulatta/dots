{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  installAgentSkills,
  makeWrapper,
  nodejs,
}:

stdenvNoCC.mkDerivation rec {
  pname = "archify-cli";
  version = "3.0.1";

  src = fetchFromGitHub {
    owner = "tt-a1i";
    repo = "archify";
    rev = "v${version}";
    hash = "sha256-i7+M5PdQkGiC/Sow9Vtfh+ZHnOMVM9uBOtdzkKZhzLY=";
  };

  nativeBuildInputs = [
    installAgentSkills
    makeWrapper
  ];
  dontInstallAgentSkills = true;

  preInstall = ''
    installSkill archify
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share/skills $out/share/doc/archify
    cp -r archify $out/share/skills/archify
    for example in examples/*; do
      target=$out/share/skills/archify/examples/$(basename "$example")
      if [ ! -e "$target" ]; then
        cp -r "$example" "$target"
      fi
    done
    cp -r docs $out/share/skills/archify/docs
    cp README.md README_ZH.md CHANGELOG.md ROADMAP.md $out/share/doc/archify/
    cp LICENSE $out/share/doc/archify/LICENSE

    makeWrapper ${nodejs}/bin/node $out/bin/archify \
      --add-flags "$out/share/skills/archify/bin/archify.mjs"

    runHook postInstall
  '';

  doInstallCheck = true;

  installCheckPhase = ''
    runHook preInstallCheck
    test -f $out/share/skills/archify-cli/archify/SKILL.md
    $out/bin/archify doctor
    $out/bin/archify validate architecture $out/share/skills/archify/examples/web-app.architecture.json
    runHook postInstallCheck
  '';

  meta = {
    description = "Generate checked interactive architecture/workflow/sequence/dataflow/lifecycle diagrams";
    homepage = "https://github.com/tt-a1i/archify";
    license = lib.licenses.mit;
    mainProgram = "archify";
    platforms = nodejs.meta.platforms;
  };
}
