import hashlib
import importlib
import json
import logging
import os
import signal
import subprocess
import sys
import termios
from pathlib import Path
from typing import TYPE_CHECKING, Any

keyring: Any = importlib.import_module("keyring")

if TYPE_CHECKING:
    from collections.abc import Callable

logger = logging.getLogger(__name__)

# Assuan GPG_ERR_CANCELED, which rbw-agent reports as a cancelled prompt.
CANCELLED = "ERR 83886179 Operation cancelled"

# Seconds before an unanswered macOS dialog gives up, so a background caller
# without a terminal does not wait forever.
DIALOG_TIMEOUT = 120


class PromptInterrupted(Exception):
    pass


def setup_logging() -> None:
    """Log to a file so messages never interleave with the pinentry protocol."""
    cache_home = os.environ.get("XDG_CACHE_HOME", "")
    base = Path(cache_home) if os.path.isabs(cache_home) else Path.home() / ".cache"
    handler: logging.Handler
    try:
        log_dir = base / "rbw-pinentry"
        log_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
        handler = logging.FileHandler(log_dir / "pinentry.log")
    except OSError:
        # stderr, never stdout: stdout carries the protocol.
        handler = logging.StreamHandler()
    logging.basicConfig(
        level=logging.WARNING,
        format="%(asctime)s - %(levelname)s - %(message)s",
        handlers=[handler],
    )


def rbw_config_path() -> Path:
    """config.json as rbw 1.15 finds it through directories::ProjectDirs."""
    profile = os.environ.get("RBW_PROFILE")
    name = f"rbw-{profile}" if profile else "rbw"
    if sys.platform == "darwin":
        return (
            Path.home()
            / "Library"
            / "Application Support"
            / name.replace(" ", "-")
            / "config.json"
        )
    xdg_config_home = os.environ.get("XDG_CONFIG_HOME", "")
    config_home = (
        Path(xdg_config_home)
        if os.path.isabs(xdg_config_home)
        else Path.home() / ".config"
    )
    return config_home / "".join(name.lower().split()) / "config.json"


