_final: prev: {
  afew = prev.afew.overrideAttrs (_old: {
    # Structured Python attrs no longer split packed wrapper arguments.
    # Upstream fix is pending; remove once the input includes it.
    # https://github.com/NixOS/nixpkgs/pull/575801
    makeWrapperArgs = [
      "--prefix"
      "PATH"
      ":"
      "${prev.notmuch}/bin"
    ];
  });
}
