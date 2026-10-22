{
  lib,
  buildPythonPackage,
  hatchling,
  pytestCheckHook,
  ruff,
  runCommand,
  noto-fonts-cjk-sans-static,
  noto-fonts-cjk-serif-static,
  nanum,
  dejavu_fonts,
  poppler-utils,
  rhwp,
}:

let
  # Variable CJK fonts break rhwp's subsetter and drop the text layer.
  fontDir = runCommand "rhwp-fonts" { } ''
    mkdir -p $out
    find -L ${noto-fonts-cjk-sans-static} ${noto-fonts-cjk-serif-static} ${nanum} \
      -name '*.[ot]t[fc]' -exec ln -s {} $out/ \;
    # Fallback for symbols CJK fonts lack (U+22C5); one font, as rhwp picks by directory order.
    ln -s ${dejavu_fonts}/share/fonts/truetype/DejaVuSans.ttf $out/
  '';
in
buildPythonPackage {
  pname = "paperless-rhwp";
  version = "0.1.0";
  pyproject = true;

  src = ./.;

  postPatch = ''
    substituteInPlace paperless_rhwp/__init__.py \
      --replace-fail '@rhwp@' '${lib.getExe' rhwp "rhwp"}' \
      --replace-fail '@pdftotext@' '${lib.getExe' poppler-utils "pdftotext"}' \
      --replace-fail '@fontDir@' '${fontDir}'
  '';

  build-system = [ hatchling ];

  nativeCheckInputs = [
    pytestCheckHook
    ruff
  ];

  preCheck = ''
    # Substituted store paths exceed the line length.
    ruff format --no-cache --check $src
    ruff check --no-cache $src
    export RHWP_SAMPLES=${rhwp.src}/samples
  '';

  pythonImportsCheck = [ "paperless_rhwp" ];

  meta = {
    description = "Paperless-ngx parser for HWP/HWPX documents via rhwp";
    license = lib.licenses.mit;
  };
}
