# Register ~/bin/tmux-open-file as the system handler for text/source files,
# so clicking a file:// hyperlink in ghostty (or any terminal) opens helix
# in the active tmux pane instead of TextEdit/gedit/whatever.
#
# Why mime registration instead of wrapping ghostty:
#   - linux: ghostty calls `xdg-open file://...`; xdg-open resolves the file's
#     real mimetype and dispatches via mimeapps.list. There is no
#     x-scheme-handler/file. Shimming xdg-open works but breaks if ghostty
#     is launched from a .desktop file pointing at the unwrapped binary.
#   - macos: ghostty calls `open -t file://...`; `-t` goes straight to
#     LaunchServices' default text editor. PATH shims don't work because
#     GUI apps inherit launchd's PATH, not the shell's.
#
# Registering as the default handler covers both with one mechanism, and as
# a bonus also catches `xdg-open foo.py` from the shell, file manager
# double-clicks, etc.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # The script lives in ~/bin (stow-managed via dots/home/bin/), not the
  # nix store, so we can iterate on it without a home-manager switch. The
  # .desktop / .app entries are just trampolines pointing at it.
  opener = "${config.home.homeDirectory}/bin/tmux-open-file";

  # Mimetypes we actually care about when clicking hyperlinks emitted by
  # compilers, ripgrep, ls --hyperlink, etc. Intentionally not exhaustive:
  # we don't want to take over PDFs, images, or anything with a real GUI app.
  textMimes = [
    "text/plain"
    "text/markdown"
    "text/x-log"
    "text/x-patch"
    "text/x-diff"
    "text/x-python"
    "text/x-shellscript"
    "text/x-nix"
    "text/x-csrc"
    "text/x-chdr"
    "text/x-c++src"
    "text/x-c++hdr"
    "text/rust"
    "text/x-lua"
    "application/x-shellscript"
    "application/json"
    "application/x-yaml"
    "application/toml"
    # Unrecognised extensions land here; better us than the file manager.
    "application/octet-stream"
    "inode/x-empty"
  ];

  # macOS UTIs roughly mirroring the above. `open -t` only consults
  # public.plain-text, but we register the rest so Finder double-click
  # behaves consistently.
  utis = [
    "public.plain-text"
    "public.text"
    "public.source-code"
    "public.data"
    "public.shell-script"
    "public.python-script"
    "public.json"
    "net.daringfireball.markdown"
  ];
in
lib.mkMerge [
  (lib.mkIf pkgs.stdenv.isLinux {
    xdg.desktopEntries.tmux-hx = {
      name = "hx (in tmux)";
      # %u not %f: xdg-open passes the original file:// URI when the
      # .desktop advertises it can take URLs, which preserves :line:col
      # suffixes that path normalisation would strip.
      exec = "${opener} %u";
      terminal = false;
      mimeType = textMimes;
      noDisplay = true; # don't clutter the app launcher
    };

    xdg.mimeApps = {
      enable = true;
      defaultApplications = lib.genAttrs textMimes (_: "tmux-hx.desktop");
    };
  })

  (lib.mkIf pkgs.stdenv.isDarwin {
    # LaunchServices won't run a bare script; it needs a bundle. Minimal
    # AppleScript .app that forwards the dropped/opened file to our script.
    # Built lazily into ~/Applications because LS only indexes real paths,
    # not /nix/store.
    home.activation.tmuxHxApp = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      app="$HOME/Applications/tmux-hx.app"
      # Clean up the previous tmux-nvim.app if it still lingers — otherwise
      # LaunchServices may keep its stale UTI claims around. Idempotent.
      legacy="$HOME/Applications/tmux-nvim.app"
      if [ -d "$legacy" ]; then
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
          -u "$legacy" || true
        rm -rf "$legacy"
      fi
      # osacompile is idempotent enough; just overwrite.
      /usr/bin/osacompile -o "$app" -e '
        on open theFiles
          repeat with f in theFiles
            do shell script "${opener} " & quoted form of POSIX path of f
          end repeat
        end open
        -- Launched without a file (e.g. `open -a tmux-hx`): do nothing,
        -- the dock icon bounce is annoying enough already.
        on run
        end run
      '
      # CFBundleIdentifier is what duti targets. osacompile generates a
      # random one each time, so pin it.
      /usr/bin/plutil -replace CFBundleIdentifier -string io.mulatta.tmux-hx \
        "$app/Contents/Info.plist"
      /usr/bin/plutil -replace CFBundleDocumentTypes -json '${
        builtins.toJSON [
          {
            CFBundleTypeName = "tmux-hx documents";
            CFBundleTypeRole = "Editor";
            LSHandlerRank = "Alternate";
            LSItemContentTypes = utis;
          }
        ]
      }' "$app/Contents/Info.plist"
      # Nudge LaunchServices to re-index. -f = force, -R = recursive.
      /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
        -f -R "$app"
    '';

    # duti applies UTI -> bundle-id associations declaratively at activation
    # time. Re-running is harmless. `all` role = viewer + editor + shell.
    home.activation.tmuxHxDuti = lib.hm.dag.entryAfter [ "tmuxHxApp" ] ''
      set_tmux_hx_handler() {
        uti="$1"
        current="$(${pkgs.duti}/bin/duti -d "$uti" 2>/dev/null || true)"
        if [ "$current" = io.mulatta.tmux-hx ]; then
          return
        fi

        # public.data is accepted into LaunchServices but duti may still report
        # LSSetDefaultRoleHandlerForContentType error -50. Trust the resulting
        # association instead of the transient status.
        ${pkgs.duti}/bin/duti -s io.mulatta.tmux-hx "$uti" all 2>/dev/null || true
        current="$(${pkgs.duti}/bin/duti -d "$uti" 2>/dev/null || true)"
        if [ "$current" != io.mulatta.tmux-hx ]; then
          ${pkgs.duti}/bin/duti -s io.mulatta.tmux-hx "$uti" all
        fi
      }

      ${lib.concatMapStringsSep "\n" (uti: ''
        set_tmux_hx_handler ${lib.escapeShellArg uti}
      '') utis}
    '';
  })
]
