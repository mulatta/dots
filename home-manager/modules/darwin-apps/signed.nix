{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.targets.darwin;
  apps = cfg.signedApps;
  # One line per app, so a later activation can undo what this one set up.
  manifestFile = pkgs.writeText "signed-apps" (
    lib.concatStrings (
      lib.mapAttrsToList (
        name: app:
        lib.concatStringsSep "\t" [
          name
          app.identifier
          (if app.launchAgent == null then "-" else app.launchAgent.label)
          (if app.tccServices == [ ] then "-" else lib.concatStringsSep " " app.tccServices)
        ]
        + "\n"
      ) apps
    )
  );
  sha1 = lib.mapNullable lib.toLower cfg.codeSigning.certificateSha1;
  appsDir = "${config.home.homeDirectory}/Applications";
  stateDir = "${config.xdg.stateHome}/home-manager/signed-apps";

  # TCC keys grants on the designated requirement. Pinning it to the certificate
  # instead of the cdhash keeps Accessibility grants across rebuilds.
  requirement = identifier: ''identifier "${identifier}" and certificate leaf = H"${sha1}"'';

  appModule =
    { name, config, ... }:
    {
      options = {
        package = mkOption {
          type = types.package;
          default = mkBundle config;
          defaultText = lib.literalMD "a bundle built from `program` and `infoPlist`";
          description = "Package providing the bundle under `Applications/`.";
        };
        bundle = mkOption {
          type = types.str;
          example = "gksdud.app";
        };
        program = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Bare executable to wrap in a bundle when the package ships none.";
        };
        infoPlist = mkOption {
          type = types.attrsOf types.anything;
          default = { };
          description = "Info.plist keys for a bundle built from `program`.";
        };
        identifier = mkOption {
          type = types.str;
          description = "Code signing identifier of the bundle, usually its CFBundleIdentifier.";
        };
        executable = mkOption {
          type = types.str;
          default = "Contents/MacOS/${baseNameOf config.program}";
          defaultText = lib.literalExpression ''"Contents/MacOS/''${baseNameOf program}"'';
          example = "Contents/MacOS/gksdud";
          description = "Main executable, relative to the bundle.";
        };
        nested = mkOption {
          type = types.attrsOf types.str;
          default = { };
          example = {
            "Contents/Helpers/gksdud" = "io.gksdud.inputswitch.cli";
          };
          description = "Nested Mach-O files, relative to the bundle, mapped to their own identifiers.";
        };
        entitlements = mkOption {
          type = types.attrsOf types.anything;
          default = { };
          example = {
            "com.apple.security.cs.disable-library-validation" = true;
          };
          description = ''
            Entitlements for the main executable. The hardened runtime is always
            on, since without it DYLD_INSERT_LIBRARIES could borrow the app's TCC
            grants; apps linking Nix store dylibs need library validation off.
          '';
        };
        tccServices = mkOption {
          type = types.listOf types.str;
          default = [ ];
          example = [ "Accessibility" ];
          description = ''
            TCC services, as tccutil(1) names them, whose grants activation
            checks against the current signature. A grant recorded for another
            requirement is reset so the next prompt records the stable one.
          '';
        };
        binaries = mkOption {
          type = types.attrsOf types.str;
          default = { };
          description = "Commands put on PATH, mapped to files relative to the installed bundle.";
        };
        launchAgent = mkOption {
          type = types.nullOr (
            types.submodule {
              options = {
                label = mkOption { type = types.str; };
                config = mkOption {
                  type = types.attrsOf types.anything;
                  default = { };
                  description = "launchd.plist(5) keys; Label and Program are set from this app.";
                };
              };
            }
          );
          default = null;
        };
        path = mkOption {
          type = types.str;
          readOnly = true;
          default = "${appsDir}/${config.bundle}";
          defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/Applications/<bundle>"'';
        };
        installer = mkOption {
          type = types.package;
          readOnly = true;
          internal = true;
          default = mkInstaller name config;
        };
      };
    };

  # A copy, not a symlink, so the bundle can carry its own signature.
  mkBundle =
    app:
    if app.program == null then
      throw "targets.darwin.signedApps: ${app.bundle} needs either package or program"
    else
      let
        name = lib.removeSuffix ".app" app.bundle;
        executable = baseNameOf app.program;
        infoPlist = pkgs.writeText "Info.plist" (
          lib.generators.toPlist { escape = true; } (
            {
              CFBundleExecutable = executable;
              CFBundleIdentifier = app.identifier;
              CFBundleInfoDictionaryVersion = "6.0";
              CFBundleName = name;
              CFBundlePackageType = "APPL";
            }
            // app.infoPlist
          )
        );
      in
      pkgs.runCommand name { } ''
        contents="$out/Applications/"${lib.escapeShellArg app.bundle}/Contents
        install -Dm755 ${app.program} "$contents/MacOS/"${lib.escapeShellArg executable}
        install -Dm644 ${infoPlist} "$contents/Info.plist"
      '';

  agentPlist =
    app:
    pkgs.writeText "${app.launchAgent.label}.plist" (
      lib.generators.toPlist { escape = true; } (
        lib.filterAttrsRecursive (_: v: v != null) app.launchAgent.config
        // {
          Label = app.launchAgent.label;
          Program = "${app.path}/${app.executable}";
        }
      )
    );

  signCommand =
    flags: target: identifier:
    "/usr/bin/codesign --force --options runtime ${flags}--timestamp=none --identifier ${lib.escapeShellArg identifier} "
    + (
      if sha1 == null then
        "--sign -"
      else
        "--sign ${sha1} --requirements ${lib.escapeShellArg "=designated => ${requirement identifier}"}"
    )
    + " ${target}";

  mkInstaller =
    name: app:
    pkgs.writeShellApplication {
      name = "install-signed-app-${name}";
      text = ''
        src=${lib.escapeShellArg "${app.package}/Applications/${app.bundle}"}
        target=${lib.escapeShellArg app.path}
        marker=${lib.escapeShellArg "${stateDir}/${name}"}
        stamp=${
          lib.escapeShellArg (
            builtins.toJSON {
              inherit (app)
                package
                identifier
                nested
                entitlements
                ;
              certificate = sha1;
            }
          )
        }
        resigned=0

        # errexit is off inside conditions, so every step returns explicitly.
        sign_copy() {
          mkdir -p ${lib.escapeShellArg appsDir} || return 1
          stage=$(mktemp -d ${lib.escapeShellArg "${appsDir}/.signing-${name}.XXXXXX"}) || return 1
          trap 'rm -rf "$stage"' EXIT
          app="$stage/"${lib.escapeShellArg app.bundle}
          # Dereference so wrapper packages built with symlinkJoin yield real files.
          cp -RL "$src" "$stage/" || return 1
          chmod -R u+w "$stage" || return 1
          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (
              path: id: "${signCommand "" ''"$app"/${lib.escapeShellArg path}'' id} || return 1"
            ) app.nested
          )}
          ${
            signCommand (lib.optionalString (app.entitlements != { })
              "--entitlements ${
                pkgs.writeText "${name}.entitlements" (lib.generators.toPlist { escape = true; } app.entitlements)
              } "
            ) ''"$app"'' app.identifier
          } || return 1
          /usr/bin/codesign --verify --deep --strict "$app" || return 1
          ${lib.optionalString (sha1 != null) ''
            [[ "$(/usr/bin/codesign -d -r- "$app" 2>&1)" == *${lib.escapeShellArg "designated => ${requirement app.identifier}"}* ]] || return 1
          ''}
        }

        # A locked or missing keychain must not break activation; keep the last good copy.
        if [[ -d "$target" && -f "$marker" && "$(<"$marker")" == "$stamp" ]] \
          && /usr/bin/codesign --verify --strict "$target" 2>/dev/null; then
          :
        ${lib.optionalString (sha1 != null) ''
          elif [[ "$(/usr/bin/security find-identity -v -p codesigning)" != *${lib.toUpper sha1}* ]]; then
            echo "warning: code signing identity ${sha1} unavailable; keeping $target as is" >&2
        ''}
        elif ! sign_copy; then
          echo "warning: signing $target failed; keeping the installed copy" >&2
        else
          # Swap by rename so a failed signature never leaves the app missing.
          if [[ -e "$target" ]]; then
            mv "$target" "$stage/previous"
          fi
          mv "$app" "$target"
          /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$target"
          mkdir -p "$(dirname "$marker")"
          printf '%s' "$stamp" > "$marker"
          resigned=1
        fi

        ${lib.optionalString (sha1 != null && app.tccServices != [ ]) ''
          req=$(mktemp)
          /usr/bin/csreq -r=${lib.escapeShellArg (requirement app.identifier)} -b "$req"
          expected=$(od -An -tx1 -v "$req" | tr -d ' \n' | tr '[:lower:]' '[:upper:]')
          rm -f "$req"
          services=(${lib.escapeShellArgs app.tccServices})
          for service in "''${services[@]}"; do
            readable=0
            row=""
            for db in "/Library/Application Support/com.apple.TCC/TCC.db" "$HOME/Library/Application Support/com.apple.TCC/TCC.db"; do
              if out=$(/usr/bin/sqlite3 -readonly "$db" "select auth_value || '|' || hex(csreq) from access where service = 'kTCCService$service' and client = '${app.identifier}'" 2>/dev/null); then
                readable=1
                if [[ -n "$out" ]]; then
                  row=$out
                  break
                fi
              fi
            done
            # Reading TCC.db needs Full Disk Access, which only some terminals hold.
            if [[ $readable == 0 ]]; then
              echo "note: cannot read TCC.db; skipping the $service check for $target" >&2
            elif [[ -z "$row" ]]; then
              echo "warning: grant $service to $target in System Settings" >&2
            elif [[ "''${row#*|}" != "$expected" ]]; then
              /usr/bin/tccutil reset "$service" ${lib.escapeShellArg app.identifier} >/dev/null
              echo "warning: reset the stale $service grant of $target; grant it again" >&2
            elif [[ "''${row%%|*}" != 2 ]]; then
              echo "warning: $service is denied for $target" >&2
            fi
          done
        ''}
        ${lib.optionalString (app.launchAgent != null) ''
          label=${lib.escapeShellArg app.launchAgent.label}
          plist=${agentPlist app}
          domain="gui/$UID"
          destination="$HOME/Library/LaunchAgents/$label.plist"
          loaded() { /bin/launchctl print "$domain/$label" >/dev/null 2>&1; }

          if ! /usr/bin/cmp -s "$plist" "$destination"; then
            if loaded; then
              /bin/launchctl bootout "$domain/$label" || true
              for _ in $(seq 50); do loaded || break; sleep 0.1; done
            fi
            mkdir -p "$(dirname "$destination")"
            /usr/bin/install -m 444 "$plist" "$destination"
          elif [[ $resigned == 1 ]] && loaded; then
            /bin/launchctl kickstart -k "$domain/$label"
          fi

          if ! loaded; then
            /bin/launchctl bootstrap "$domain" "$destination"
          fi
        ''}
      '';
    };
