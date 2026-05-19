{
  coreutils,
  jq,
  n8nCli,
  writeShellApplication,
}:
writeShellApplication {
  name = "n8n-provision";
  runtimeInputs = [
    coreutils
    jq
    n8nCli
  ];
  text = builtins.readFile ./n8n-provision.sh;
}
