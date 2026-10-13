{
  lib,
  fetchFromGitHub,
  buildDotnetModule,
  dotnetCorePackages,
}:

buildDotnetModule (finalAttrs: {
  pname = "paperless-mcp";
  version = "0.6.1";

  src = fetchFromGitHub {
    owner = "barryw";
    repo = "PaperlessMCP";
    rev = "v${finalAttrs.version}";
    hash = "sha256-yD1CAVLtvVyMmdQeG5bf5SgP6ROuELX8RSA+OkpEi9I=";
  };

  projectFile = "PaperlessMCP/PaperlessMCP.csproj";
  testProjectFile = "PaperlessMCP.Tests/PaperlessMCP.Tests.csproj";
  nugetDeps = ./deps.json;
  doCheck = true;

  dotnet-sdk = dotnetCorePackages.sdk_10_0;
  dotnet-runtime = dotnetCorePackages.aspnetcore_10_0;
  dotnetFlags = [ "-p:Version=${finalAttrs.version}" ];

  executables = [ "PaperlessMCP" ];

  meta = {
    description = "Model Context Protocol server for Paperless-ngx";
    homepage = "https://github.com/barryw/PaperlessMCP";
    license = lib.licenses.mit;
    mainProgram = "PaperlessMCP";
    platforms = finalAttrs.dotnet-runtime.meta.platforms;
  };
})
