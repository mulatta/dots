{ pkgs, ... }:
{
  services.vscode-server = {
    enable = true;
    enableFHS = true;
  };

  programs.vscode = {
    enable = true;
    profiles.default = {
      extensions = with pkgs.vscode-extensions; [
        ms-python.python
        ms-python.vscode-pylance
        ms-toolsai.jupyter
        ms-toolsai.jupyter-keymap
        ms-toolsai.jupyter-renderers
        ms-vscode-remote.remote-ssh
      ];

      userSettings = {
        "remote.SSH.useLocalServer" = false;
        "python.defaultInterpreterPath" = "${pkgs.python3}/bin/python";
        "python.languageServer" = "Pylance";
        "jupyter.jupyterServerType" = "local";
      };
    };
  };

  home.packages = with pkgs; [
    python3
    python3Packages.jupyter
    python3Packages.ipykernel
    python3Packages.notebook
  ];
}
