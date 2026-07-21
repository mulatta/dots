{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  makeWrapper,
  nodejs,
}:

stdenvNoCC.mkDerivation {
  pname = "archify-cli";
  version = "2.11.0";

  src = fetchFromGitHub {
    owner = "tt-a1i";
    repo = "archify";
    rev = "6d5204d23dfa2cbf3dfff423beeb32250a3dc727";
    hash = "sha256-PRPWBhwJGM56jKDn2jIOZbd8Y5hkqLhSDCF5NzFyEK0=";
  };

  nativeBuildInputs = [ makeWrapper ];

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

        substituteInPlace $out/share/skills/archify/SKILL.md \
          --replace-fail 'description: Create professional architecture, workflow, sequence, data-flow, and lifecycle/state diagrams as explorable standalone HTML files with SVG graphics, progressive MAP/READ/FULL Reading Depth, selective counted inline legends that enter a Semantic Lens with selection-triggered direction signals, directly operable and shareable stable relationships, exact-edge one-shot Relationship Preview pulses, pre-click Intent Trace path previews, two-endpoint Route Probe analysis, searchable semantic nodes, focus with Semantic Passport context, a live Semantic Radar overview, a Named Chapter Rail with pre-commit Chapter Delta Preview, Shared Anchor Handoff, a directly inspectable Story Beat Navigator with Story Follow Camera, factual Story Director Strip, and one-step Story Horizon, stable Shareable Story Moment links, a reader-controlled Live/Still Motion Governor, Presentation Stage, dependency-free pan/zoom, dark/light themes, optional motion styling, and one-click export to PNG / JPEG / WebP / SVG / WebM. Accepts plain-language descriptions or pasted Mermaid code (flowchart, sequenceDiagram, stateDiagram) and lays the diagram out from scratch in archify style. Use when the user asks for system architecture diagrams, infrastructure diagrams, cloud architecture visualizations, security diagrams, network topology, technical workflows, approval flows, runbooks, CI/CD flows, process diagrams, API call sequences, request lifecycles, data pipelines, ETL/ELT maps, PII boundaries, data lineage, state machines, lifecycle diagrams, status transitions, or asks to convert/beautify a Mermaid diagram.' 'description: Create interactive architecture, workflow, sequence, dataflow, and lifecycle diagrams as self-contained HTML/SVG artifacts. Use for system architecture, infrastructure, security, network topology, process/runbook/CI-CD flows, API call sequences, request lifecycles, data pipelines, PII boundaries, data lineage, state machines, lifecycle/status transitions, or converting Mermaid into Archify-style diagrams. Defaults reader-facing diagram text to Korean unless user asks otherwise.' \
          --replace-fail '# Archify Skill

    Create professional technical diagrams' '# Archify Skill

    ## Local Output Language

    Default every newly authored diagram to Korean for reader-facing text unless the user explicitly asks for another language. Keep stable ids, relationship ids, filenames, CLI commands, JSON keys, and schema enum values in ASCII English for deep links and validation. Write Korean in title, subtitle, labels, sublabels, tags, cards, view labels, and view notes. Keep node labels short and move longer explanation into cards or notes to avoid CJK layout overlap.

    Create professional technical diagrams' \
          --replace-fail '`node bin/archify.mjs doctor`' '`archify doctor`' \
          --replace-fail '`node bin/archify.mjs demo [output-directory]`' '`archify demo [output-directory]`' \
          --replace-fail '`node bin/archify.mjs guide ' '`archify guide ' \
          --replace-fail '`node bin/archify.mjs render ' '`archify render ' \
          --replace-fail '`node bin/archify.mjs validate ' '`archify validate ' \
          --replace-fail '`node bin/archify.mjs check ' '`archify check ' \
          --replace-fail 'node bin/archify.mjs inspect ' 'archify inspect ' \
          --replace-fail 'node bin/archify.mjs validate architecture my.architecture.json --layout-json' 'archify validate architecture my.architecture.json --layout-json'

        runHook postInstall
  '';

  doInstallCheck = true;

  installCheckPhase = ''
    runHook preInstallCheck
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
