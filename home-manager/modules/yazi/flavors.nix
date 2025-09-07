{ pkgs, ... }:
{
  flexoki-dark = pkgs.fetchFromGitHub {
    owner = "gosxrgxx";
    repo = "flexoki-dark.yazi";
    rev = "65ba7448bbdeb227d580be50c69b5a6df3d7bb48";
    hash = "sha256-VQJIqUNklPDiXBSYGWUp099LXytlETUwGj03o/9HP5I=";
  };
  flexoki-light = pkgs.fetchFromGitHub {
    owner = "gosxrgxx";
    repo = "flexoki-light.yazi";
    rev = "04860ce0c54f747e8a356c1a4a5175dc57e3e43a";
    hash = "sha256-wv6lSh2IlgCMC6gW7HUsTWJtqOQi6emLZ00QmZM8Qyw=";
  };
}
