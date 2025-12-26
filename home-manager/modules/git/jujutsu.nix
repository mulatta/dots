{
  config,
  pkgs,
  ...
}:
let
  gitCfg = config.programs.git;
in
{
  programs.jujutsu = {
    enable = true;
    settings = {
      user.email = gitCfg.settings.user.email;
      user.name = gitCfg.settings.user.name;

      ui = {
        pager = "less -FRX";
        show-cryptographix-signatures = true;
        default-command = [
          "log"
          "--reversed"
        ];
      };

      aliases = {
        l = [
          "log"
          "-r"
          "all()"
          "--template"
          "builtin_log_compact"
          "--reversed"
        ];
        s = [ "show" ];
        d = [ "describe" ];
      };

      signing = {
        backend = "ssh";
        behaviour = "own";
        key = gitCfg.signing.key;
        backends.ssh = {
          program = gitCfg.signing.signer;
        };
      };

      templates = {
        file_annotate = ''
          commit_id.short() ++ " (" ++
          author.name() ++ " " ++
          author.timestamp().ago() ++
          ") "
        '';
      };

      template-aliases = {
        "format_short_signature(signature)" = "signature.name()";
        "format_timestamp(timestamp)" = "timestamp.ago()";
        "format_short_id(id)" = "id.shortest(8)";
      };
    };
  };

  home.packages = [ pkgs.jjui ];
}
