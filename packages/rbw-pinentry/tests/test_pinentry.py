import hashlib
import json
import os
import re
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from rbw_pinentry.pinentry import Pinentry


class FakeKeyringError(Exception):
    pass


class FakePasswordDeleteError(Exception):
    pass


class FakeErrors:
    KeyringError = FakeKeyringError
    PasswordDeleteError = FakePasswordDeleteError


class FakeKeyring:
    errors = FakeErrors

    def __init__(self) -> None:
        self.store: dict[tuple[str, str], str] = {}

    def get_password(self, service: str, account: str) -> str | None:
        return self.store.get((service, account))

    def set_password(self, service: str, account: str, password: str) -> None:
        self.store[(service, account)] = password

    def delete_password(self, service: str, account: str) -> None:
        try:
            del self.store[(service, account)]
        except KeyError as e:
            raise FakePasswordDeleteError from e


def write_config(root: str, base_url: str, email: str = "user@example.com") -> None:
    config_dir = Path(root) / "rbw"
    config_dir.mkdir()
    (config_dir / "config.json").write_text(
        json.dumps({"base_url": base_url, "email": email}),
        encoding="utf-8",
    )


class PinentryCacheAccountTests(unittest.TestCase):
    def test_cache_account_is_keychain_safe_digest_of_rbw_server_identity(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            write_config(tmp, "https://vaultwarden.example")

            with mock.patch.dict(
                os.environ,
                {"XDG_CONFIG_HOME": tmp, "RBW_PROFILE": "mulatta"},
                clear=True,
            ):
                account = Pinentry().cache_account

        identity = "\0".join(
            ["mulatta", "https://vaultwarden.example", "user@example.com"]
        )
        expected = f"rbw:{hashlib.sha256(identity.encode()).hexdigest()}"
        self.assertEqual(account, expected)
        self.assertRegex(account, re.compile(r"^rbw:[0-9a-f]{64}$"))

    def test_cache_account_separates_vaultwarden_instances(self) -> None:
        with (
            tempfile.TemporaryDirectory() as left,
            tempfile.TemporaryDirectory() as right,
        ):
            write_config(left, "https://vaultwarden.one")
            write_config(right, "https://vaultwarden.two")

            with mock.patch.dict(
                os.environ,
                {"XDG_CONFIG_HOME": left, "RBW_PROFILE": "mulatta"},
                clear=True,
            ):
                left_account = Pinentry().cache_account
            with mock.patch.dict(
                os.environ,
                {"XDG_CONFIG_HOME": right, "RBW_PROFILE": "mulatta"},
                clear=True,
            ):
                right_account = Pinentry().cache_account

        self.assertNotEqual(left_account, right_account)

    def test_legacy_profile_cache_is_migrated_to_server_scoped_cache(self) -> None:
        fake = FakeKeyring()
        with tempfile.TemporaryDirectory() as tmp:
            write_config(tmp, "https://vaultwarden.example")
            with (
                mock.patch.dict(
                    os.environ,
                    {"XDG_CONFIG_HOME": tmp, "RBW_PROFILE": "rbw"},
                    clear=True,
                ),
                mock.patch("rbw_pinentry.pinentry.keyring", fake),
            ):
                pinentry = Pinentry()
                fake.store[(pinentry.service_name, "rbw")] = "secret"

                self.assertEqual(pinentry._get_cached_password(), "secret")
                self.assertEqual(
                    fake.store[(pinentry.service_name, pinentry.cache_account)],
                    "secret",
                )

    def test_clear_removes_server_scoped_and_legacy_cache(self) -> None:
        fake = FakeKeyring()
        with tempfile.TemporaryDirectory() as tmp:
            write_config(tmp, "https://vaultwarden.example")
            with (
                mock.patch.dict(
                    os.environ,
                    {"XDG_CONFIG_HOME": tmp, "RBW_PROFILE": "rbw"},
                    clear=True,
                ),
                mock.patch("rbw_pinentry.pinentry.keyring", fake),
            ):
                pinentry = Pinentry()
                fake.store[(pinentry.service_name, "rbw")] = "legacy"
                fake.store[(pinentry.service_name, pinentry.cache_account)] = "scoped"

                pinentry.clear_cached_password()

                self.assertEqual(fake.store, {})


if __name__ == "__main__":
    unittest.main()
