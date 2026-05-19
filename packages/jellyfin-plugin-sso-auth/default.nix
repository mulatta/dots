{
  lib,
  fetchFromGitHub,
  buildDotnetModule,
  dotnetCorePackages,
  yq,
}:

buildDotnetModule rec {
  pname = "jellyfin-plugin-sso-auth";
  version = "4.0.0.3";

  src = fetchFromGitHub {
    owner = "9p4";
    repo = "jellyfin-plugin-sso";
    rev = "v${version}";
    hash = "sha256-xaOqKX1sRTpFN/SuiYAnIc4wIM4eiz+JMqHWQp2xHf8=";
  };

  prePatch = ''
    # The plugin no longer needs its F# helper library for the Jellyfin 10.11 build,
    # and dropping it keeps the package on the standard .NET SDK path.
    rm -rf SSO-Auth/Lib
    substituteInPlace SSO-Auth/Api/SSOController.cs \
      --replace-fail 'using SSO_Auth.Lib;' ""
  '';

  projectFile = "SSO-Auth/SSO-Auth.csproj";
  nugetDeps = ./deps.json;

  dotnet-sdk = dotnetCorePackages.sdk_9_0;
  dotnet-runtime = dotnetCorePackages.aspnetcore_9_0;
  dotnetBuildFlags = [
    "--no-self-contained"
    "-p:AssemblyVersion=${version}"
    "-p:FileVersion=${version}"
  ];
  dotnetInstallFlags = [ "-p:Version=${version}" ];

  nativeBuildInputs = [ yq ];

  fixupPhase = ''
    runHook preFixup

    artifacts=(
      Duende.IdentityModel.dll
      Duende.IdentityModel.OidcClient.dll
      SSO-Auth.dll
      SSO-Auth.pdb
    )
    for artifact in "''${artifacts[@]}"; do
      mv "$out/lib/jellyfin-plugin-sso-auth/$artifact" "$out/"
    done
    rm -rf "$out/lib"

    yq '{
      guid: .guid,
      name: .name,
      description: .description,
      overview: .overview,
      owner: .owner,
      category: .category,
      targetAbi: .targetAbi,
      changelog: .changelog,
      timestamp: "2000-01-01T00:00:00Z",
      version: "${version}",
      imageUrl: .imageUrl
    }' build.yaml > "$out/meta.json"

    runHook postFixup
  '';

  meta = {
    description = "SSO authentication plugin for Jellyfin";
    homepage = "https://github.com/9p4/jellyfin-plugin-sso";
    license = lib.licenses.gpl3Only;
    platforms = dotnet-runtime.meta.platforms;
  };
}
