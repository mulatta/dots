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
  version = "1.1.0";
  pyproject = true;

  src = fetchPypi {
    pname = "hindsight_client";
    inherit (finalAttrs) version;
    hash = "sha256-EyBV7v6tfDuI+3e4bXz+CJ+rjfHCb15wpUKi3xf+buA=";
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