in
{
  options.targets.darwin = {
    codeSigning.certificateSha1 = mkOption {
      type = types.nullOr (types.strMatching "[0-9A-Fa-f]{40}");
      default = null;
      description = ''
        SHA-1 of a code signing certificate whose private key is in the login
        keychain. When null, signed apps fall back to ad-hoc signatures, so
        TCC grants have to be renewed after every rebuild.
      '';
    };

    signedApps = mkOption {
      type = types.attrsOf (types.submodule appModule);
      default = { };
      description = ''
        Application bundles copied out of the store into ~/Applications and
        re-signed with the local identity, for apps whose TCC grants should
        survive package updates.
      '';
    };
  };

  config = lib.mkMerge [
    {
      # Stop agents and drop markers of apps no longer listed; the bundles
      # themselves go through managedApps.
      # Before managedApps deletes bundles: tccutil needs them registered to resolve identifiers.
      home.activation.removeSignedApps =
        lib.hm.dag.entryBetween [ "reconcileManagedDarwinApps" ] [ "writeBoundary" ]
          ''
            state=${lib.escapeShellArg stateDir}
            manifest="$state/installed"
            current=${lib.escapeShellArg (lib.concatStringsSep " " (lib.attrNames apps))}
            if [[ -f "$manifest" ]]; then
              while IFS=$'\t' read -r name identifier label services; do
                case " $current " in
                  *" $name "*) continue ;;
                esac
                if [[ "$label" != - ]]; then
                  run /bin/launchctl bootout "gui/$UID/$label" 2>/dev/null || true
                  run rm -f "$HOME/Library/LaunchAgents/$label.plist"
                fi
                for service in $services; do
                  [[ "$service" == - ]] && continue
                  run --quiet /usr/bin/tccutil reset "$service" "$identifier" \
                    || echo "warning: could not reset $service for $identifier" >&2
                done
              done < "$manifest"
            fi
            for marker in "$state"/*; do
              [[ -f "$marker" && "$marker" != "$manifest" ]] || continue
              case " $current " in
                *" $(basename "$marker") "*) ;;
                *) run rm -f "$marker" ;;
              esac
            done
            run mkdir -p "$state"
            run install -m 644 ${manifestFile} "$manifest"
          '';
    }

    (lib.mkIf (apps != { }) {
      targets.darwin.managedApps = lib.mapAttrsToList (_: app: app.path) apps;

      home.packages = [
        (pkgs.callPackage ./code-signing-identity.nix { })
      ]
      ++ lib.mapAttrsToList (
        name: app:
        pkgs.linkFarm "signed-app-${name}-bin" (
          lib.mapAttrs' (command: path: lib.nameValuePair "bin/${command}" "${app.path}/${path}") app.binaries
        )
      ) (lib.filterAttrs (_: app: app.binaries != { }) apps);

      home.activation.installSignedApps = lib.hm.dag.entryAfter [ "writeBoundary" "setupLaunchAgents" ] (
        lib.concatMapStringsSep "\n" (app: "run ${lib.getExe app.installer}") (lib.attrValues apps)
      );
    })
  ];
}
