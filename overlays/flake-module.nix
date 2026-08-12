{
  inputs,
  ...
}:
{
  flake.overlays = {
    dots = _final: prev: {
      miniflux = prev.miniflux.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          ../packages/miniflux/allow-highlight-trusted-type.patch
          ../packages/miniflux/send-webhook-on-star.patch
        ];
      });

      # rust-s3 0.35 signs empty body headers on ranged GET and DELETE.
      # Cloudflare R2 rejects those signatures, breaking JMAP attachment
      # downloads and blob garbage collection. Keep this until rust-s3 merges
      # PRs #459/#465 and Stalwart bumps the crate.
      stalwart = prev.stalwart_0_15.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [
          ../packages/stalwart/return-empty-s3-blob-for-empty-range.patch
        ];

        cargoDeps =
          let
            rust-s3-r2-range-get-signing-fix = prev.fetchpatch {
              url = "https://github.com/durch/rust-s3/commit/4c7ed2b44d6fbf1ebdd401dd3a81c14d288cffb2.patch";
              relative = "s3";
              hash = "sha256-f4OBtd/XcERHSckluRh2ESTumygIMnEv7GMqPXT18QQ=";
            };
          in
          prev.runCommand "${old.pname}-${old.version}-vendor-rust-s3-r2-signing-fixes" { } ''
            cp -R ${old.cargoDeps} "$out"
            chmod -R u+w "$out/source-registry-0/rust-s3-0.35.1"
            cd "$out/source-registry-0/rust-s3-0.35.1"
            patch -p1 < ${rust-s3-r2-range-get-signing-fix}
            patch -p1 < ${../packages/stalwart/rust-s3-skip-delete-object-body-headers.patch}
            grep -F 'Command::GetObjectRange { .. } => {}' src/request/request_trait.rs
            grep -F 'Command::DeleteObject => {}' src/request/request_trait.rs
          '';
      });

    };
  };

  perSystem =
    { system, ... }:
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        overlays = [
          inputs.self.overlays.dots
        ];
      };
    };
}
