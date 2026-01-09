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
        st = [ "status" ];

        # Log
        l = [
          "log"
          "-r"
          "all()"
          "--template"
          "builtin_log_compact"
          "--reversed"
        ];
        lr = [
          "log"
          "-r"
        ];
        la = [
          "log"
          "-r"
          "all()"
        ];

        # Show
        s = [ "show" ];
        ss = [
          "show"
          "--summary"
        ];
        sg = [
          "show"
          "--git"
        ];

        # Describe
        d = [ "describe" ];
        dm = [
          "describe"
          "-m"
        ];

        # Diff
        df = [ "diff" ];
        dfs = [
          "diff"
          "--stat"
        ];
        dfc = [
          "diff"
          "--color-words"
        ];
        dfg = [
          "diff"
          "--git"
        ];

        # New
        n = [ "new" ];
        nn = [
          "new"
          "--no-edit"
        ];
        na = [
          "new"
          "-A"
        ];
        nb = [
          "new"
          "-B"
        ];
        nna = [
          "new"
          "--no-edit"
          "-A"
        ];
        nnb = [
          "new"
          "--no-edit"
          "-B"
        ];

        # Edit / Navigation
        e = [ "edit" ];
        pr = [ "prev" ];
        nx = [ "next" ];

        # Bookmark
        bs = [
          "bookmark"
          "set"
        ];
        bl = [
          "bookmark"
          "list"
        ];
        bt = [
          "bookmark"
          "track"
        ];
        bd = [
          "bookmark"
          "delete"
        ];
        bf = [
          "bookmark"
          "forget"
        ];
        bm = [
          "bookmark"
          "move"
        ];
        br = [
          "bookmark"
          "rename"
        ];

        # Git
        gf = [
          "git"
          "fetch"
        ];
        gp = [
          "git"
          "push"
        ];
        gpa = [
          "git"
          "push"
          "--all"
        ];
        gpb = [
          "git"
          "push"
          "--bookmark"
        ];
        gpc = [
          "git"
          "push"
          "--change"
        ];
        gpd = [
          "git"
          "push"
          "--deleted"
        ];
        gcl = [
          "git"
          "clone"
        ];

        # Rebase
        rb = [ "rebase" ];
        rbr = [
          "rebase"
          "-r"
        ];
        rbs = [
          "rebase"
          "-s"
        ];
        rbd = [
          "rebase"
          "-d"
        ];

        # Resolve
        rs = [ "resolve" ];
        rsr = [
          "resolve"
          "-r"
        ];
        rsl = [
          "resolve"
          "--list"
        ];

        # Squash / Split / Fix
        sq = [ "squash" ];
        sp = [ "split" ];
        fx = [ "fix" ];

        # Abandon / Absorb
        a = [ "abandon" ];
        abs = [ "absorb" ];

        # File
        fa = [
          "file"
          "annotate"
        ];
        fl = [
          "file"
          "list"
        ];
        fc = [
          "file"
          "chmod"
        ];
        fs = [
          "file"
          "show"
        ];

        # History / Operation
        el = [ "evolog" ];
        ol = [
          "op"
          "log"
        ];

        # Stack Workflow
        nt = [
          "new"
          "trunk()"
        ];
        stack = [
          "log"
          "-r"
          "stack()"
        ];
        open = [
          "log"
          "-r"
          "open()"
        ];
        examine = [
          "log"
          "-r"
          "@"
          "-p"
          "--git"
        ];

        # Rebase to trunk
        rom = [
          "rebase"
          "-d"
          "trunk()"
        ];
        sandwich = [
          "rebase"
          "-r"
          "@"
          "-d"
          "trunk()"
        ];
        ram = [
          "rebase"
          "-s"
          "all:roots(mutable())"
          "-d"
          "trunk()"
        ];
        consume = [
          "squash"
          "--from"
          "@-"
          "--into"
          "@"
        ];
        eject = [
          "squash"
          "--from"
          "@"
          "--into"
          "@-"
        ];
      };

      signing = {
        backend = "ssh";
        behaviour = "true";
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

      revset-aliases = {
        "trunk()" = "main@origin | present(master@origin)";
        "mine()" = "author(exact:${builtins.toJSON gitCfg.userEmail})";
        "draft()" = "mutable() ~ ::remote_bookmarks()";
        "stack()" = "trunk()..@";
        "open()" = "stack() & draft()";
        "wip()" = ''description(glob:"wip:*") | description(glob:"WIP:*")'';
        "ready()" = "heads(stack()) & draft() & ~wip()";
        "unpushed()" = "remote_bookmarks()..@";
      };
    };
  };

  home.packages = [ pkgs.jjui ];
}
