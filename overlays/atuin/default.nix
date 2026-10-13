_final: prev: {
  atuin = prev.atuin.overrideAttrs (old: {
    # Host Bash startup files can overwrite the isolated PTY test PATH.
    # Keep capture and shell integration tests enabled by isolating startup.
    # https://github.com/NixOS/nixpkgs/issues/573527
    # nixos-unstable now isolates Bash through env.ATUIN_E2E_BASH; the pinned
    # fork does not. Drop this patch once that packaging fix reaches the input.
    patches = (old.patches or [ ]) ++ [ ./isolate-bash-startup.patch ];

    checkFlags =
      (old.checkFlags or [ ])
      ++ prev.lib.optionals prev.stdenv.hostPlatform.isDarwin [
        # Parallel PTY forks can retain listener FDs after the parent's drop,
        # racing the test's immediate stale-socket assertion on Darwin.
        "--skip=a_stale_socket_file_is_not_a_live_proxy"
      ];
  });
}
