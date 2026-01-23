{
  lib,
  fetchFromGitHub,
  qt6Packages,
  stdenv,
  cmake,
  kdePackages,
  bzip2,
  libp11,
  librsvg,
  openssl,
  pcre,
  pkg-config,
  sphinx,
  sqlite,
}:

let
  # kdePackages scope is marked Linux-only, but ECM and KArchive are
  # pure CMake/Qt and build fine on macOS. Override the scope so
  # transitive deps also get the platform override.
  kdePackagesDarwin = kdePackages.overrideScope (
    _final: prev: {
      extra-cmake-modules = prev.extra-cmake-modules.overrideAttrs (old: {
        meta = old.meta // {
          platforms = lib.platforms.all;
        };
      });
      karchive = prev.karchive.overrideAttrs (old: {
        buildInputs = (old.buildInputs or [ ]) ++ [ bzip2 ];
        meta = old.meta // {
          platforms = lib.platforms.all;
        };
      });
    }
  );
in

stdenv.mkDerivation rec {
  pname = "nextcloud-client";
  version = "4.0.3";

  outputs = [
    "out"
    "dev"
  ];

  src = fetchFromGitHub {
    owner = "nextcloud-releases";
    repo = "desktop";
    tag = "v${version}";
    hash = "sha256-PwL5USUP60ePxn0U7zyx6hHQlx4xKVquZ1QLTWTsSRU=";
  };

  nativeBuildInputs = [
    pkg-config
    cmake
    kdePackagesDarwin.extra-cmake-modules
    librsvg
    sphinx
    qt6Packages.wrapQtAppsHook
  ];

  buildInputs = [
    kdePackagesDarwin.karchive
    libp11
    openssl
    pcre
    qt6Packages.qt5compat
    qt6Packages.qtbase
    qt6Packages.qtkeychain
    qt6Packages.qtsvg
    qt6Packages.qttools
    qt6Packages.qtwebengine
    qt6Packages.qtwebsockets
    sqlite
  ];

  cmakeFlags = [
    "-DBUILD_UPDATER=OFF"
    "-DCMAKE_INSTALL_LIBDIR=lib"
    "-DMIRALL_VERSION_SUFFIX="
    "-DBUILD_OWNCLOUD_OSX_BUNDLE=OFF"
    "-DBUILD_FILE_PROVIDER_MODULE=OFF"
    "-DBUILD_SHELL_INTEGRATION=OFF"
  ];

  meta = {
    changelog = "https://github.com/nextcloud/desktop/releases/tag/v${version}";
    description = "Desktop sync client for Nextcloud";
    homepage = "https://nextcloud.com";
    license = lib.licenses.gpl2Plus;
    platforms = lib.platforms.darwin;
    mainProgram = "nextcloudcmd";
  };
}
