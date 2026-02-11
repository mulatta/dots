{
  inputs,
  pkgs,
  lib,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;

  # macOS: the upstream wrapper uses `open -na` which (1) doesn't pass
  # MOZ_LEGACY_PROFILES to the app and (2) forces a new instance with -n.
  # Shadow the CLI commands with hiPrio wrappers using `launchctl setenv` + `open -a`.
  original = inputs.zen-browser.packages.${system}.twilight;

  zenCli = pkgs.writeShellApplication {
    name = "zen";
    text = ''
      /bin/launchctl setenv MOZ_LEGACY_PROFILES 1 2>/dev/null
      STABLE_PATH="$HOME/Applications/Home Manager Apps/Zen Browser (Twilight).app"
      if [[ -e "$STABLE_PATH" ]]; then
        exec /usr/bin/open -a "$STABLE_PATH" --args "$@"
      else
        exec /usr/bin/open -a "${original}/Applications/Zen Browser (Twilight).app" --args "$@"
      fi
    '';
  };
in
{
  imports = [
    inputs.zen-browser.homeModules.twilight
  ];

  programs.zen-browser = {
    enable = true;
    policies = {
      LegacyProfiles = true;
      DisableAppUpdate = true;
      DisableTelemetry = true;
      DisableFirefoxStudies = true;
      DisablePocket = true;
      PasswordManagerEnabled = false;
      OfferToSaveLogins = false;

      ExtensionSettings = {
        # uBlock Origin
        "uBlock0@raymondhill.net" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
          installation_mode = "normal_installed";
        };
        # Bitwarden
        "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi";
          installation_mode = "normal_installed";
        };
        # Obsidian Web Clipper
        "clipper@obsidian.md" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/web-clipper-obsidian/latest.xpi";
          installation_mode = "normal_installed";
        };
        # Zotero Connector
        "zotero@chnm.gmu.edu" = {
          install_url = "https://www.zotero.org/download/connector/dl?browser=firefox";
          installation_mode = "normal_installed";
        };
        # Media Harvest
        "mediaharvest@mediaharvest.app" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/media-harvest/latest.xpi";
          installation_mode = "normal_installed";
        };
        # Linkwarden
        "jordanlinkwarden@gmail.com" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/linkwarden/latest.xpi";
          installation_mode = "normal_installed";
        };
        # ff2mpv - open videos in mpv
        "ff2mpv@yossarian.net" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/ff2mpv/latest.xpi";
          installation_mode = "normal_installed";
        };
      };
    };

    nativeMessagingHosts = [
      pkgs.ff2mpv-rust # open videos in mpv from browser
    ];

    profiles.default = {
      isDefault = true;
      settings = {
        # --- Startup ---
        "browser.startup.homepage" = "about:blank";
        "browser.newtabpage.enabled" = false;
        "browser.shell.checkDefaultBrowser" = false;
        "browser.warnOnQuitShortcut" = false;
        "browser.tabs.loadBookmarksInTabs" = true;

        # --- URL bar: autocomplete enabled, hide search engine suggestions ---
        "browser.urlbar.suggest.engines" = false;

        # --- HTTPS-Only Mode ---
        "dom.security.https_only_mode" = true;

        # --- Privacy & network ---
        "browser.contentblocking.category" = "custom";
        "network.cookie.cookieBehavior" = 4;
        "network.dns.disablePrefetch" = true;
        "network.http.speculative-parallel-limit" = 0;
        "network.prefetch-next" = false;
        "privacy.clearOnShutdown_v2.browsingHistoryAndDownloads" = false;
        "privacy.clearOnShutdown_v2.cache" = false;
        "privacy.clearOnShutdown_v2.cookiesAndStorage" = false;
        "privacy.clearOnShutdown_v2.formdata" = true;
        "privacy.history.custom" = true;

        # --- Password manager (use Bitwarden instead) ---
        "signon.autofillForms" = false;
        "signon.generation.enabled" = false;
        "signon.management.page.breach-alerts.enabled" = false;
        "signon.rememberSignons" = false;

        # --- Extensions ---
        "extensions.update.enabled" = false;
        "xpinstall.signatures.required" = false;

        # --- Translation ---
        "browser.translations.automaticallyPopup" = false;
        "browser.translations.mostRecentTargetLanguages" = "ko";

        # --- Zen: compact mode ---
        "zen.view.compact.enable-at-startup" = true;
        "zen.view.compact.hide-toolbar" = true;
        "zen.view.compact.should-enable-at-startup" = true;
        "zen.view.compact.toolbar-flash-popup" = true;
        "zen.view.use-single-toolbar" = false;

        # --- Zen: workspaces ---
        "zen.workspaces.separate-essentials" = false;
        "zen.workspaces.show-workspace-indicator" = true;

        # --- Zen: bookmarks bar (SuperPins mod) ---
        "uc.bookmarks.center-toolbar" = true;
        "uc.bookmarks.expand-on-hover" = true;
        "uc.bookmarks.expand-on-search" = true;
        "uc.bookmarks.hide-favicons" = true;
        "uc.bookmarks.hide-folder-icons" = true;
        "uc.bookmarks.hide-name" = true;
        "uc.bookmarks.position-toolbar" = "right";
        "uc.bookmarks.transparent" = true;
      };

      search = {
        force = true;
        default = "google";
        engines = {
          "NixOS Options" = {
            urls = [ { template = "https://search.nixos.org/options?channel=unstable&query={searchTerms}"; } ];
            definedAliases = [ "@no" ];
          };
          "Home-manager Options" = {
            urls = [ { template = "https://home-manager-options.extranix.com/?query={searchTerms}"; } ];
            definedAliases = [ "@hm" ];
          };
          "Nix Packages" = {
            urls = [ { template = "https://search.nixos.org/packages?type=packages&query={searchTerms}"; } ];
            definedAliases = [ "@np" ];
          };
          "GitHub Search" = {
            urls = [ { template = "https://github.com/search?q={searchTerms}&type=code"; } ];
            definedAliases = [ "@gs" ];
          };
          "Danawa" = {
            urls = [ { template = "https://search.danawa.com/dsearch.php?query={searchTerms}"; } ];
            definedAliases = [ "@da" ];
          };
        };
      };
    };
  };

  # macOS: shadow upstream CLI wrappers that use broken `open -na`
  home.packages = lib.mkIf pkgs.stdenv.isDarwin [
    (lib.hiPrio zenCli)
  ];

  # macOS: zen-browser wrapper doesn't set up native messaging hosts,
  # so register the manifest manually where Firefox-based browsers look for it
  home.file."Library/Application Support/Mozilla/NativeMessagingHosts/ff2mpv.json" =
    pkgs.lib.mkIf pkgs.stdenv.isDarwin
      {
        source = "${pkgs.ff2mpv-rust}/lib/mozilla/native-messaging-hosts/ff2mpv.json";
      };

  # macOS GUI apps don't inherit shell PATH; point ff2mpv-rust to mpv via config
  xdg.configFile."ff2mpv-rust.json" = pkgs.lib.mkIf pkgs.stdenv.isDarwin {
    text = builtins.toJSON {
      player_command = "${pkgs.mpv}/bin/mpv";
      player_args = [
        "--no-terminal"
        "--script-opts=ytdl_hook-ytdl_path=${pkgs.yt-dlp}/bin/yt-dlp"
        "--"
      ];
    };
  };
}
