{ runCommand, hindsight }:

# Built from the server's own source so plugins and server always share a release.
runCommand "hindsight-plugins-${hindsight.version}" { } ''
  mkdir $out
  cp -r ${hindsight.src}/hindsight-integrations/hermes $out/hermes
''
