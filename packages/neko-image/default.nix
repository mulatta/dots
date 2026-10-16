{ dockerTools }:
dockerTools.pullImage {
  imageName = "ghcr.io/m1k1o/neko/chromium";
  imageDigest = "sha256:270face8b8111e639744fb7bcdbbf0deed227900bb89d58b2f8adfc12af8c41e";
  hash = "sha256-boUefHW01eBTdjKX1fKIXVXYOkc7IcMKn6ycEbCD16U=";
  finalImageTag = "3.2.0";
  os = "linux";
  arch = "amd64";
}
