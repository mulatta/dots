{
  buildNpmPackage,
  fetchurl,
  lib,
}:

buildNpmPackage (finalAttrs: {
  pname = "openknowledge";
  version = "0.79.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@inkeep/open-knowledge/-/open-knowledge-${finalAttrs.version}.tgz";
    hash = "sha256-NrFFKplJ4I/H39sJ8ZTiMUdMo4q05dodIL1n7yC1WxA=";
  };

  postPatch = ''
    cp ${./package.json} package.json
    cp ${./package-lock.json} package-lock.json
  '';

  npmDepsHash = "sha256-TginCHgV8hPtBCibGOqSNk0lMnRuUjV7pwFvTBYevNM=";

  dontNpmBuild = true;

  meta = {
    description = "Local-first Markdown knowledge base with agent integrations";
    homepage = "https://openknowledge.ai";
    downloadPage = "https://www.npmjs.com/package/@inkeep/open-knowledge";
    license = lib.licenses.gpl3Plus;
    mainProgram = "ok";
    platforms = lib.platforms.all;
  };
})
