{
  ...
}:
{
  programs.thunderbird = {
    enable = true;
    profiles.default = {
      isDefault = true;
      withExternalGnupg = true;
    };
  };

  # Enable Thunderbird for email account
  accounts.email.accounts.mulatta.thunderbird = {
    enable = true;
    profiles = [ "default" ];
  };

  # Enable Thunderbird for calendar account
  accounts.calendar.accounts.stalwart.thunderbird = {
    enable = true;
    profiles = [ "default" ];
  };

  # Enable Thunderbird for contact account
  accounts.contact.accounts.stalwart.thunderbird = {
    enable = true;
    profiles = [ "default" ];
  };
}
