{ config, ... }:
let
  gitCfg = config.programs.git;
in
{
  programs.jujutsu = {
    enable = true;
    settings = {
      user.email = gitCfg.userEmail;
      user.name = gitCfg.userName;
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

      template-aliases = {
        "format_short_signature(signature)" = "signature.name()";
        "format_timestamp(timestamp)" = "timestamp.ago()";
        "format_short_id(id)" = "id.shortest(8)";
      };
    };
  };
}
