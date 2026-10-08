{
  fetchFromGitHub,
}:

pyFinal: pyPrev: {
  mcp-types = pyFinal.buildPythonPackage {
    pname = "mcp-types";
    inherit (pyFinal.mcp) version src;
    sourceRoot = "${pyFinal.mcp.src.name}/src/mcp-types";
    pyproject = true;

    build-system = with pyFinal; [
      hatchling
      uv-dynamic-versioning
    ];

    dependencies = with pyFinal; [
      pydantic
      typing-extensions
    ];

    pythonImportsCheck = [ "mcp_types" ];

    meta = pyFinal.mcp.meta // {
      description = "Model Context Protocol wire types";
    };
  };

  # Not an override: nixpkgs mcp 1 deps differ.
  mcp = pyFinal.buildPythonPackage (finalAttrs: {
    pname = "mcp";
    version = "2.1.1";
    pyproject = true;

    src = fetchFromGitHub {
      owner = "modelcontextprotocol";
      repo = "python-sdk";
      tag = "v${finalAttrs.version}";
      hash = "sha256-v3qS18hgOxLjm+IEa/knkfyh0Cz2QFtyqxXTZJepevU=";
    };

    build-system = with pyFinal; [
      hatchling
      uv-dynamic-versioning
    ];

    dependencies =
      with pyFinal;
      [
        anyio
        httpx2
        jsonschema
        mcp-types
        opentelemetry-api
        pydantic
        pyjwt
        python-multipart
        sse-starlette
        starlette
        typing-extensions
        typing-inspection
        uvicorn
      ]
      ++ pyFinal.pyjwt.optional-dependencies.crypto;

    pythonImportsCheck = [
      "mcp"
      "mcp.client.stdio"
      "mcp.client.streamable_http"
      "mcp.server"
    ];

    meta = pyPrev.mcp.meta // {
      changelog = "https://github.com/modelcontextprotocol/python-sdk/releases/tag/v${finalAttrs.version}";
    };
  });
}
