import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
import { parse, stringify } from "smol-toml";

// Nix owns the compiler pin. Preserve upstream targets, profile and components,
// and keep native-config's exact-version guard instead of disabling it.
export function pinRustToolchain(source, version) {
  assert.match(version, /^\d+\.\d+\.\d+$/, "expected an exact Nix Rust release");
  const document = parse(source);
  assert.ok(
    document.toolchain &&
      !Array.isArray(document.toolchain) &&
      typeof document.toolchain === "object" &&
      typeof document.toolchain.channel === "string" &&
      document.toolchain.channel.length > 0,
    "expected [toolchain].channel in upstream rust-toolchain.toml",
  );
  document.toolchain.channel = version;
  return stringify(document);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [, , file, version] = process.argv;
  assert.ok(file && version, "usage: nix-rust-toolchain.mjs FILE VERSION");
  writeFileSync(file, pinRustToolchain(readFileSync(file, "utf8"), version));
}
