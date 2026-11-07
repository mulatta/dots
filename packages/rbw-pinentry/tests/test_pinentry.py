import contextlib
import hashlib
import json
import logging
import os
import re
import select
import signal
import subprocess
import sys
import tempfile
import termios
import threading
import time
import unittest
from collections.abc import Iterator
from pathlib import Path
from unittest import mock

from rbw_pinentry.pinentry import CANCELLED, Pinentry, setup_logging


class FakeKeyringError(Exception):
    pass


class FakePasswordDeleteError(FakeKeyringError):
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


class LockedKeyring(FakeKeyring):
    def get_password(self, service: str, account: str) -> str | None:
        raise FakeKeyringError("locked")


class UnusableKeyring(FakeKeyring):
    def get_password(self, service: str, account: str) -> str | None:
        raise AssertionError("keyring must not be read")

    def set_password(self, service: str, account: str, password: str) -> None:
        raise AssertionError("keyring must not be written")


@contextlib.contextmanager
def isolated_home(**env: str) -> Iterator[Path]:
    """A temporary HOME that also covers Path.home(), which macOS resolves via pwd."""
    with tempfile.TemporaryDirectory() as tmp:
        home = Path(tmp)
        with (
            mock.patch.dict(os.environ, {"HOME": tmp, **env}, clear=True),
            mock.patch.object(Path, "home", return_value=home),
        ):
            yield home


def config_dir(home: Path, name: str) -> Path:
    if sys.platform == "darwin":
        return home / "Library" / "Application Support" / name
    return home / ".config" / name


def write_config(
    directory: Path, base_url: str, email: str = "user@example.com"
) -> None:
    directory.mkdir(parents=True)
    (directory / "config.json").write_text(
        json.dumps({"base_url": base_url, "email": email}), encoding="utf-8"
    )


def read_until(fd: int, marker: bytes, timeout: float = 10) -> bytes:
    """Read a PTY until marker appears; fail instead of hanging."""
    seen = b""
    deadline = time.monotonic() + timeout
    while marker not in seen:
        remaining = deadline - time.monotonic()
        if remaining <= 0 or not select.select([fd], [], [], remaining)[0]:
            raise AssertionError(f"{marker!r} not seen; got {seen!r}")
        seen += os.read(fd, 1024)
    return seen


def digest(*parts: str) -> str:
    return f"rbw:{hashlib.sha256(chr(0).join(parts).encode()).hexdigest()}"


class PinentryCacheAccountTests(unittest.TestCase):
    def test_cache_account_is_keychain_safe_digest_of_rbw_server_identity(self) -> None:
        with isolated_home(RBW_PROFILE="mulatta") as home:
            write_config(config_dir(home, "rbw-mulatta"), "https://vault.example")
            account = Pinentry().cache_account

        self.assertEqual(
            account, digest("mulatta", "https://vault.example", "user@example.com")
        )
        self.assertRegex(account or "", re.compile(r"^rbw:[0-9a-f]{64}$"))

    def test_cache_account_separates_vaultwarden_instances(self) -> None:
        accounts = []
        for url in ("https://vault.one", "https://vault.two"):
            with isolated_home() as home:
                write_config(config_dir(home, "rbw"), url)
                accounts.append(Pinentry().cache_account)

        self.assertNotEqual(accounts[0], accounts[1])

    def test_rbw_config_dir_is_ignored(self) -> None:
        with tempfile.TemporaryDirectory() as other:
            write_config(Path(other) / "rbw", "https://other.example")
            with isolated_home(RBW_CONFIG_DIR=f"{other}/rbw") as home:
                write_config(config_dir(home, "rbw"), "https://vault.example")
                account = Pinentry().cache_account

        self.assertEqual(
            account, digest("rbw", "https://vault.example", "user@example.com")
        )

    @unittest.skipUnless(sys.platform == "darwin", "Darwin config path")
    def test_darwin_ignores_xdg_config_home(self) -> None:
        with isolated_home() as home:
            xdg = home / "xdg"
            write_config(xdg / "rbw", "https://xdg.example")
            write_config(config_dir(home, "rbw"), "https://darwin.example")
            with mock.patch.dict(os.environ, {"XDG_CONFIG_HOME": str(xdg)}):
                account = Pinentry().cache_account

        self.assertEqual(
            account, digest("rbw", "https://darwin.example", "user@example.com")
        )

    @unittest.skipIf(sys.platform == "darwin", "Linux config path")
    def test_linux_ignores_relative_xdg_config_home(self) -> None:
        with isolated_home(XDG_CONFIG_HOME="relative") as home:
            write_config(home / ".config" / "rbw", "https://vault.example")
            self.assertIsNotNone(Pinentry().cache_account)

    @unittest.skipIf(sys.platform == "darwin", "Linux config path")
    def test_linux_normalizes_profile_directory(self) -> None:
        # directories lowercases and drops every whitespace run, not only spaces.
        for profile, directory in (
            ("Work", "rbw-work"),
            (" Work\tOps ", "rbw-workops"),
        ):
            with (
                self.subTest(profile=profile),
                isolated_home(RBW_PROFILE=profile) as home,
            ):
                write_config(home / ".config" / directory, "https://work.example")
                self.assertEqual(
                    Pinentry().cache_account,
                    digest(profile, "https://work.example", "user@example.com"),
                )

    def test_missing_config_disables_cache_but_still_prompts(self) -> None:
        with (
            isolated_home(DISPLAY=":0"),
            mock.patch("rbw_pinentry.pinentry.keyring", UnusableKeyring()),
        ):
            pinentry = Pinentry()
            self.assertIsNone(pinentry.cache_account)
            with mock.patch.object(pinentry, "_show_dialog", return_value="typed"):
                value = pinentry._handle_password("rbw", "Master Password", "", "")

        self.assertEqual(value, "typed")

    def test_legacy_profile_cache_is_not_used(self) -> None:
        fake = FakeKeyring()
        with (
            isolated_home(RBW_PROFILE="work") as home,
            mock.patch("rbw_pinentry.pinentry.keyring", fake),
        ):
            write_config(config_dir(home, "rbw-work"), "https://vault.example")
            pinentry = Pinentry()
            fake.store[(pinentry.service_name, "work")] = "possibly-not-master"

            self.assertIsNone(pinentry._get_cached_password())

    def test_clear_removes_server_scoped_and_legacy_cache(self) -> None:
        fake = FakeKeyring()
        with (
            isolated_home() as home,
            mock.patch("rbw_pinentry.pinentry.keyring", fake),
        ):
            write_config(config_dir(home, "rbw"), "https://vault.example")
            pinentry = Pinentry()
            fake.store[(pinentry.service_name, "rbw")] = "legacy"
            fake.store[(pinentry.service_name, pinentry.cache_account or "")] = "new"

            self.assertEqual(pinentry.clear_cached_password(), 2)
            self.assertEqual(fake.store, {})
            self.assertEqual(pinentry.clear_cached_password(), 0)

    def test_clear_reports_keyring_failures(self) -> None:
        with (
            isolated_home() as home,
            mock.patch("rbw_pinentry.pinentry.keyring", LockedKeyring()),
        ):
            write_config(config_dir(home, "rbw"), "https://vault.example")
            with self.assertRaises(FakeKeyringError):
                Pinentry().clear_cached_password()


class PinentryPromptIsolationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fake = FakeKeyring()
        home = self.enterContext(isolated_home(DISPLAY=":0"))
        self.enterContext(mock.patch("rbw_pinentry.pinentry.keyring", self.fake))
        write_config(config_dir(home, "rbw"), "https://vault.example.com")
        self.pinentry = Pinentry()
        self.key = (self.pinentry.service_name, self.pinentry.cache_account or "")

    def prompt(self, prompt: str, typed: str, error: str = "") -> str | None:
        with mock.patch.object(self.pinentry, "_show_dialog", return_value=typed):
            return self.pinentry._handle_password("rbw", prompt, "Log in", error)

    def test_non_master_prompts_ignore_cached_master_password(self) -> None:
        # rbw 1.15 prompts: rbw-agent/actions.rs and the 2FA headers in api.rs.
        prompts = [
            "API key client__id",
            "API key client__secret",
            "Authenticator App",
            "Yubikey",
            "Email Code",
            "Two Factor Authentication",
            "Something Else",
        ]
        for prompt in prompts:
            with self.subTest(prompt=prompt):
                self.fake.store[self.key] = "master"
                self.assertEqual(self.prompt(prompt, "typed"), "typed")
                self.assertEqual(self.fake.store, {self.key: "master"})

    def test_totp_error_does_not_clear_master_password(self) -> None:
        self.fake.store[self.key] = "master"
        self.assertEqual(
            self.prompt("Authenticator App", "654321", "Incorrect TOTP"), "654321"
        )
        self.assertEqual(self.fake.store, {self.key: "master"})

    def test_master_password_comes_from_cache(self) -> None:
        self.fake.store[self.key] = "master"
        self.assertEqual(self.prompt("Master Password", "unused"), "master")

    def test_master_password_error_replaces_cached_password(self) -> None:
        self.fake.store[self.key] = "old"
        self.assertEqual(
            self.prompt("Master Password", "new", "Incorrect password"), "new"
        )
        self.assertEqual(self.fake.store, {self.key: "new"})

    def test_cancelled_prompt_is_an_assuan_error(self) -> None:
        state = {"title": "", "prompt": "Master Password", "desc": "", "error": ""}
        with mock.patch.object(self.pinentry, "_handle_password", return_value=None):
            self.assertEqual(self.pinentry._handle_getpin(state), CANCELLED)

    def test_getpin_percent_encodes_secret(self) -> None:
        state = {"title": "", "prompt": "Master Password", "desc": "", "error": ""}
        with (
            mock.patch.object(
                self.pinentry, "_handle_password", return_value="a%b\nc\r"
            ),
            mock.patch("builtins.print") as print_mock,
        ):
            self.assertEqual(self.pinentry._handle_getpin(state), "OK")

        print_mock.assert_called_once_with("D a%25b%0Ac%0D", flush=True)

    def test_dialog_preserves_surrounding_spaces(self) -> None:
        completed = mock.Mock(returncode=0, stdout=" secret with spaces \n")
        with mock.patch("subprocess.run", return_value=completed):
            value = self.pinentry._run_dialog(["dialog"])

        self.assertEqual(value, " secret with spaces ")

    def test_failed_dialog_logs_stderr_but_not_stdout(self) -> None:
        completed = mock.Mock(
            returncode=1, stdout="typed", stderr="cannot open display"
        )
        with (
            mock.patch("subprocess.run", return_value=completed),
            self.assertLogs("rbw_pinentry.pinentry") as logs,
        ):
            self.assertIsNone(self.pinentry._run_dialog(["zenity"]))

        self.assertIn("cannot open display", logs.output[0])
        self.assertNotIn("typed", logs.output[0])

    def test_empty_display_uses_the_terminal(self) -> None:
        self.pinentry.ttyname = "/dev/tty-test"
        with (
            mock.patch.dict(os.environ, {"DISPLAY": "", "WAYLAND_DISPLAY": ""}),
            mock.patch.object(self.pinentry, "_prompt_tty", return_value="t") as tty,
            mock.patch.object(
                self.pinentry, "_show_dialog", side_effect=AssertionError
            ),
        ):
            self.assertEqual(self.pinentry._prompt_secret("rbw", "P", "", ""), "t")
        tty.assert_called_once()


