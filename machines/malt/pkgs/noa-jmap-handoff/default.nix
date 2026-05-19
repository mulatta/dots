{ writers }:

writers.writePython3 "noa-jmap-handoff" {
  flakeIgnore = [
    "E501" # long default URLs and systemd credential messages
    "S310" # URLs are declarative service configuration
  ];
} (builtins.readFile ./jmap-handoff.py)
