import json
import sys
import tomllib
from pathlib import Path


def entry(root: str) -> dict[str, object]:
    path = Path(root) / "herdr-plugin.toml"
    with path.open("rb") as file:
        manifest = tomllib.load(file)
    return {
        "plugin_id": manifest["id"],
        "name": manifest["name"],
        "version": manifest["version"],
        "min_herdr_version": manifest.get("min_herdr_version", ""),
        "manifest_path": str(path),
        "plugin_root": root,
        "enabled": True,
        "source": {"kind": "local"},
    }


json.dump(
    sorted((entry(root) for root in sys.argv[1:]), key=lambda item: item["plugin_id"]),
    sys.stdout,
    indent=2,
)
print()
