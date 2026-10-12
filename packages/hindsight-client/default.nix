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
  version = "0.10.3";
  pyproject = true;

  src = fetchPypi {
    pname = "hindsight_client";
    inherit (finalAttrs) version;
    hash = "sha256-39i5qRLMCdNmdfarSrAqqNx6oQrgkYN5TsW9CDvhlUA=";
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
