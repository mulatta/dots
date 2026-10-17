{ inputs }:
final: _prev: {
  hindsight =
    inputs.llm-agents.packages.${final.stdenv.hostPlatform.system}.hindsight.overridePythonAttrs
      (old: {
        patches = (old.patches or [ ]) ++ [
          # Hindsight sends no session headers, so even a pinned prompt_cache_key
          # never hits the Codex backend's cache. No upstream issue or fix yet.
          ./codex-cache-headers.patch
        ];
        # Local embeddings and reranker; the package leaves torch out by default.
        dependencies = old.dependencies ++ old.optional-dependencies.local-ml;
      });
}
