{
  pkgs,
  package,
}:

let
  token = "agentsview-test-token";

  # Upstream internal/parser/testdata/claude/valid_session.jsonl. A session needs a second
  # user turn, or agentsview files it as one-shot and hides it from listings.
  session = pkgs.writeText "session.jsonl" ''
    {"type":"user","timestamp":"2024-01-01T10:00:00Z","message":{"content":"Fix the login bug"},"cwd":"/home/alice/code/my-app"}
    {"type":"assistant","timestamp":"2024-01-01T10:00:05Z","message":{"model":"claude-sonnet-4-20250514","content":[{"type":"text","text":"Looking at the auth module..."},{"type":"tool_use","id":"toolu_1","name":"Read","input":{"file_path":"src/auth.ts"}}],"usage":{"input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":200,"cache_read_input_tokens":300}}}
    {"type":"user","timestamp":"2024-01-01T10:05:00Z","message":{"content":"That looks right"}}
    {"type":"assistant","timestamp":"2024-01-01T10:05:05Z","message":{"model":"claude-sonnet-4-20250514","content":[{"type":"text","text":"Applied the fix."}],"usage":{"input_tokens":150,"output_tokens":75,"cache_creation_input_tokens":0,"cache_read_input_tokens":500}}}
  '';

  sshKeys = import "${pkgs.path}/nixos/tests/ssh-keys.nix" pkgs;
in
pkgs.testers.runNixOSTest {
  name = "agentsview";

  nodes.remote = {
    services.openssh.enable = true;
    users.users.alice = {
      isNormalUser = true;
      openssh.authorizedKeys.keys = [ sshKeys.snakeOilPublicKey ];
    };
    # A matching agentsview on PATH keeps sync from downloading a release binary.
    environment.systemPackages = [ package ];
  };

  nodes.collector = {
    imports = [ ./default.nix ];

    services.agentsview = {
      enable = true;
      inherit package;
      host = "0.0.0.0";
      authTokenFile = pkgs.writeText "token" token;
      sshKeyFile = sshKeys.snakeOilPrivateKey;
      sshConfig = ''
        Host remote
          User alice
          StrictHostKeyChecking no
          UserKnownHostsFile /dev/null
      '';
      settings.remote_hosts = [
        {
          host = "remote";
          transport = "ssh";
          interval = "10s";
        }
      ];
    };
  };

  testScript = ''
    import json
    from datetime import timedelta

    remote.wait_for_unit("sshd.service")
    remote.succeed(
        "install -D -o alice -m 0644 ${session} /home/alice/.claude/projects/-home-alice-code-my-app/s1.jsonl"
    )

    collector.wait_for_unit("agentsview.service")
    collector.wait_for_open_port(8080)

    with subtest("the API requires the configured token"):
        collector.fail("curl -sf http://127.0.0.1:8080/api/v1/sessions")
        collector.succeed(
            "curl -sf -H 'Authorization: Bearer ${token}' http://127.0.0.1:8080/api/v1/sessions"
        )

    with subtest("sessions from the ssh remote reach the archive"):
        collector.wait_until_succeeds(
            "curl -sf -H 'Authorization: Bearer ${token}' http://127.0.0.1:8080/api/v1/sessions"
            " | grep -q 'Fix the login bug'",
            timeout=timedelta(minutes=2),
        )

    with subtest("managed settings merge without dropping generated keys"):
        config = collector.succeed(
            "${pkgs.remarshal}/bin/remarshal -f toml -t json /var/lib/agentsview/config.toml"
        )
        before = json.loads(config)
        assert before["remote_hosts"][0]["host"] == "remote", before
        assert before.get("cursor_secret"), before

        collector.systemctl("restart agentsview.service")
        collector.wait_for_open_port(8080)
        after = json.loads(collector.succeed(
            "${pkgs.remarshal}/bin/remarshal -f toml -t json /var/lib/agentsview/config.toml"
        ))
        assert after["cursor_secret"] == before["cursor_secret"], (before, after)
  '';
}
