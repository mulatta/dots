# Loaded as sitecustomize inside the hindsight-api image. The ChatGPT Codex backend
# routes prompt caching on the session_id / x-client-request-id headers (as Hermes and
# the Codex CLI send them); Hindsight 0.10.3 sends neither, so even a pinned body key
# never hit (probe: 0 cached vs 1792/2717 on luna and 2560/2717 on gpt-6.1-sol).
import sys


def _patch() -> None:
    from hindsight_api.engine.providers.codex_llm import CodexLLM

    build = CodexLLM._build_request_headers

    def build_request_headers(self):
        headers = build(self)
        # Same value as the body key from HINDSIGHT_API_LLM_EXTRA_BODY, so both agree.
        key = self._extra_body.get("prompt_cache_key")
        if key:
            headers.setdefault("session_id", key)
            headers.setdefault("x-client-request-id", key)
        return headers

    CodexLLM._build_request_headers = build_request_headers


# An upstream refactor must not break interpreter startup.
try:
    _patch()
except (ImportError, AttributeError) as exc:
    print(f"hindsight-codex-cache: patch not applied: {exc!r}", file=sys.stderr)
