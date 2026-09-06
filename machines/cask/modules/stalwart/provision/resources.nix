{
  principals = [
    {
      type = "domain";
      name = "mulatta.io";
      description = "mulatta.io";
    }
    {
      type = "oauthClient";
      name = "bulwark-webmail";
      description = "Bulwark Webmail";
      urls = map (language: "https://mail.mulatta.io/${language}/auth/callback") [
        "cs"
        "en"
        "fr"
        "de"
        "es"
        "it"
        "ja"
        "ko"
        "lv"
        "nl"
        "pl"
        "pt"
        "ru"
        "tr"
        "uk"
        "zh"
      ];
    }
    {
      type = "oauthClient";
      name = "webadmin";
      description = "Stalwart Webadmin";
      urls = [ "stalwart://auth" ];
    }
  ];

  mailboxAcls = [
    {
      account = "seungwon";
      role = "inbox";
      shareWith = {
        noa = [
          "mayReadItems"
          # Stalwart derives maySetSeen from maySetKeywords and refuses to
          # clear it, so it is declared to keep the mailbox converged.
          "maySetSeen"
          "maySetKeywords"
        ];
      };
    }
  ];
}
