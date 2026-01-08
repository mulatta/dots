{ pkgs, ... }:
{
  # dock
  system.defaults.dock = {
    autohide = true;
    autohide-delay = 0.1;
    autohide-time-modifier = 0.6;
    show-recents = false;
    wvous-br-corner = 14;
    wvous-tr-corner = 12;
    wvous-tl-corner = 11;

    persistent-apps = [
      "/System/Applications/Calendar.app"
      "/System/Applications/Reminders.app"
      "/System/Applications/Messages.app"
      "/System/Applications/Mail.app"
      "/System/Applications/System Settings.app"
      "/Applications/Claude.app"
      "/Applications/Slack.app"
      "/Applications/Zen.app"
      "${pkgs.firefox-bin}/Applications/Firefox.app"
      "${pkgs.obsidian}/Applications/Obsidian.app"
      "${pkgs.ghostty-bin}/Applications/Ghostty.app"
      "/Applications/KakaoTalk.app"
    ];
  };

  # control center
  system.defaults.controlcenter = {
    BatteryShowPercentage = true;
    Bluetooth = true;
  };

  system.defaults.loginwindow.GuestEnabled = false;

  # finder
  system.defaults.finder = {
    FXPreferredViewStyle = "clmv";
    ShowPathbar = true;
    ShowStatusBar = true;
    _FXSortFoldersFirst = true;
    _FXSortFoldersFirstOnDesktop = true;
    NewWindowTarget = "Home";
  };
  system.defaults.CustomUserPreferences."com.apple.finder" = {
    ShowExternalHardDrivesOnDesktop = false;
    ShowRemovableMediaOnDesktop = false;
    WarnOnEmptyTrash = false;
  };
}
