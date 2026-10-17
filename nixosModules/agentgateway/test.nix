{ pkgs, ... }:

let
  clientToken = "agw-client-test-token";
  # Scoped to Gemini with a one-token budget, so its second call is over budget.
  limitedToken = "agw-limited-test-token";
  upstreamKey = "sk-upstream-test-key";
  # agentgateway moves only Google-shaped keys (AIza..., AQ....) to x-goog-api-key.
  geminiKey = "AIza-upstream-test-key";

  # Records each request's headers and body by API shape and answers in that shape.
  stubUpstream = pkgs.writers.writePython3 "stub-upstream" { } ''
    import json
    from http.server import BaseHTTPRequestHandler, HTTPServer

    USAGE = {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2}


    def openai(body):
        return {
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
            "usage": USAGE,
        }


    def anthropic(body):
        return {
            "id": "msg_test",
            "type": "message",
            "role": "assistant",
            "model": body.get("model", ""),
            "content": [{"type": "text", "text": "pong"}],
            "stop_reason": "end_turn",
            "usage": {"input_tokens": 1, "output_tokens": 1},
        }


    def gemini(_body):
        return {
            "candidates": [
                {
                    "content": {"role": "model", "parts": [{"text": "pong"}]},
                    "finishReason": "STOP",
                }
            ],
            "usageMetadata": {
                "promptTokenCount": 1,
                "candidatesTokenCount": 1,
                "totalTokenCount": 2,
            },
        }


    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get("content-length", 0))
            body = json.loads(self.rfile.read(length))
            if self.path.endswith("/messages"):
                kind, reply = "anthropic", anthropic(body)
            elif ":generateContent" in self.path:
                kind, reply = "gemini", gemini(body)
            else:
                kind, reply = "openai", openai(body)
            record = {
                "path": self.path,
                "headers": {k.lower(): v for k, v in self.headers.items()},
                "body": body,
            }
            with open(f"/tmp/stub-{kind}.json", "w") as f:
                json.dump(record, f)
            data = json.dumps(reply).encode()
            self.send_response(200)
            self.send_header("content-type", "application/json")
            self.send_header("content-length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)


    HTTPServer(("127.0.0.1", 9000), Handler).serve_forever()
  '';

  credential = name: "/run/credentials/agentgateway.service/${name}";
in
pkgs.testers.runNixOSTest {
  name = "agentgateway";

  nodes.machine = {
    imports = [ ./default.nix ];
    environment.systemPackages = [ pkgs.sqlite ];

    systemd.services.stub-upstream = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig.ExecStart = stubUpstream;
    };

    services.agentgateway = {
      enable = true;
      credentials = {
        stub = pkgs.writeText "stub-key" upstreamKey;
        gemini = pkgs.writeText "gemini-key" geminiKey;
      };
      settings = {
        config.standardAttributes.user = "apiKey.name";
        gateways.default.port = 4000;
        llm = {
          policies.apiKey = {
            mode = "strict";
            # Each SDK sends the client key its own way: Anthropic as x-api-key, Google as
            # x-goog-api-key, OpenAI as a bearer token.
            location.expression = ''
              "x-api-key" in request.headers
                ? request.headers["x-api-key"]
                : "x-goog-api-key" in request.headers
                  ? request.headers["x-goog-api-key"]
                  : request.headers["authorization"].stripPrefix("Bearer ")
            '';
            keys = [
              {
                keyHash = "sha256:${builtins.hashString "sha256" clientToken}";
                metadata.name = "test";
              }
              {
                keyHash = "sha256:${builtins.hashString "sha256" limitedToken}";
                metadata.name = "limited";
                allowedModels = [ "gemini-*" ];
                budgets = [
                  {
                    name = "daily";
                    limit = {
                      unit = "Tokens";
                      amount = 1;
                    };
                    window.rolling = "24h";
                    onBudgetExceeded = "Block";
                  }
                ];
              }
            ];
          };
          models = [
            {
              name = "stub/*";
              provider = "openAI";
              params = {
                baseUrl = "http://127.0.0.1:9000/v1";
                apiKey.file = credential "stub";
              };
              transformation.model = ''llmRequest.model.stripPrefix("stub/")'';
            }
            {
              name = "claude-*";
              provider = "anthropic";
              params = {
                baseUrl = "http://127.0.0.1:9000";
                apiKey.file = credential "stub";
              };
            }
            {
              name = "gemini-*";
              provider = "gemini";
              params = {
                baseUrl = "http://127.0.0.1:9000";
                apiKey.file = credential "gemini";
              };
            }
          ];
        };
      };
    };
  };

  testScript = ''
    import json

    def post(path, payload, headers):
        flags = "".join(f"-H '{h}' " for h in headers + ["content-type: application/json"])
        return machine.succeed(
            f"curl -s -o /tmp/resp -w '%{{http_code}}' {flags}"
            + f"-d '{json.dumps(payload)}' http://127.0.0.1:4000{path}"
        )

    def chat(model, token=None):
        auth = [f"authorization: Bearer {token}"] if token else []
        payload = {"model": model, "messages": [{"role": "user", "content": "ping"}]}
        return post("/v1/chat/completions", payload, auth)

    def recorded(kind):
        return json.loads(machine.succeed(f"cat /tmp/stub-{kind}.json"))

    def assert_no_client_token(kind):
        seen = json.dumps(recorded(kind)["headers"])
        assert "${clientToken}" not in seen, f"client token leaked upstream: {seen}"

    machine.wait_for_unit("stub-upstream.service")
    machine.wait_for_unit("agentgateway.service")
    machine.wait_for_open_port(4000)

    with subtest("requests without a client token are rejected"):
        assert chat("stub/plain") == "401", "missing token must be rejected"
        assert chat("stub/plain", "wrong-token") == "401", "unknown token must be rejected"

    with subtest("client token reaches upstream with the upstream key"):
        assert chat("stub/plain", "${clientToken}") == "200"
        req = recorded("openai")
        assert req["headers"]["authorization"] == "Bearer ${upstreamKey}"
        assert req["body"]["model"] == "plain"
        assert_no_client_token("openai")

    with subtest("upstream key never reaches the client"):
        machine.fail("grep -q '${upstreamKey}' /tmp/resp")

    with subtest("anthropic messages authenticate by x-api-key and keep cache_control"):
        system = [{"type": "text", "text": "static prefix", "cache_control": {"type": "ephemeral"}}]
        payload = {
            "model": "claude-test",
            "max_tokens": 16,
            "system": system,
            "messages": [{"role": "user", "content": "ping"}],
        }
        headers = ["anthropic-version: 2023-06-01"]
        assert post("/v1/messages", payload, headers + ["x-api-key: wrong-token"]) == "401"
        assert post("/v1/messages", payload, headers + ["x-api-key: ${clientToken}"]) == "200"
        req = recorded("anthropic")
        assert req["headers"]["x-api-key"] == "${upstreamKey}", req["headers"]
        assert req["body"]["system"][0].get("cache_control") == {"type": "ephemeral"}, req["body"]
        assert_no_client_token("anthropic")

    with subtest("native gemini requests reach generateContent with the upstream key"):
        payload = {"contents": [{"role": "user", "parts": [{"text": "ping"}]}]}
        path = "/v1beta/models/gemini-test:generateContent"
        assert post(path, payload, ["authorization: Bearer ${clientToken}"]) == "200"
        req = recorded("gemini")
        assert req["path"].endswith("/models/gemini-test:generateContent"), req["path"]
        assert req["headers"].get("x-goog-api-key") == "${geminiKey}", req["headers"]
        assert "authorization" not in req["headers"], req["headers"]
        assert_no_client_token("gemini")

    with subtest("google sdk clients authenticate by x-goog-api-key"):
        payload = {"contents": [{"role": "user", "parts": [{"text": "ping"}]}]}
        path = "/v1beta/models/gemini-test:generateContent"
        assert post(path, payload, ["x-goog-api-key: wrong-token"]) == "401"
        assert post(path, payload, ["x-goog-api-key: ${clientToken}"]) == "200"
        req = recorded("gemini")
        assert req["headers"].get("x-goog-api-key") == "${geminiKey}", req["headers"]
        assert_no_client_token("gemini")

    gemini_path = "/v1beta/models/gemini-test:generateContent"
    gemini_payload = {"contents": [{"role": "user", "parts": [{"text": "ping"}]}]}
    limited = ["authorization: Bearer ${limitedToken}"]

    with subtest("a key cannot use models outside allowedModels"):
        assert chat("stub/plain", "${limitedToken}") != "200", "stub/* is not allowed"
        assert post(gemini_path, gemini_payload, limited) == "200"

    with subtest("a key over its budget is blocked, and stays blocked after a restart"):
        assert post(gemini_path, gemini_payload, limited) != "200", "budget must block"
        machine.systemctl("restart agentgateway.service")
        machine.wait_for_open_port(4000)
        assert post(gemini_path, gemini_payload, limited) != "200", "usage must persist"
        assert chat("stub/plain", "${clientToken}") == "200", "other keys are unaffected"

    with subtest("the admin API is a unix socket, and stats and readiness are off"):
        machine.succeed("test -S /run/agentgateway/admin.sock")
        for port in (15000, 15020, 15021):
            machine.fail(f"curl -s -o /dev/null http://127.0.0.1:{port}/")

    with subtest("the request log names the client and keeps no prompt"):
        db = "sqlite3 /var/lib/agentgateway/agentgateway.db"
        machine.wait_until_succeeds(
            f"{db} \"select agentgateway_user, has_payload from request_logs"
            + " where gen_ai_request_model = 'claude-test' limit 1\" | grep -qx 'test|0'"
        )
        assert machine.succeed(f"{db} 'select count(*) from request_log_payloads'").strip() == "0"
  '';
}
