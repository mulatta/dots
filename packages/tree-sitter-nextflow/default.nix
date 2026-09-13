{
  fetchFromGitHub,
  lib,
  tree-sitter,
}:

tree-sitter.buildGrammar rec {
  language = "nextflow";
  version = "0.3.0";

  src = fetchFromGitHub {
    owner = "nextflow-io";
    repo = "tree-sitter-nextflow";
    rev = "v${version}";
    hash = "sha256-nMQATg0dP15d+P+8/9f0tWNpSl8FgBIR/KW9smPHKVk=";
  };

  meta = {
    description = "Tree-sitter grammar for Nextflow";
    homepage = "https://github.com/nextflow-io/tree-sitter-nextflow";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
