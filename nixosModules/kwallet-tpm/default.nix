# Unlocks KWallet from a TPM-sealed password, without a login.
# Setup: echo -n '<pw>' | systemd-creds encrypt --user - ~/.config/kwallet-tpm/password.cred
{ pkgs, ... }:
let
  ksecretd = "${pkgs.kdePackages.kwallet}/bin/ksecretd";

  kwallet-tpm-unlock = pkgs.python3.pkgs.buildPythonApplication {
    pname = "kwallet-tpm-unlock";
    version = "0.2.0";
    pyproject = false;

    nativeBuildInputs = [ pkgs.makeWrapper ];

    dontUnpack = true;

    installPhase = ''
      install -Dm755 ${./kwallet-tpm-unlock.py} $out/bin/kwallet-tpm-unlock
      wrapProgram $out/bin/kwallet-tpm-unlock \
        --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.systemd ]}
    '';
  };
in
{
  # Starts the user manager, and with it the wallet, at boot without a login.
  users.users.seungwon.linger = true;

  environment.systemPackages = [ kwallet-tpm-unlock ];

  systemd.user.services.kwallet-tpm-unlock = {
    description = "KWallet secret service (ksecretd) unlocked via TPM-sealed credentials";
    # Not tied to the desktop: headless rbw and mail sync need the wallet too.
    # ksecretd then has no display for dialogs; TPM unlock needs none.
    wantedBy = [ "default.target" ];
    # Early secret-service clients must not D-Bus-activate a locked ksecretd.
    aliases = [
      "dbus-org.kde.secretservicecompat.service"
      "dbus-org.freedesktop.secrets.service"
    ];
    unitConfig = {
      # User units apply to every user, including GDM's greeters.
      ConditionUser = "seungwon";
      # A decrypt restart loop exhausts TPM session slots for every user.
      StartLimitIntervalSec = 120;
      StartLimitBurst = 3;
    };
    # Starts before any display exists; ksecretd is a Qt app and aborts without a platform.
    environment.QT_QPA_PLATFORM = "offscreen";
    serviceConfig = {
      Type = "dbus";
      BusName = "org.kde.secretservicecompat";
      ExecStart = "${kwallet-tpm-unlock}/bin/kwallet-tpm-unlock ${ksecretd} %h/.config/kwallet-tpm/password.cred";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  # Route D-Bus activation through the unit above.
  services.dbus.packages = [
    (pkgs.runCommand "ksecretd-dbus-activation" { } ''
      dir=$out/share/dbus-1/services
      mkdir -p $dir
      for name in org.kde.secretservicecompat org.freedesktop.secrets; do
        cat > $dir/$name.service <<EOF
      [D-BUS Service]
      Name=$name
      Exec=${pkgs.coreutils}/bin/false
      SystemdService=kwallet-tpm-unlock.service
      EOF
      done
    '')
  ];
}
