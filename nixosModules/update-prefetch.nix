{
  config,
  pkgs,
  ...
}:
let
  outputs = "https://nixbot.mulatta.io/nix-outputs/github/mulatta/dots/main/checks.${pkgs.stdenv.hostPlatform.system}";
  home = config.users.users.seungwon.home;
in
{
  systemd.timers.update-prefetch.timerConfig.Persistent = true;
  systemd.services.update-prefetch = {
    startAt = "hourly";
    path = [
      config.nix.package
      pkgs.curl
      pkgs.gitMinimal
      pkgs.openssh
      pkgs.util-linux
    ];
    script = ''
      set -eux -o pipefail
      store_path="$(curl -fL ${outputs}.nixos-${config.networking.hostName})"
      nix-store --add-root /run/next-system -r "$store_path"

      if [[ -f ${home}/dots/flake.nix ]]; then
        profile=$(runuser -u seungwon -- nix run "${home}/dots#hm" -- profile)
        store_path="$(curl -fL ${outputs}.home-manager-$profile)"
        nix-store --add-root /run/next-home -r "$store_path"
      fi
    '';
    serviceConfig = {
      Type = "oneshot";
      CPUSchedulingPolicy = "idle";
      IOSchedulingClass = "idle";
    };
  };
}
