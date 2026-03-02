{
  lib,
  craneLib,
  fetchFromGitHub,
  installShellFiles,
  runtimeShell,
}:
let
  version = "3.6.0";

  src = fetchFromGitHub {
    owner = "skim-rs";
    repo = "skim";
    tag = "v${version}";
    hash = "sha256-kNE9atMZOeJbH8KK7MCIKFfEFeUhFKY3b6898HCmtYQ=";
  };

  commonArgs = {
    inherit src version;
    pname = "skim";
    nativeBuildInputs = [ installShellFiles ];
    # Tests require tmux and TTY
    doCheck = false;
  };

  cargoArtifacts = craneLib.buildDepsOnly commonArgs;
in
craneLib.buildPackage (
  commonArgs
  // {
    inherit cargoArtifacts;

    postPatch = ''
      sed -i -e "s|expand('<sfile>:h:h')|'$out'|" plugin/skim.vim
    '';

    postInstall = ''
      install -Dm755 bin/sk-tmux $out/bin/sk-tmux
      install -D -m 444 plugin/skim.vim -t $out/share/vim-plugins/skim/plugin
      install -D -m 444 shell/* -t $out/share/skim

      cat > $out/bin/sk-share <<SCRIPT
      #! ${runtimeShell}
      # Run this script to find the skim shared folder where all the shell
      # integration scripts are living.
      echo $out/share/skim
      SCRIPT
      chmod +x $out/bin/sk-share

      installManPage man/man1/*
      installShellCompletion \
        --cmd sk \
        --bash shell/completion.bash \
        --fish shell/completion.fish \
        --zsh shell/completion.zsh
    '';

    meta = {
      description = "Command-line fuzzy finder written in Rust";
      homepage = "https://github.com/skim-rs/skim";
      license = lib.licenses.mit;
      mainProgram = "sk";
    };
  }
)
