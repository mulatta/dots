{
  security.audit = {
    enable = true;
    rules = [
      # systemd sandboxing emits high-volume BPF records we do not act on.
      "-a always,exclude -F msgtype=BPF"

      # Session tracking (wtmp=login history, btmp=failed logins)
      "-w /var/log/wtmp -p wa -k session"
      "-w /var/log/btmp -p wa -k session"

      # SSH config tampering
      "-w /etc/ssh/sshd_config -p wa -k sshd_config"

      # Account/identity file changes
      "-w /etc/passwd -p wa -k identity"
      "-w /etc/shadow -p wa -k identity"
      "-w /etc/group -p wa -k identity"
      "-w /etc/sudoers -p wa -k privilege"
      "-w /etc/sudoers.d -p wa -k privilege"

      # Kernel module load/unload (rootkit detection)
      "-a always,exit -F arch=b64 -S init_module,finit_module,delete_module -k kernel_module"
    ];
  };

  security.auditd.enable = true;

  # Bound audit.log growth to roughly 250 MiB.
  security.auditd.settings = {
    max_log_file = 50; # MiB per file
    num_logs = 5;
    max_log_file_action = "ROTATE";
  };
}
