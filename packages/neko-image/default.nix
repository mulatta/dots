{ dockerTools }:
dockerTools.pullImage {
  imageName = "ghcr.io/m1k1o/neko/chromium";
  imageDigest = "sha256:a79093411aced75b3ed7110d50ec9082f9933afabd6592254f01c383678082e7";
  hash = "sha256-sZ3Z0Ti/PYXP7Qqxbm6w+09Asfld4uQxnUai+62Q/tM=";
  finalImageTag = "3.1.5";
  os = "linux";
  arch = "amd64";
}
