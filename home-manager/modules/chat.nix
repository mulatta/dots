{ pkgs, ... }:
{
  home.packages =
    let
      weechat = pkgs.wrapWeechat pkgs.weechat-unwrapped { };
      matrixPlugin =
        if pkgs.stdenv.hostPlatform.isDarwin then
          pkgs.runCommand "weechat-matrix-rs-plugin" { } ''
            mkdir -p "$out/lib/weechat/plugins"
            ln -s "${pkgs.weechat-matrix-rs}/lib/weechat/plugins/matrix${pkgs.stdenv.hostPlatform.extensions.sharedLibrary}" \
              "$out/lib/weechat/plugins/matrix.so"
          ''
        else
          pkgs.weechat-matrix-rs;
    in
    [
      (weechat.override {
        configure =
          { availablePlugins, ... }:
          {
            scripts = with pkgs.weechatScripts; [
              wee-slack
            ];
            plugins = [
              availablePlugins.python
              availablePlugins.perl
              availablePlugins.lua
              {
                pluginFile = "${matrixPlugin}/lib/weechat/plugins/matrix.so";
              }
            ];
          };
      })
    ];
}
