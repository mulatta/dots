{ inputs, ... }:
_args:
let
  pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
  nixbotEffects = inputs.nixbot.lib.effects { inherit pkgs; };

  mkRepoEffect =
    name:
    {
      extraInputs ? [ ],
      extraSecrets ? { },
      checkout ? false,
    }:
    script:
    nixbotEffects.mkEffect {
      name = "effect-${name}";
      inherit checkout;
      inputs = [
        pkgs.gh
        pkgs.git
        pkgs.jq
        pkgs.nix
        pkgs.openssh
      ]
      ++ extraInputs;
      secretsMap = {
        git.type = "GitToken";
      }
      // extraSecrets;
      effectScript = ''
        set -euo pipefail
        export NIX_CONFIG="experimental-features = nix-command flakes"
        token=$(jq -r '.git.data.token' "$HERCULES_CI_SECRETS_JSON")
        export GH_TOKEN="$token"
        git config --global user.name "dots-bot"
        git config --global user.email "dots-bot@users.noreply.github.com"
        git config --global safe.directory '*'
        ${if checkout then ''cd "$NIXBOT_EFFECT_CHECKOUT"'' else "exit 1"}
        ${script}
      '';
    };
in
{
  onSchedule.update-submodules = {
    when = {
      hour = 2;
      minute = 51;
    };
    outputs.effects.update-submodules = mkRepoEffect "update-submodules" { checkout = true; } ''
      git submodule update --init --recursive
      git submodule update --recursive --remote
      if git diff --quiet; then
        echo "no submodule changes"
        exit 0
      fi

      branch=update-submodules
      git checkout -b "$branch"
      git commit -am "Update submodules"
      git push -f origin "$branch"
      if ! gh pr view "$branch" >/dev/null 2>&1; then
        gh pr create --head "$branch" \
          --title "Update submodules" \
          --body "Update pinned upstream submodules." \
          --label auto-merge
      fi
    '';
  };

  onSchedule.renew-step-intermediate = {
    when = {
      dayOfMonth = [ 1 ];
      hour = 4;
      minute = 30;
    };
    outputs.effects.renew-step-intermediate =
      mkRepoEffect "renew-step-intermediate"
        {
          checkout = true;
          extraInputs = [
            pkgs.openssl
            pkgs.step-cli
          ];
          extraSecrets.dure-ca = "dure-ca";
        }
        ''
          cert=vars/per-machine/taps/step-intermediate-cert/intermediate.crt/value
          if openssl x509 -checkend $((90 * 24 * 3600)) -noout -in "$cert"; then
            echo "intermediate certificate valid for more than 90 days"
            exit 0
          fi

          ca=$(mktemp -d)
          trap 'rm -rf "$ca"' EXIT
          jq -r '.["dure-ca"].data["ca.crt"]' "$HERCULES_CI_SECRETS_JSON" > "$ca/ca.crt"
          jq -r '.["dure-ca"].data["ca.key"]' "$HERCULES_CI_SECRETS_JSON" > "$ca/ca.key"
          jq -r '.["dure-ca"].data["intermediate.key"]' "$HERCULES_CI_SECRETS_JSON" > "$ca/intermediate.key"

          step certificate create \
            --ca "$ca/ca.crt" \
            --ca-key "$ca/ca.key" \
            --ca-password-file /dev/null \
            --key "$ca/intermediate.key" \
            --template machines/cask/modules/intermediate.tmpl \
            --not-after 8760h \
            --no-password --insecure --force \
            "dure intermediate ca" \
            "$cert"

          branch=renew-step-intermediate
          git checkout -b "$branch"
          git commit -am "step-ca: renew intermediate certificate"
          git push -f origin "$branch"
          if ! gh pr view "$branch" >/dev/null 2>&1; then
            gh pr create --head "$branch" \
              --title "step-ca: renew intermediate certificate" \
              --body "renew the dure intermediate certificate before its expiry window." \
              --label auto-merge
          fi
        '';
  };
}
