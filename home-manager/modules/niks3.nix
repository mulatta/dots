{
  self,
  system,
  ...
}:
{
  home.sessionVariables = {
    NIKS3_SERVER_URL = "https://niks3.mulatta.io";
  };
  home.packages = [
    self.inputs.niks3.packages.${system}.niks3
  ];
}
