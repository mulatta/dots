{
  lib,
  buildGoModule,
  fetchFromGitHub,
  installAgentSkills,
  installShellFiles,
  stdenv,
}:

buildGoModule (finalAttrs: {
  pname = "maiao";
  version = "1.8.1";

  src = fetchFromGitHub {
    owner = "runetes";
    repo = "maiao";
    tag = "maiao-v${finalAttrs.version}";
    hash = "sha256-DhEFhZ+6gH+O29ge2jefEbvSq62i4bOotLrowJh+W/s=";
  };

  vendorHash = "sha256-ccuTrhRrH+Qe9VwIKSK9rQYcYtrB8YO3pODbMT5/sVc=";

  overrideModAttrs = oldAttrs: {
    nativeBuildInputs = lib.remove installShellFiles (
      lib.remove installAgentSkills oldAttrs.nativeBuildInputs
    );
    preInstall = null;
    postInstall = null;
  };

  subPackages = [ "cmd/maiao" ];

  ldflags = [
    "-s"
    "-w"
    "-X github.com/runetes/maiao/pkg/version.Version=${finalAttrs.version}"
  ];

  nativeBuildInputs = [
    installAgentSkills
    installShellFiles
  ];
  dontInstallAgentSkills = true;

  preInstall = ''
    installSkill skills/maiao/skills/git-review
  '';

  # Upstream ships the binary as git-review so it works as `git review`.
  postInstall = ''
    mv $out/bin/maiao $out/bin/git-review
  ''
  + lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    installShellCompletion --cmd git-review \
      --bash <($out/bin/git-review completion bash) \
      --fish <($out/bin/git-review completion fish) \
      --zsh <($out/bin/git-review completion zsh)
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    $out/bin/git-review version | grep -q "^${finalAttrs.version}$"
    test -f "$out/share/skills/maiao/git-review/SKILL.md"
    test -f "$out/share/skills/maiao/git-review/operations.md"
  '';

  meta = {
    description = "Seamless GitHub PR management from the command-line (stacked PRs)";
    homepage = "https://github.com/runetes/maiao";
    license = lib.licenses.mit;
    mainProgram = "git-review";
  };
})
