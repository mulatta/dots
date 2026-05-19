{ inputs, ... }:
{
  imports = [ inputs.paneru.homeModules.paneru ];

  services.paneru.enable = true;
}
