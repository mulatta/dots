{ pkgs, ... }:

let
  clientToken = "agw-client-test-token";
  upstreamKey = "sk-upstream-test-key";

  # Records the Authorization header it receives and answers like an OpenAI chat endpoint.
  stubUpstream = pkgs.writers.writePython3 "stub-upstream" { } ''
    import json
    from http.server import BaseHTTPRequestHandler, HTTPServer


    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get("content-length", 0))
            body = json.loads(self.rfile.read(length))
            with open("/tmp/stub-auth", "w") as f:
                f.write(self.headers.get("authorization", ""))
            with open("/tmp/stub-model", "w") as f:
                f.write(body.get("model", ""))
            reply = {
                "id": "chatcmpl-test",
                "object": "chat.completion",
                "created": 0,
                "model": body.get("model", ""),
                "choices": [
                    {
                        "index": 0,
                        "message": {"role": "assistant", "content": "pong"},
                        "finish_reason": "stop",
                    }
                ],
                "usage": {
                    "prompt_tokens": 1,
                    "completion_tokens": 1,
                    "total_tokens": 2,
                },
            }
            data = json.dumps(reply).encode()
            self.send_response(200)
            self.send_header("content-type", "application/json")
            self.send_header("content-length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)


    HTTPServer(("127.0.0.1", 9000), Handler).serve_forever()
  '';
in
pkgs.testers.runNixOSTest {
  name = "agentgateway";

  nodes.machine = {
    imports = [ ./default.nix ];

    systemd.services.stub-upstream = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig.ExecStart = stubUpstream;
    };

    services.agentgateway = {
      enable = true;
      credentials.stub = pkgs.writeText "stub-key" upstreamKey;
      settings = {
        gateways.default.port = 4000;
        llm = {
          policies.apiKey = {
            mode = "strict";
            keys = [
              {
                keyHash = "sha256:${builtins.hashString "sha256" clientToken}";
                metadata.client = "test";
              }
            ];
          };
          models = [
            {
              name = "stub/*";
              provider = "openAI";
              params = {
                baseUrl = "http://127.0.0.1:9000/v1";
                apiKey.file = "/run/credentials/agentgateway.service/stub";
              };
              transformation.model = ''llmRequest.model.stripPrefix("stub/")'';
            }
          ];
          # Exercises the request clock inside a virtual model, as time-of-day routing does.
          virtualModels = [
            {
              name = "timed";
              routing.conditional.targets = [
                {
                  "when" = "request.startTime.getFullYear() >= 2000";
                  model = "stub/current";
                }
                { model = "stub/fallback"; }
              ];
            }
          ];
        };
      };
    };
  };

  testScript = ''
    import json

    def chat(model, token=None):
        auth = f"-H 'authorization: Bearer {token}' " if token else ""
        payload = json.dumps({"model": model, "messages": [{"role": "user", "content": "ping"}]})
        return machine.succeed(
            "curl -s -o /tmp/resp -w '%{http_code}' "
            + auth
            + "-H 'content-type: application/json' "
            + f"-d '{payload}' http://127.0.0.1:4000/v1/chat/completions"
        )

    machine.wait_for_unit("stub-upstream.service")
    machine.wait_for_unit("agentgateway.service")
    machine.wait_for_open_port(4000)

    with subtest("requests without a client token are rejected"):
        assert chat("stub/plain") == "401", "missing token must be rejected"
        assert chat("stub/plain", "wrong-token") == "401", "unknown token must be rejected"

    with subtest("client token reaches upstream with the upstream key"):
        assert chat("stub/plain", "${clientToken}") == "200"
        assert machine.succeed("cat /tmp/stub-auth") == "Bearer ${upstreamKey}"
        assert machine.succeed("cat /tmp/stub-model") == "plain"

    with subtest("upstream key never reaches the client"):
        machine.fail("grep -q '${upstreamKey}' /tmp/resp")

    with subtest("virtual model routes on the request clock"):
        assert chat("timed", "${clientToken}") == "200"
        assert machine.succeed("cat /tmp/stub-model") == "current"
  '';
}
