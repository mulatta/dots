import json

import pytest

from slack_manifest_cli.errors import ManifestError
from slack_manifest_cli.manifest import dump_manifest, manifest_api_value, parse_manifest


def test_parse_yaml_manifest() -> None:
    manifest = parse_manifest(
        """
        display_information:
          name: Test App
        oauth_config:
          scopes:
            user:
              - channels:read
        """
    )

    assert manifest["display_information"]["name"] == "Test App"
    assert manifest["oauth_config"]["scopes"]["user"] == ["channels:read"]


def test_parse_json_manifest() -> None:
    manifest = parse_manifest('{"display_information":{"name":"Test App"}}')

    assert manifest == {"display_information": {"name": "Test App"}}


def test_manifest_must_be_object() -> None:
    with pytest.raises(ManifestError):
        parse_manifest("- not\n- object\n")


def test_manifest_api_value_is_json_string() -> None:
    value = manifest_api_value({"b": 2, "a": 1})

    assert json.loads(value) == {"a": 1, "b": 2}
    assert " " not in value


def test_dump_yaml_manifest() -> None:
    rendered = dump_manifest({"display_information": {"name": "Test App"}}, "yaml")

    assert "display_information:" in rendered
    assert "name: Test App" in rendered
