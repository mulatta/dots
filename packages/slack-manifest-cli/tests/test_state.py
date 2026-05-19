import json
from pathlib import Path

from slack_manifest_cli.state import (
    STATE_FILENAME,
    app_id_for_manifest,
    find_state_file,
    save_app_id_for_manifest,
    state_key,
)


def test_state_key_is_relative_to_state_file(tmp_path: Path) -> None:
    manifest = tmp_path / "definitions" / "read.yaml"
    manifest.parent.mkdir()
    manifest.write_text("display_information: {name: Read}\n")
    state = tmp_path / STATE_FILENAME

    assert state_key(str(manifest), state) == "definitions/read.yaml"


def test_save_and_load_app_id(tmp_path: Path) -> None:
    manifest = tmp_path / "definitions" / "read.yaml"
    manifest.parent.mkdir()
    manifest.write_text("display_information: {name: Read}\n")
    state = tmp_path / STATE_FILENAME

    save_app_id_for_manifest(str(manifest), "A123", state)

    assert app_id_for_manifest(str(manifest), state) == "A123"
    loaded = json.loads(state.read_text())
    assert loaded["manifests"]["definitions/read.yaml"] == {"app_id": "A123"}


def test_find_state_searches_upward(tmp_path: Path) -> None:
    state = tmp_path / STATE_FILENAME
    state.write_text(json.dumps({"version": 1, "manifests": {}}))
    manifest = tmp_path / "definitions" / "nested" / "read.yaml"
    manifest.parent.mkdir(parents=True)
    manifest.write_text("display_information: {name: Read}\n")

    assert find_state_file(str(manifest)) == state
