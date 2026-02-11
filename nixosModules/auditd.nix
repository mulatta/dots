{
  security.audit = {
    enable = true;
    rules = [
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
}
