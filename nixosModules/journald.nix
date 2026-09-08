{
  services.journald.settings.Journal = {
    Storage = "persistent";
    Compress = "yes";
    SystemMaxUse = "100M";
    MaxRetentionSec = "1week";
    MaxFileSec = "1month";
    RateLimitIntervalSec = "30s";
    RateLimitBurst = 10000;
    ForwardToSyslog = "no";
  };
}
