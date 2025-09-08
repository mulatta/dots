{
  wayland.windowManager.hyprland = {
    enable = true;

    systemd.enable = true;
    systemd.enableXdgAutostart = true;
    xwayland.enable = true;

    settings = {
      "$mod" = "SUPER";
      monitor = "eDP-1,3456x2234@120,0x0,2";
    };
  };
}
