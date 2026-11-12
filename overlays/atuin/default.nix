_final: prev: {
  atuin = prev.atuin.overrideAttrs (old: {
    checkFlags =
      (old.checkFlags or [ ])
      ++ prev.lib.optionals prev.stdenv.hostPlatform.isDarwin [
        # Parallel PTY forks can retain listener FDs after the parent's drop,
        # racing the test's immediate stale-socket assertion on Darwin.
        "--skip=a_stale_socket_file_is_not_a_live_proxy"
        # The build is not sandboxed on Darwin: a pi running on the host
        # makes the Pi cases see their test session as live.
        "--skip=a_diverged_copy_resumes_only_as_chosen::agent_6_Agent__Pi"
        "--skip=a_session_gone_on_with_elsewhere_catches_up_where_it_came_from::agent_5_Agent__Pi"
        # Redacting the 4.5 MiB message overruns its time budget on a loaded machine.
        "--skip=a_huge_message_reads_back"
      ];
  });
}
