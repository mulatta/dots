{
  fetchFromGitHub,
  lib,
  tree-sitter,
}:

let
  version = "0.4.1";
in
tree-sitter.buildGrammar {
  language = "nextflow";
  inherit version;

  src = fetchFromGitHub {
    owner = "nextflow-io";
    repo = "tree-sitter-nextflow";
    rev = "v${version}";
    hash = "sha256-jnuP+E3Zn6vPc6HXmXuy7PyxFgD5KfcEWpRTea+di2Q=";
  };

  meta = {
    description = "Tree-sitter grammar for Nextflow";
    homepage = "https://github.com/nextflow-io/tree-sitter-nextflow";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
