{
  buildNpmPackage,
  fetchurl,
  installAgentSkills,
  lib,
}:

buildNpmPackage (finalAttrs: {
  pname = "openknowledge";
  version = "0.81.4";

  src = fetchurl {
    url = "https://registry.npmjs.org/@inkeep/open-knowledge/-/open-knowledge-${finalAttrs.version}.tgz";
    hash = "sha256-AFhOJ+UEDzvLxGuSsQsMViARFVEhENUluYBT7HqXyM0=";
  };

  postPatch = ''
    cp ${./package.json} package.json
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-ep0h+ZXaHmPjN4bLnJoAyYBXH0IkgwH5M611ODZ/LiU=";

  nativeBuildInputs = [ installAgentSkills ];
  dontInstallAgentSkills = true;
  postInstall = ''
    installSkill dist/assets/skills/discovery openknowledge
  '';

  dontNpmBuild = true;

  doInstallCheck = true;
  installCheckPhase = ''
    test -f $out/share/skills/openknowledge/discovery/SKILL.md
  '';

  meta = {
    description = "Local-first Markdown knowledge base with agent integrations";
    homepage = "https://openknowledge.ai";
    downloadPage = "https://www.npmjs.com/package/@inkeep/open-knowledge";
    license = lib.licenses.gpl3Plus;
    mainProgram = "ok";
    platforms = lib.platforms.all;
  };
})
