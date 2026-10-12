_final: prev: {
  # go-mockery 3.8.0 vendors golang.org/x/tools v0.49, which cannot read Go
  # 1.27.2 export data, so its checks (and sesh, built with Go 1.27) fail.
  # Drop once nixpkgs carries 3.8.1 (vektra/mockery#1188, NixOS/nixpkgs#572848).
  go-mockery = prev.go-mockery.overrideAttrs (
    finalAttrs: _old: {
      version = "3.8.1";
      src = prev.fetchFromGitHub {
        owner = "vektra";
        repo = "mockery";
        tag = "v${finalAttrs.version}";
        hash = "sha256-HCbnifYWE/3CG85dt0FPWT9hLSQbgOXuOKTBJHO0S2U=";
      };
      vendorHash = "sha256-ksfAHdPdOd8ELS0CSBg+E7KPd5xX/uGeLPn9HiItjdI=";
    }
  );
}
