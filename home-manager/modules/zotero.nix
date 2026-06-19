{
  inputs,
  ...
}:
{
  imports = [ inputs.zhost.homeModules.zotero ];

  # Patched Zotero pointed at the self-hosted server. The package derives itself
  # from these endpoints (see zhost's homeModule — no overlay needed); on darwin
  # the bundle is deep-signed into ~/Applications at activation.
  programs.zotero = {
    enable = true;
    apiUrl = "https://zotero.mulatta.io/";
    wwwUrl = "https://zotero.mulatta.io/";
    streamUrl = "wss://zotero.mulatta.io/stream/";
  };
}
