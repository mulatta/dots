{
  fetchFromGitHub,
  lib,
  tree-sitter,
}:

tree-sitter.buildGrammar rec {
  language = "nextflow";
  version = "0.4.0";

  src = fetchFromGitHub {
    owner = "nextflow-io";
    repo = "tree-sitter-nextflow";
    rev = "v${version}";
    hash = "sha256-WcqkGvd/NHzsdMt88pjyS02EFPAinljnETOb4FQrgR4=";
  };

  meta = {
    description = "Tree-sitter grammar for Nextflow";
    homepage = "https://github.com/nextflow-io/tree-sitter-nextflow";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
