{
  services.journald.extraConfig = ''
    # Persistent storage (systemd default, declared explicitly)
    Storage=persistent
    Compress=yes

    # Disk usage limits
    SystemMaxUse=100M
    MaxRetentionSec=1week

    # Rotation per file (systemd default)
    MaxFileSec=1month

    # Rate limiting per service (systemd default)
    RateLimitIntervalSec=30s
    RateLimitBurst=10000

    # Do not duplicate to syslog
    ForwardToSyslog=no
  '';
}
