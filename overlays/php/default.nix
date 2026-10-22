# PHP 8.4.27 fixes CVE-2026-109618 and CVE-2026-109619 (RCE); NixOS/nixpkgs#576853
# is on master but not yet in nixos-unstable. Drop once the fork carries 8.4.27.
final: prev: {
  php84 =
    (prev.php84.override {
      packageOverrides = _phpFinal: phpPrev: {
        extensions = phpPrev.extensions // {
          # The new OOM tests spawn php with -n and need filter loaded explicitly.
          filter = phpPrev.extensions.filter.overrideAttrs (old: {
            postConfigure = (old.postConfigure or "") + ''
              substituteInPlace \
                tests/oom_filter_input.phpt \
                tests/oom_filter_input_array.phpt \
                tests/oom_filter_default_encoded.phpt \
                --replace-fail "'-n'," "'-n', '-d', 'extension=$PWD/modules/filter.so',"
            '';
          });
        };
      };
    }).overrideAttrs
      (
        finalAttrs: _prevAttrs: {
          version = "8.4.27";
          src = final.fetchurl {
            url = "https://www.php.net/distributions/php-${finalAttrs.version}.tar.bz2";
            hash = "sha256-slMKh3xyL0sIyeF0owywi6wrfhkD7m6eMV8KqfX4LCQ=";
          };
        }
      );
}
