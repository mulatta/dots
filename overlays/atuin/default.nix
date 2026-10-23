_final: prev: {
  atuin = prev.atuin.overrideAttrs (old: {
    checkFlags =
      (old.checkFlags or [ ])
      ++ prev.lib.optionals prev.stdenv.hostPlatform.isDarwin [
        # Parallel PTY forks can retain listener FDs after the parent's drop,
        # racing the test's immediate stale-socket assertion on Darwin.
        "--skip=a_stale_socket_file_is_not_a_live_proxy"
      ];
  });
}
