_final: prev: {
  # The auth-source CLI accepts an OIDC secret only as an argument value, so
  # every reconciliation would publish it in the process listing. Give the
  # existing flag an environment source until the auth-source CLI supports
  # runtime secret files. go-gitea/gitea#36996 is related admin-password work,
  # not an implementation of OIDC secret-file support.
  gitea = prev.gitea.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ./oidc-secret-env.patch
    ];
  });
}
