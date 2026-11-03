{
  lib,
  buildPythonPackage,
  fetchPypi,
  hatchling,
  aiohttp,
  aiohttp-retry,
  pydantic,
  python-dateutil,
  typing-extensions,
  urllib3,
  yarl,
}:

buildPythonPackage (finalAttrs: {
  pname = "hindsight-client";
  version = "1.2.0";
  pyproject = true;

  src = fetchPypi {
    pname = "hindsight_client";
    inherit (finalAttrs) version;
    hash = "sha256-Hi3UbubnM3SRc89lNdQ1iZqJ+WzOkd2pLq/PgM+kpcU=";
  };

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
})
