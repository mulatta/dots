---
name: nix-build-fixes
description: Nix build error patterns and fixes
user-invocable: false
---

## Error Pattern Reference

| Error Pattern                                   | Type          | Fix                |
| ----------------------------------------------- | ------------- | ------------------ |
| `hash mismatch` / `got: sha256-...`             | Hash          | Update hash        |
| `Package requirements (X) were not met`         | Missing dep   | Add to buildInputs |
| `Could not find X` / `library not found`        | Missing dep   | Add to buildInputs |
| `undefined reference to '*.lto_priv.*'`         | LTO           | Disable LTO on dep |
| `No rule to make target '*.1'`                  | Docs          | Disable doc build  |
| `RPATH contains forbidden reference to /build/` | RPATH         | patchelf shrink    |
| Test `FAILED`                                   | Test          | `doCheck = false`  |
| `/usr/bin/perl: not found`                      | Abs path      | substituteInPlace  |
| `cargoHash`/`vendorHash` mismatch               | Cargo/Go hash | Update hash        |

## Fix Recipes

### Hash Mismatch

Extract correct hash from error output, replace in package.nix:

```nix
hash = "sha256-CORRECT_HASH_FROM_ERROR";
```

### Missing Dependency

1. Identify package name from error
2. Search: `nix search nixpkgs "NAME"`
3. Add to correct list:
   - Build tools (cmake, pkg-config, meson) → `nativeBuildInputs`
   - Libraries (zlib, openssl) → `buildInputs`
   - Python runtime deps → `propagatedBuildInputs`

### LTO Symbol Error

Override the problematic dependency:

```nix
let
  dep-no-lto = dep.overrideAttrs (old: {
    env = (old.env or {}) // {
      NIX_CFLAGS_COMPILE = toString (
        lib.toList (old.env.NIX_CFLAGS_COMPILE or "")
        ++ ["-fno-lto" "-ffat-lto-objects"]
      );
    };
  });
in
```

### Documentation Build Failure

Disable doc generation:

```nix
postConfigure = ''
  sed -i '/^SUBDIRS/s/Doc//' Makefile
'';
```

Or with CMake:

```nix
cmakeFlags = [ "-DBUILD_DOC=OFF" ];
```

### RPATH Issues

```nix
noAuditTmpdir = true;
postFixup = ''
  for bin in $out/bin/*; do
    if file "$bin" | grep -q "ELF"; then
      patchelf --shrink-rpath "$bin" || true
    fi
  done
'';
```

### Absolute Path References

```nix
preConfigure = ''
  substituteInPlace scripts/tool.sh \
    --replace-fail "/usr/bin/perl" "${perl}/bin/perl"
'';
```

### Python: Missing Module at Runtime

Move from `buildInputs` to `propagatedBuildInputs`:

```nix
propagatedBuildInputs = [ dep ];  # not buildInputs
```

### Rust: cargoHash Mismatch

```nix
cargoHash = "sha256-CORRECT_HASH";
```

Use `lib.fakeHash` initially, then fix from error.

### Go: vendorHash Mismatch

```nix
vendorHash = "sha256-CORRECT_HASH";
```

Use `null` if vendor/ is committed, otherwise `lib.fakeHash` then fix.

## Build Loop Strategy

1. Build with `nix build .#NAME --print-build-logs 2>&1`
2. Parse error → match pattern from table above
3. Apply fix
4. Track changes: `jj file track` if new files
5. Retry (max 10 iterations)
6. If stuck: `nix build .#NAME --keep-failed` then inspect `/tmp/nix-build-*`