class PinentryTerminalPromptTests(unittest.TestCase):
    def test_prompts_on_tty_and_caches_without_display(self) -> None:
        master, slave = os.openpty()
        seen = bytearray()

        def type_password() -> None:
            seen.extend(read_until(master, b": "))
            os.write(master, b"hunter2\n")

        typist = threading.Thread(target=type_password)
        fake = FakeKeyring()
        with (
            isolated_home() as home,
            mock.patch("rbw_pinentry.pinentry.keyring", fake),
            mock.patch.object(
                Pinentry, "_show_zenity_password_dialog", side_effect=AssertionError
            ),
        ):
            write_config(config_dir(home, "rbw"), "https://vault.example.com")
            pinentry = Pinentry(ttyname=os.ttyname(slave))
            typist.start()
            password = pinentry._handle_password("rbw", "Master Password", "", "")
            typist.join(timeout=5)

        seen.extend(read_until(master, b"\n"))  # the newline written after the prompt
        os.close(master)
        os.close(slave)
        self.assertEqual(password, "hunter2")
        self.assertIn(b"Master Password", seen)
        self.assertNotIn(b"hunter2", seen)  # echo stays off
        self.assertIn("hunter2", fake.store.values())

    def test_non_terminal_ttyname_fails_without_crashing(self) -> None:
        with isolated_home():
            self.assertIsNone(Pinentry()._prompt_tty(os.devnull, "Password"))

    def test_sigterm_during_prompt_restores_echo_and_cancels(self) -> None:
        master, slave = os.openpty()
        self.addCleanup(os.close, master)
        self.addCleanup(os.close, slave)
        script = (
            "import sys; from rbw_pinentry.pinentry import Pinentry; "
            "Pinentry(ttyname=sys.argv[1]).handle_pinentry_session()"
        )
        with tempfile.TemporaryDirectory() as home:
            # No rbw config in this HOME, so the real keyring is never touched.
            proc = subprocess.Popen(
                [sys.executable, "-c", script, os.ttyname(slave)],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                env={"HOME": home, "PYTHONPATH": os.pathsep.join(sys.path)},
                text=True,
            )
            self.addCleanup(proc.wait, 10)
            self.addCleanup(proc.kill)
            assert proc.stdin is not None
            proc.stdin.write("SETPROMPT Master Password\nGETPIN\n")
            proc.stdin.flush()

            read_until(master, b"Master Password: ")
            self.assertFalse(termios.tcgetattr(slave)[3] & termios.ECHO)

            proc.send_signal(signal.SIGTERM)
            stdout, _ = proc.communicate(timeout=10)

        self.assertEqual(proc.returncode, 0)
        self.assertEqual(stdout.splitlines()[-1], CANCELLED)
        self.assertTrue(termios.tcgetattr(slave)[3] & termios.ECHO)


class LoggingTests(unittest.TestCase):
    def test_unwritable_log_falls_back_to_stderr(self) -> None:
        root = logging.getLogger()
        saved = root.handlers[:]
        self.addCleanup(setattr, root, "handlers", saved)
        root.handlers = []
        with isolated_home() as home:
            # A directory where the log file should be makes the open fail.
            (home / ".cache" / "rbw-pinentry" / "pinentry.log").mkdir(parents=True)
            setup_logging()

        self.assertIs(type(root.handlers[0]), logging.StreamHandler)


if __name__ == "__main__":
    unittest.main()
