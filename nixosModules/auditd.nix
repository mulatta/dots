{
  security.audit = {
    enable = true;
    rules = [
      # Drop BPF syscall records: systemd's per-service cgroup firewalls and
      # sandboxing (IPAddress*, DeviceAllow, etc.) emit a type=BPF event on
      # every bpf() call, a large share of the log volume that carries no
      # security signal we act on.
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

  # Bound disk use: without these auditd writes a single unbounded audit.log.
  # Rotate at 50 MiB and keep 5 files -> ~250 MiB cap.
  security.auditd.settings = {
    max_log_file = 50; # MiB per file
    num_logs = 5;
    max_log_file_action = "ROTATE";
  };
}
