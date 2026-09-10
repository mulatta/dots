_final: prev: {
  # The auth-source CLI accepts an OIDC secret only as an argument value, so
  # every reconciliation would publish it in the process listing. Give the
  # existing flag an environment source until go-gitea/gitea#36996 lands a
  # file-based option upstream.
  gitea = prev.gitea.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ./oidc-secret-env.patch
    ];
  });
}
