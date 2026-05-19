{
  lib,
  stdenv,
  python3Packages,
  makeWrapper,
  calendar-cli,
  crabfit-cli,
  vdirsyncer,
  todoman,
  notmuch,
  afew,
  mblaze,
  msmtp-with-sent,
  n8n-hooks,
  miniflux-cli,
  vikunja-cli,
  isync,
  khard,
  email-sync,
  rbw,
  coreutils,
  gnugrep,
  gnused,
  gawk,
  jq,
  findutils,
  bash,
  ncurses,
  util-linux,
  bubblewrap,
  pi,
  nodePath ? null,
}:

let
  toolsPath = lib.makeBinPath (
    [
      calendar-cli
      crabfit-cli
      vdirsyncer
      todoman
      notmuch
      afew
      mblaze
      msmtp-with-sent
      n8n-hooks
      miniflux-cli
      vikunja-cli
      isync
      khard
      email-sync
      rbw
      coreutils
      gnugrep
      gnused
      gawk
      jq
      findutils
      bash
      ncurses
    ]
    ++ lib.optionals stdenv.isLinux [
      util-linux
    ]
  );

  runtimeDeps = lib.optionals stdenv.isLinux [ bubblewrap ];
in
python3Packages.buildPythonApplication {
  pname = "pim";
  version = "0.1.0";
  src = ./.;
  format = "other";

  nativeBuildInputs = [ makeWrapper ];

  # Domain-specific skills stay local to pim so the default pi profile can
  # remain a narrower general-purpose Mic92-style setup.
  installPhase = ''
    runHook preInstall

    install -D -m 0755 pim.py $out/bin/pim

    wrapProgram $out/bin/pim \
      --set PIM_TOOLS_PATH ${lib.escapeShellArg toolsPath} \
      --set PIM_PI_BIN ${pi}/bin/pi \
      --set PIM_SKILL_PATHS ${lib.escapeShellArg "${crabfit-cli}/share/skills/crabfit-cli:${miniflux-cli}/share/skills/miniflux-cli:${vikunja-cli}/share/skills/vikunja-cli"} \
      ${lib.optionalString (nodePath != null) "--set NODE_PATH ${lib.escapeShellArg nodePath} \\"}
      --prefix PATH : ${lib.makeBinPath runtimeDeps}

    runHook postInstall
  '';

  meta = {
    description = "Focused pi wrapper for local calendar, mail, and contacts workflows";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
    mainProgram = "pim";
  };
}
