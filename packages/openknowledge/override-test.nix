{
  package,
  lib,
  runCommand,
}:
let
  version = "0.0.0-override-test";
  overridden = package.overrideAttrs {
    inherit version;
    src = package.src.override { tag = "v${version}"; };
  };
  # Evaluation only: these sentinel sources and hashes must never be fetched.
  checks = [
    (overridden.src.rev == "refs/tags/v${version}")
    (lib.hasSuffix "/v${version}" overridden.meta.changelog)
    (overridden.cargoDeps.name == "openknowledge-native-config-${version}-vendor")
    (lib.hasInfix "--arg version ${version}" overridden.preBuild)
  ];
in
assert lib.assertMsg (lib.all (
  passed: passed
) checks) "OpenKnowledge version overrides must reach source, vendor, metadata, and build inputs";
runCommand "openknowledge-override-test" { } ''
  touch "$out"
''
