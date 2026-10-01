{
  writeShellApplication,
  prime-agent,
  pueue,
  writers,
}:
let
  reconcile = writers.writeNuBin "prime-agent-reconcile" ''
    let declarative_path = ($env.HOME | path join "dots/home/.prime/agent/settings.json")
    let live_path = ($env.HOME | path join ".prime/agent/settings.json")
    let managed = [
      extensions
      skills
      prompts
      theme
      themes
      hideThinkingBlock
      defaultProvider
      defaultModel
      defaultThinkingLevel
      telemetry
      mcpServers
    ]

    let declarative = (open $declarative_path)
    let live = if ($live_path | path exists) { open $live_path } else { {} }
    let reconciled = ($managed | reduce --fold $live {|key, settings|
      if ($key in $declarative) {
        $settings | upsert $key ($declarative | get $key)
      } else {
        $settings | reject --optional $key
      }
    })

    if $reconciled != $live {
      let temporary = $"($live_path).tmp.($nu.pid)"
      $reconciled | to json --indent 2 | save --force $temporary
      mv --force $temporary $live_path
    }
  '';
in
writeShellApplication {
  name = "prime-agent";
  runtimeInputs = [ pueue ];
  text = ''
    ${reconcile}/bin/prime-agent-reconcile
    pueued -d >/dev/null 2>&1 || true
    exec ${prime-agent}/bin/prime-agent "$@"
  '';
}
