{
  lib,
  pkgs,
  ...
}:
let
  settings = {
    # ===== Appearance =====
    alpha-blending = "linear";
    auto-update-channel = "tip";
    background-blur = true;
    background-opacity = 0.9;
    theme = "nightfox";

    # ===== Clipboard =====
    clipboard-paste-protection = false;
    clipboard-read = "allow";
    confirm-close-surface = true;
    copy-on-select = "clipboard";

    # ===== Cursor =====
    cursor-style = "block_hollow";
    cursor-style-blink = false;
    cursor-color = "#C4A7E7";

    # ===== Font =====
    font-family = "BerkeleyMono Nerd Font";
    font-feature = [
      "calt"
      "liga"
      "zero"
    ];
    font-size = 15;
    font-codepoint-map = [
      "U+e0b0-U+e0b3,U+e0b4-U+e0c8,U+e0cc-U+e0d4,U+e0ca=JetBrainsMono Nerd Font Mono"
      "U+e5fa-U+e6b1=JetBrainsMono Nerd Font Mono"
      "U+ea60-U+ebeb=JetBrainsMono Nerd Font Mono"
      "U+f000-U+f2e0,U+e200-U+e2a9=JetBrainsMono Nerd Font Mono"
    ];

    # ===== Keybindings =====
    keybind = [
      "cmd+v=paste_from_clipboard"
      "cmd+c=copy_to_clipboard"
      "cmd+w=close_window"
      "cmd+n=new_window"
      "cmd+q=quit"
      "cmd+plus=increase_font_size:1"
      "cmd+minus=decrease_font_size:1"
      "cmd+0=reset_font_size"
      "global:ctrl+;=toggle_quick_terminal"
    ];

    # ===== Mouse =====
    mouse-hide-while-typing = true;

    # ===== Shell =====
    shell-integration = "fish";
    shell-integration-features = "no-cursor,sudo,no-title";
    command = "${pkgs.fish}/bin/fish";

    # ===== Window =====
    window-decoration = "auto";
    window-height = 9999;
    window-padding-balance = true;
    window-save-state = "always";
    window-theme = "dark";
    window-width = 9999;
    window-colorspace = "display-p3";

    # ===== Quick Terminal =====
    quick-terminal-position = "bottom";
    quick-terminal-screen = "mouse";
    quick-terminal-animation-duration = 0.2;
    quick-terminal-autohide = true;
    quick-terminal-space-behavior = "move";

    # ===== Palette =====
    palette = [ "0=#1b1b1b" ];
  }
  // lib.optionalAttrs (pkgs.stdenv.isDarwin) {
    macos-option-as-alt = true;
    macos-titlebar-style = "hidden";
    macos-non-native-fullscreen = "visible-menu";
    macos-auto-secure-input = true;
    macos-secure-input-indication = true;
  };
  toGhosttyConfig =
    settings:
    lib.concatStringsSep "\n" (
      lib.mapAttrsToList (
        key: value:
        if lib.isList value then
          lib.concatMapStringsSep "\n" (v: "${key} = ${toString v}") value
        else if lib.isBool value then
          "${key} = ${if value then "true" else "false"}"
        else if lib.isString value then
          "${key} = ${value}"
        else
          "${key} = ${toString value}"
      ) settings
    );
in
{
  programs.ghostty = lib.mkIf (pkgs.stdenv.isLinux) {
    enable = true;
    package = pkgs.ghostty;
    enableFishIntegration = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    installBatSyntax = true;
    clearDefaultKeybinds = true;
    inherit settings;
  };

  xdg.configFile = lib.mkIf (pkgs.stdenv.isDarwin) {
    "ghostty/config".text = toGhosttyConfig settings;
  };
}
