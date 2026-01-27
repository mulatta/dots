---
name: nix-cuda
description: CUDA package patterns for Nix. Dynamic linking, autoPatchelfHook, cudaPackages, binary cache setup.
user-invocable: false
---

## CUDA Package Building in Nix

### Core Mechanism: autoPatchelfHook

PyPI wheels and prebuilt binaries expect FHS paths (`/usr/lib64/...`). Nix uses `autoPatchelfHook` to patch ELF RPATH to Nix store paths.

```nix
buildPythonPackage {
  nativeBuildInputs = [
    autoPatchelfHook      # Auto-patch ELF binaries
    autoAddDriverRunpath  # Add NVIDIA driver path
    addDriverRunpath      # Runtime driver linking
  ];

  buildInputs = with cudaPackages; [
    cuda_cudart   # libcudart.so
    cuda_nvrtc    # libnvrtc.so (JIT compilation)
    cuda_cupti    # Profiling
    cudnn         # Deep learning primitives
    libcublas     # Linear algebra
    libcufft      # FFT
    libcurand     # Random numbers
    libcusolver   # Dense solvers
    libcusparse   # Sparse matrices
    nccl          # Multi-GPU communication
  ];

  # Runtime-only driver (provided by system)
  autoPatchelfIgnoreMissingDeps = [ "libcuda.so.1" ];
}
```

### Binary Cache (Avoid Recompilation)

Add to NixOS config or flake:

```nix
nix.settings = {
  substituters = [ "https://cache.nixos-cuda.org" ];
  trusted-public-keys = [ "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M=" ];
};
```

### Enable CUDA Support

**Per-package** (recommended):

```nix
pkgs.python3Packages.torch.override { cudaSupport = true; }
```

**Flake-wide**:

```nix
pkgs = import nixpkgs {
  system = "x86_64-linux";
  config = {
    allowUnfree = true;  # Required for CUDA
    cudaSupport = true;
  };
};
```

### Common Patterns

#### Python Package with CUDA (torch-bin style)

```nix
buildPythonPackage {
  pname = "my-cuda-package";
  format = "wheel";
  src = fetchurl { /* wheel URL */ };

  nativeBuildInputs = [
    autoPatchelfHook
    autoAddDriverRunpath
  ];

  buildInputs = with cudaPackages; [
    cuda_cudart cuda_nvrtc cudnn libcublas nccl
  ];

  # Add internal lib path for cross-references
  postFixup = ''
    addAutoPatchelfSearchPath "$out/${python.sitePackages}/torch/lib"
  '';

  # Extra RPATH for runtime discovery
  postPatchelfPhase = ''
    find "$out" -type f -name '*.so' -exec \
      patchelf {} --add-rpath "${lib.getLib cudaPackages.cuda_nvrtc}/lib" \;
  '';

  dontStrip = true;  # Avoid ELF alignment issues
}
```

#### Source Build with CUDA

```nix
stdenv.mkDerivation {
  nativeBuildInputs = [
    cmake
    pkg-config
    cudaPackages.cuda_nvcc  # nvcc compiler
  ];

  buildInputs = with cudaPackages; [
    cuda_cudart
    cuda_cccl     # CUDA C++ Core Libraries
    libcublas
  ];

  cmakeFlags = [
    "-DCUDA_TOOLKIT_ROOT_DIR=${cudaPackages.cudatoolkit}"
    "-DCMAKE_CUDA_ARCHITECTURES=all"
  ];
}
```

#### Triton-style Patching (Build-time RPATH injection)

```nix
patches = [
  (replaceVars ./add-driver-rpath.patch {
    ccCmdExtraFlags = "-Wl,-rpath,${addDriverRunpath.driverLink}/lib";
  })
  (replaceVars ./cuda-stubs.patch {
    libcudaStubsDir = "${cudaPackages.cuda_cudart}/lib/stubs";
  })
];
```

### Error Patterns

| Error                       | Cause            | Fix                                  |
| --------------------------- | ---------------- | ------------------------------------ |
| `libcuda.so.1: cannot open` | Missing driver   | `autoPatchelfIgnoreMissingDeps`      |
| `libnvrtc.so: not found`    | Missing CUDA lib | Add `cuda_nvrtc` to buildInputs      |
| `CUDA unknown error`        | Driver mismatch  | Check `nvidia-smi` version           |
| `nvcc not found`            | Missing compiler | Add `cuda_nvcc` to nativeBuildInputs |
| `ptxas not found`           | Triton JIT       | Patch ptxas path explicitly          |

### Verification

```bash
# Check CUDA linkage
ldd ./result/bin/app | grep -E "(cuda|nvrtc|cublas)"

# Verify RPATH
patchelf --print-rpath ./result/bin/app

# Test CUDA availability
nix shell .#package -c python -c "import torch; print(torch.cuda.is_available())"

# Check for /build/ contamination
strings ./result/bin/app | grep /build/ || echo "RPATH clean"
```

### uvx/pip on NixOS Workaround

If using uvx with CUDA packages fails due to dynamic linking:

```bash
# Quick fix: LD_LIBRARY_PATH
LD_LIBRARY_PATH=/run/current-system/sw/share/nix-ld/lib \
  uvx --from=package-name command

# Better: Use nixpkgs version
nix run nixpkgs#python3Packages.package-name

# Best: Package with Nix using autoPatchelfHook
```

### cudaPackages Reference

| Package       | Provides       | Use Case        |
| ------------- | -------------- | --------------- |
| `cuda_cudart` | libcudart.so   | Core runtime    |
| `cuda_nvrtc`  | libnvrtc.so    | JIT compilation |
| `cuda_nvcc`   | nvcc           | CUDA compiler   |
| `cuda_cccl`   | Headers        | C++ templates   |
| `cudnn`       | libcudnn.so    | Deep learning   |
| `libcublas`   | libcublas.so   | Linear algebra  |
| `nccl`        | libnccl.so     | Multi-GPU       |
| `cutensor`    | libcutensor.so | Tensor ops      |
| `cudatoolkit` | Full toolkit   | Legacy compat   |
