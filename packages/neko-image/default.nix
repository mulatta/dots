{ dockerTools }:
dockerTools.pullImage {
  imageName = "ghcr.io/m1k1o/neko/chromium";
  imageDigest = "sha256:2471119c7b4010067f76f3421a78a8bcf35e3c223b2d1f4db084914ec915fb30";
  hash = "sha256-W473+T4TdDm89DZhoblXwk36BkH7ooB001KG5jDn3AQ=";
  finalImageTag = "3.1.6";
  os = "linux";
  arch = "amd64";
}
