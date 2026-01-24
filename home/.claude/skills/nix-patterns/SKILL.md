---
name: nix-patterns
description: Nix flake patterns by language and build system
user-invocable: false
---

## Language Detection

| File             | Language | Builder                     | Flake Input |
| ---------------- | -------- | --------------------------- | ----------- |
| `Cargo.toml`     | Rust     | crane                       | crane       |
| `pyproject.toml` | Python   | poetry2nix or dream2nix     | poetry2nix  |
| `package.json`   | Node     | dream2nix                   | dream2nix   |
| `go.mod`         | Go       | buildGoModule               | (nixpkgs)   |
| `CMakeLists.txt` | C/C++    | stdenv.mkDerivation + cmake | (nixpkgs)   |
| `meson.build`    | C/C++    | stdenv.mkDerivation + meson | (nixpkgs)   |
| `Makefile` only  | C/C++    | stdenv.mkDerivation         | (nixpkgs)   |
| `mix.exs`        | Elixir   | mixRelease                  | (nixpkgs)   |
| `build.zig`      | Zig      | stdenv.mkDerivation + zig   | (nixpkgs)   |

## flake-parts Base Template

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    # language-specific inputs here
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      perSystem = { pkgs, system, ... }: {
        devShells.default = pkgs.mkShell {
          packages = [
            # language tools
          ];
        };

        # packages.default = ...;
      };
    };
}
```

## Rust (crane)

```nix
inputs.crane.url = "github:ipetkov/crane";
```

```nix
perSystem = { pkgs, system, ... }:
let
  craneLib = inputs.crane.mkLib pkgs;
  src = craneLib.cleanCargoSource ./.;
in {
  packages.default = craneLib.buildPackage {
    inherit src;
    # buildInputs = [ ]; # platform deps
  };

  devShells.default = craneLib.devShell {
    packages = [ pkgs.rust-analyzer pkgs.cargo-watch ];
  };
};
```

## Python (poetry2nix)

```nix
inputs.poetry2nix.url = "github:nix-community/poetry2nix";
```

```nix
perSystem = { pkgs, system, ... }:
let
  poetry2nix = inputs.poetry2nix.lib.mkPoetry2Nix { inherit pkgs; };
in {
  packages.default = poetry2nix.mkPoetryApplication {
    projectDir = ./.;
  };

  devShells.default = pkgs.mkShell {
    packages = [
      (poetry2nix.mkPoetryEnv { projectDir = ./.; })
      pkgs.poetry
      pkgs.ruff
      pkgs.pyright
    ];
  };
};
```

## Go

```nix
perSystem = { pkgs, ... }: {
  packages.default = pkgs.buildGoModule {
    pname = "name";
    version = "0.1.0";
    src = ./.;
    vendorHash = null; # or lib.fakeHash then fix
  };

  devShells.default = pkgs.mkShell {
    packages = [ pkgs.go pkgs.gopls pkgs.golangci-lint ];
  };
};
```

## C/C++ (CMake)

```nix
perSystem = { pkgs, ... }: {
  packages.default = pkgs.stdenv.mkDerivation {
    pname = "name";
    version = "0.1.0";
    src = ./.;
    nativeBuildInputs = [ pkgs.cmake pkgs.pkg-config ];
    buildInputs = [ ];
  };

  devShells.default = pkgs.mkShell {
    packages = [ pkgs.cmake pkgs.pkg-config pkgs.clang-tools ];
    inputsFrom = [ self'.packages.default ];
  };
};
```

## .envrc

```bash
use flake
```

## Runtime Verification

```bash
# CLI smoke test
./result/bin/NAME --version || ./result/bin/NAME --help

# Closure analysis
nix-store -qR ./result | wc -l

# Check for build tool leakage
nix-store -qR ./result | grep -E "(cmake|gcc|pkg-config)" || echo "OK"

# Binary deps (Linux)
ldd ./result/bin/NAME | grep "not found"

# Python import test
nix shell .#default -c python -c "import MODULE; print('OK')"
```
