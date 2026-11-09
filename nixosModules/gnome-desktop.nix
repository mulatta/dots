{
  config,
  self,
  lib,
  pkgs,
  ...
}:
let
  rhesus = self.darwinConfigurations.rhesus.config;
  sources = {
    wireguard = map (address: lib.head (lib.splitString "/" address)) (
      lib.filter (lib.hasInfix ":") rhesus.networking.wg-quick.interfaces.wireguard.address
    );
    "tinc.naru" = [
      rhesus.networking.naru.ipv4
      rhesus.networking.naru.ipv6
    ];
  };
  grd = pkgs.gnome-remote-desktop;
  gen = config.clan.core.vars.generators.gnome-remote-desktop;
in
{
  imports = [ ./kwallet-tpm ];

  services.displayManager.gdm = {
    enable = true;
    # Never suspend a build host from the login screen.
    autoSuspend = false;
  };
  services.desktopManager.gnome.enable = true;

  # KWallet, unlocked from the TPM, is the secret service even without a session.
  services.gnome.gnome-keyring.enable = false;

  # srvos.server turns these off.
  fonts.fontconfig.enable = true;
  xdg = {
    autostart.enable = true;
    icons.enable = true;
    menus.enable = true;
    mime.enable = true;
    sounds.enable = true;
  };

  # Remote login: an RDP client reaches the GDM login screen, which starts a headless session.
  clan.core.vars.generators.gnome-remote-desktop = {
    files."tls.crt".secret = false;
    files."tls.key".owner = "gnome-remote-desktop";
    files.rdp-password.owner = "gnome-remote-desktop";
    runtimeInputs = [
      pkgs.openssl
      pkgs.xkcdpass
    ];
    script = ''
      openssl req -x509 -newkey rsa:3072 -sha256 -days 3650 -nodes \
        -subj "/CN=${config.networking.hostName}.n" \
        -keyout "$out/tls.key" -out "$out/tls.crt"
      xkcdpass --numwords 6 --delimiter - | tr -d '\n' > "$out/rdp-password"
    '';
  };

  environment.etc."gnome-remote-desktop/grd.conf".text = ''
    [RDP]
    enabled=true
    port=3389
    tls-cert=${gen.files."tls.crt".path}
    tls-key=${gen.files."tls.key".path}
  '';

  systemd.services.gnome-remote-desktop = {
    wantedBy = [ "graphical.target" ];
    restartTriggers = [ config.environment.etc."gnome-remote-desktop/grd.conf".source ];
  };

  systemd.user.services.obex.enable = false;

  # Only gnome-remote-desktop may configure the system daemon (its polkit rule).
  systemd.services.gnome-remote-desktop-credentials = {
    description = "Load the RDP credentials into gnome-remote-desktop";
    wantedBy = [ "gnome-remote-desktop.service" ];
    before = [ "gnome-remote-desktop.service" ];
    # grdctl starts the configuration daemon through pkexec.
    path = [ "/run/wrappers" ];
    serviceConfig = {
      Type = "oneshot";
      User = "gnome-remote-desktop";
      # grdctl reads the password from stdin when it is not an argument.
      StandardInput = "file:${gen.files.rdp-password.path}";
      ExecStart = "${grd}/bin/grdctl --system rdp set-credentials seungwon";
    };
  };

  # Naru is direct on the LAN; WireGuard is steadier from outside.
  networking.firewall.extraInputRules = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      interface: addresses:
      lib.concatMapStringsSep "\n" (
        address:
        let
          family = if lib.hasInfix ":" address then "ip6" else "ip";
        in
        lib.concatMapStringsSep "\n"
          (protocol: ''
            iifname "${interface}" ${family} saddr ${address} ${protocol} dport 3389 accept
          '')
          [
            "tcp"
            "udp"
          ]
      ) addresses
    ) sources
  );
}
