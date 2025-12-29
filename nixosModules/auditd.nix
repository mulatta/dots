{
  security.audit = {
    enable = true;
    rules = [
      "-w /var/log/wtmp -p wa -k session"
      "-w /var/log/btmp -p wa -k session"
      "-w /var/run/utmp -p wa -k session"
      "-w /etc/ssh/sshd_config -p wa -k sshd_config"
    ];
  };

  security.auditd.enable = true;
}
