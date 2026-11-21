{ pkgs, ... }:
{
  home.packages = [
    ((pkgs.wrapWeechat pkgs.weechat-unwrapped { }).override {
      configure =
        { availablePlugins, ... }:
        {
          plugins = [
            availablePlugins.python
            availablePlugins.perl
            availablePlugins.lua
          ];
        };
    })
  ];
}
