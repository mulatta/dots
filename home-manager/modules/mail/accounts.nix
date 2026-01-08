{
  config,
  pkgs,
  ...
}:
let
  maildir = "${config.home.homeDirectory}/mail";
  certFile =
    if pkgs.stdenv.isDarwin then "/etc/ssl/cert.pem" else "/etc/ssl/certs/ca-certificates.crt";
in
{
  accounts.email = {
    maildirBasePath = maildir;
    accounts.mulatta = {
      primary = true;
      address = "seungwon@mulatta.io";
      userName = "seungwon@mulatta.io";
      realName = "seungwon";
      passwordCommand = "rbw get 'mulatta.io'";

      imap = {
        host = "mail.mulatta.io";
        port = 993;
        tls.enable = true;
      };

      smtp = {
        host = "mail.mulatta.io";
        port = 465;
        tls.enable = true;
      };

      mbsync = {
        enable = true;
        create = "both";
        expunge = "both";
        patterns = [
          "*"
          "!Shared Folders"
          "!Shared Folders/*"
        ];
        extraConfig.account = {
          TLSType = "IMAPS";
          CertificateFile = certFile;
        };
        extraConfig.local = {
          SubFolders = "Verbatim";
        };
      };

      aerc = {
        enable = true;
        extraAccounts = {
          source = "notmuch://${maildir}";
          outgoing = "msmtp";
          default = "INBOX";
          copy-to = "Sent";
          archive = "Archive";
          postpone = "Drafts";
          query-map = "${maildir}/query-map";
          maildir-store = "${maildir}/mulatta";
          multi-file-strategy = "act-all";
        };
      };

      msmtp = {
        enable = true;
        extraConfig = {
          tls_starttls = "off";
        };
      };

      notmuch.enable = true;
    };
  };
}
