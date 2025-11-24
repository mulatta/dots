{pkgs, ...}: {
  programs.vscode = {
    enable = true;
    profiles.default = {
      extensions = with pkgs.vscode-extensions;
        [
          ms-python.python
          ms-python.vscode-pylance
          ms-toolsai.jupyter
          ms-toolsai.jupyter-keymap
          ms-toolsai.jupyter-renderers
          ms-vscode-remote.remote-ssh
          mkhl.direnv
        ]
        ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
          {
            name = "vscode-helix-emulation";
            publisher = "jasew";
            version = "0.7.0";
            sha256 = "sha256-gYyIVnXG9Atmik0c1FsRKO2idFnufwl26nOiH3DYPLY=";
          }
        ];
      userSettings = {
        "remote.SSH.useLocalServer" = false;
        "remote.SSH.remotePlatform" = {
          "psi" = "linux";
        };
        "remote.SSH.defaultExtensions" = [
          "ms-python.python"
          "ms-python.vscode-pylance"
          "ms-toolsai.jupyter"
          "ms-toolsai.jupyter-keymap"
          "ms-toolsai.jupyter-renderers"
        ];
      };
    };
  };
}
