{
  lib,
  buildPythonPackage,
  hindsight,
  hatchling,
  aiohttp,
  aiohttp-retry,
  pydantic,
  python-dateutil,
  typing-extensions,
  urllib3,
  yarl,
}:

buildPythonPackage {
  pname = "hindsight-client";
  # Built from the server's own source so client and server always share a release.
  inherit (hindsight) version src;
  sourceRoot = "${hindsight.src.name}/hindsight-clients/python";
  pyproject = true;

  build-system = [ hatchling ];

  dependencies = [
    aiohttp
    aiohttp-retry
    pydantic
    python-dateutil
    typing-extensions
    urllib3
    yarl
  ];

  pythonImportsCheck = [
    "hindsight_client"
    "hindsight_client_api"
  ];

  meta = {
    description = "Python client for the Hindsight memory API";
    homepage = "https://github.com/vectorize-io/hindsight";
    license = lib.licenses.mit;
  };
}
