{
  principals = [
    {
      type = "oauthClient";
      name = "pim-mcp";
      description = "Personal information management MCP";
    }
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
}