class Pinentry:
    """Pinentry wrapper that caches passwords in system secure storage."""

    def __init__(self, ttyname: str | None = None, display: str | None = None) -> None:
        self.ttyname = ttyname
        self.display = display
        self.rbw_profile = os.environ.get("RBW_PROFILE") or "rbw"
        self.service_name = "rbw-master-password"
        self.cache_account = self._build_cache_account()

    def _build_cache_account(self) -> str | None:
        path = rbw_config_path()
        try:
            config = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as e:
            logger.warning("Failed to read rbw config %s: %s", path, e)
            return None
        # Without the account identity the cache could serve another account.
        if not isinstance(config, dict) or not config.get("email"):
            return None
        # Include configured server identity so a stale cached password from
        # another rbw config cannot unlock this Vaultwarden account by accident.
        identity = "\0".join(
            [self.rbw_profile, str(config.get("base_url") or ""), str(config["email"])]
        )
        return f"rbw:{hashlib.sha256(identity.encode()).hexdigest()}"

    @staticmethod
    def _run_dialog(cmd: list[str], env: dict[str, str] | None = None) -> str | None:
        try:
            result = subprocess.run(
                cmd,
                stdin=subprocess.DEVNULL,
                capture_output=True,
                text=True,
                check=False,
                env=env,
            )
        except OSError as e:
            logger.warning("Failed to run %s: %s", cmd[0], e)
            return None
        if result.returncode != 0:
            # Cancel and a failed GUI start share the exit code; stderr tells them
            # apart. stdout is never logged, it may hold the typed secret.
            logger.warning(
                "%s exited %d: %s", cmd[0], result.returncode, result.stderr.strip()
            )
            return None
        return result.stdout.rstrip("\n") or None

    def _show_zenity_password_dialog(self, title: str, text: str) -> str | None:
        env = {**os.environ, "DISPLAY": self.display} if self.display else None
        # --password ignores --text, so the error and description would not show.
        cmd = ["zenity", "--entry", "--hide-text", "--title", title, "--text", text]
        return self._run_dialog(cmd, env)

    def _show_osascript_password_dialog(self, title: str, text: str) -> str | None:
        def q(s: str) -> str:
            return s.replace("\\", "\\\\").replace('"', '\\"')

        dialog = (
            f'set r to display dialog "{q(text)}" with title "{q(title)}" '
            'default answer "" with hidden answer '
            'buttons {"Cancel", "OK"} default button "OK" '
            f"giving up after {DIALOG_TIMEOUT}"
        )
        # A timed-out dialog still returns what was typed so far; treat it as cancel.
        return self._run_dialog(
            [
                "/usr/bin/osascript",
                "-e",
                dialog,
                "-e",
                "if gave up of r then error number -128",
                "-e",
                "text returned of r",
            ]
        )

    def _show_dialog(self, title: str, text: str) -> str | None:
        if sys.platform == "darwin":
            return self._show_osascript_password_dialog(title, text)
        return self._show_zenity_password_dialog(title, text)

    def _prompt_tty(self, ttyname: str, text: str) -> str | None:
        """Read the password on rbw's terminal with echo off, like pinentry-curses."""
        try:
            fd = os.open(ttyname, os.O_RDWR | os.O_NOCTTY)
        except OSError as e:
            logger.warning("Failed to open %s: %s", ttyname, e)
            return None
        line = b""
        old_handlers: dict[signal.Signals, Any] = {}

        # Unwind through the finally below so the terminal gets its echo back.
        def interrupt_prompt(signum: int, _frame: Any) -> None:
            raise PromptInterrupted(f"terminal prompt interrupted by signal {signum}")

        try:
            for sig in (signal.SIGHUP, signal.SIGTERM):
                old_handlers[sig] = signal.getsignal(sig)
                signal.signal(sig, interrupt_prompt)

            old = termios.tcgetattr(fd)
            new = old.copy()
            new[3] &= ~termios.ECHO
            try:
                # Echo goes off before the prompt so nothing typed after it is flushed.
                termios.tcsetattr(fd, termios.TCSAFLUSH, new)
                os.write(fd, f"{text}: ".encode())
                while not line.endswith(b"\n") and (chunk := os.read(fd, 1024)):
                    line += chunk
            finally:
                termios.tcsetattr(fd, termios.TCSAFLUSH, old)
                os.write(fd, b"\n")
        except (OSError, termios.error) as e:
            logger.warning("Failed to prompt on %s: %s", ttyname, e)
            return None
        finally:
            for sig, handler in old_handlers.items():
                signal.signal(sig, handler)
            os.close(fd)
        return line.decode().rstrip("\n") or None

    def _get_cached_password(self) -> str | None:
        if self.cache_account is None:
            return None
        try:
            return keyring.get_password(self.service_name, self.cache_account)
        except keyring.errors.KeyringError as e:
            logger.warning("Failed to get cached password: %s", e)
            return None

    def _forget_cached_password(self) -> None:
        if self.cache_account is None:
            return
        try:
            keyring.delete_password(self.service_name, self.cache_account)
        except keyring.errors.KeyringError as e:
            logger.warning("Failed to delete cached password: %s", e)

    def _cache_password(self, password: str) -> None:
        if self.cache_account is None:
            return
        try:
            keyring.set_password(self.service_name, self.cache_account, password)
        except keyring.errors.KeyringError as e:
            logger.warning("Failed to store password: %s", e)

    def clear_cached_password(self) -> int:
        """Delete cached entries and return how many existed.

        Keyring errors propagate: the macOS backend reports every failed delete,
        not only a missing item, as PasswordDeleteError.
        """
        removed = 0
        # Before server scoping, entries were keyed by the bare profile name.
        for account in [self.cache_account, self.rbw_profile]:
            if account and keyring.get_password(self.service_name, account) is not None:
                keyring.delete_password(self.service_name, account)
                removed += 1
        return removed

    def _prompt_secret(
        self, title: str, prompt: str, desc: str, error: str
    ) -> str | None:
        has_display = bool(
            self.display
            or os.environ.get("WAYLAND_DISPLAY")
            or os.environ.get("DISPLAY")
        )
        if not has_display and self.ttyname:
            text = "\n".join(p for p in (error and f"Error: {error}", desc) if p)
            return self._prompt_tty(self.ttyname, f"{text}\n{prompt or 'Password'}")
        text = "\n\n".join(
            p
            for p in (error and f"Error: {error}", desc, prompt != title and prompt)
            if p
        )
        return self._show_dialog(title, text)

    def _handle_password(
        self, title: str, prompt: str, desc: str, error: str
    ) -> str | None:
        is_master_password = prompt == "Master Password"
        if is_master_password:
            if error:
                logger.warning("Master password authentication error: %s", error)
                self._forget_cached_password()
            else:
                cached_password = self._get_cached_password()
                if cached_password:
                    return cached_password

        if not title:
            title = "rbw"
        if not desc:
            if is_master_password:
                desc = (
                    f"Authentication failed. Please enter the password for '{self.rbw_profile}'"
                    if error
                    else f"Please enter the password for '{self.rbw_profile}'"
                )
            else:
                desc = f"Please enter {prompt or 'the requested secret'}"

        secret_value = self._prompt_secret(title, prompt, desc, error)
        if is_master_password and secret_value:
            self._cache_password(secret_value)
        return secret_value

    def _set_state(self, state: dict[str, str], key: str, value: str) -> str:
        state[key] = value
        return "OK"

    @staticmethod
    def _encode_assuan_data(value: str) -> str:
        return value.replace("%", "%25").replace("\n", "%0A").replace("\r", "%0D")

    def _handle_getpin(self, state: dict[str, str]) -> str:
        secret_value = self._handle_password(
            state["title"], state["prompt"], state["desc"], state["error"]
        )
        if not secret_value:
            return CANCELLED
        print(f"D {self._encode_assuan_data(secret_value)}", flush=True)
        return "OK"

    def _process_command(
        self, command: str, args: str, state: dict[str, str]
    ) -> str | None:
        command_handlers: dict[str, Callable[[], str]] = {
            "SETTITLE": lambda: self._set_state(state, "title", args),
            "SETDESC": lambda: self._set_state(state, "desc", args),
            "SETPROMPT": lambda: self._set_state(state, "prompt", args),
            "SETERROR": lambda: self._set_state(state, "error", args),
            "GETPIN": lambda: self._handle_getpin(state),
            "BYE": lambda: "BYE",
        }
        handler = command_handlers.get(command)
        return handler() if handler else "ERR Unknown command"

    def handle_pinentry_session(self) -> None:
        print("OK", flush=True)
        state: dict[str, str] = {"title": "", "prompt": "", "desc": "", "error": ""}
        while True:
            try:
                line = input()
            except EOFError:
                break
            parts = line.split(" ", 1)
            command = parts[0]
            args = parts[1] if len(parts) > 1 else ""
            try:
                response = self._process_command(command, args, state)
            except PromptInterrupted as e:
                logger.warning("%s", e)
                print(CANCELLED, flush=True)
                break
            if response == "BYE":
                break
            if response:
                print(response, flush=True)
