import hashlib
import importlib
import json
import logging
import os
import subprocess
from pathlib import Path
from typing import TYPE_CHECKING, Any

keyring: Any = importlib.import_module("keyring")

if TYPE_CHECKING:
    from collections.abc import Callable

# Set up logging to file so it doesn't interfere with pinentry protocol
cache_dir = (
    Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "rbw-pinentry"
)
log_file = cache_dir / "pinentry.log"
log_kwargs: dict[str, str] = {}
try:
    cache_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    log_kwargs["filename"] = str(log_file)
except OSError:
    pass

if log_kwargs:
    logging.basicConfig(
        level=logging.WARNING,
        format="%(asctime)s - %(levelname)s - %(message)s",
        filename=log_kwargs["filename"],
    )
else:
    logging.basicConfig(
        level=logging.WARNING,
        format="%(asctime)s - %(levelname)s - %(message)s",
    )
logger = logging.getLogger(__name__)


class Pinentry:
    """Pinentry wrapper that caches passwords in system secure storage."""

    def __init__(self) -> None:
        self.rbw_profile = os.environ.get("RBW_PROFILE", "rbw")
        self.service_name = "rbw-master-password"
        self.cache_account = self._build_cache_account()

    def _rbw_config_candidates(self) -> list[Path]:
        candidates: list[Path] = []
        if config_dir := os.environ.get("RBW_CONFIG_DIR"):
            candidates.append(Path(config_dir) / "config.json")
        xdg_config = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
        candidates.append(xdg_config / "rbw" / "config.json")
        return candidates

    def _load_rbw_config(self) -> dict[str, Any]:
        for path in self._rbw_config_candidates():
            try:
                with path.open(encoding="utf-8") as f:
                    data = json.load(f)
                if isinstance(data, dict):
                    return data
            except (FileNotFoundError, json.JSONDecodeError, OSError) as e:
                logger.warning("Failed to read rbw config %s: %s", path, e)
        return {}

    def _build_cache_account(self) -> str:
        config = self._load_rbw_config()
        parts = {
            "profile": self.rbw_profile,
            "base_url": str(config.get("base_url") or ""),
            "email": str(config.get("email") or ""),
        }
        # Include configured server identity so a stale cached password from
        # another rbw config cannot unlock this Vaultwarden account by accident.
        identity = "\0".join(parts[k] for k in ("profile", "base_url", "email"))
        return f"rbw:{hashlib.sha256(identity.encode()).hexdigest()}"

    def _show_zenity_password_dialog(
        self,
        title: str = "",
        prompt: str = "",
        desc: str = "",
        error: str = "",
    ) -> str | None:
        try:
            # Use --entry --hide-text instead of --password to support --text
            zenity_cmd = ["zenity", "--entry", "--hide-text"]

            if title:
                zenity_cmd.extend(["--title", title])
            elif prompt:
                zenity_cmd.extend(["--title", prompt])
            else:
                zenity_cmd.extend(["--title", "rbw"])

            # Build the text to display in the dialog
            text_parts: list[str] = []
            if error:
                text_parts.append(f"Error: {error}")
            if desc:
                text_parts.append(desc)
            if prompt and prompt != title:
                text_parts.append(prompt)

            if text_parts:
                zenity_cmd.extend(["--text", "\n\n".join(text_parts)])
            else:
                zenity_cmd.extend(
                    ["--text", f"Enter master password for '{self.rbw_profile}'"]
                )

            result = subprocess.run(
                zenity_cmd, capture_output=True, text=True, check=False
            )
            if result.returncode == 0 and result.stdout:
                password = result.stdout.strip()
                return password.rstrip("\n") if password else None
        except OSError as e:
            logger.warning("Failed to call zenity: %s", e)
        return None

    def _legacy_cache_accounts(self) -> list[str]:
        if self.rbw_profile == self.cache_account:
            return []
        return [self.rbw_profile]

    def _get_password(self, account: str) -> str | None:
        try:
            return keyring.get_password(self.service_name, account)
        except keyring.errors.KeyringError as e:
            logger.warning("Failed to get password for %s: %s", account, e)
            return None

    def _get_cached_password(self) -> str | None:
        """Get cached password from keyring."""
        password = self._get_password(self.cache_account)
        if password:
            return password

        for account in self._legacy_cache_accounts():
            password = self._get_password(account)
            if password:
                self._cache_password(password)
                return password
        return None

    def _delete_password(self, account: str) -> None:
        try:
            keyring.delete_password(self.service_name, account)
        except keyring.errors.PasswordDeleteError:
            pass  # Password doesn't exist, which is fine
        except keyring.errors.KeyringError as e:
            logger.warning("Failed to delete password for %s: %s", account, e)

    def clear_cached_password(self) -> None:
        """Clear cached password from keyring."""
        self._delete_password(self.cache_account)
        for account in self._legacy_cache_accounts():
            self._delete_password(account)

    def _cache_password(self, password: str) -> None:
        """Cache password in keyring."""
        try:
            keyring.set_password(self.service_name, self.cache_account, password)
        except keyring.errors.KeyringError as e:
            logger.warning("Failed to store password: %s", e)

    def _handle_password(
        self, title: str, prompt: str, desc: str, error: str
    ) -> str | None:
        # If there was an auth error, clear the cached password
        if error:
            logger.warning("Authentication error: %s", error)
            self.clear_cached_password()
        else:
            # Try to return cached password
            cached_password = self._get_cached_password()
            if cached_password:
                return cached_password

        # Set defaults for dialog
        if not title:
            title = "rbw"
        if not desc:
            desc = (
                f"Authentication failed. Please enter the password for '{self.rbw_profile}'"
                if error
                else f"Please enter the password for '{self.rbw_profile}' (will be cached in secure storage)"
            )

        # Show prompt
        secret_value = self._show_zenity_password_dialog(
            title=title, prompt=prompt, desc=desc, error=error
        )

        # Cache password if successfully entered
        if secret_value:
            self._cache_password(secret_value)

        return secret_value

    def _set_state(self, state: dict[str, str], key: str, value: str) -> str:
        state[key] = value
        return "OK"

    def _handle_getpin(self, state: dict[str, str]) -> str:
        secret_value = self._handle_password(
            state["title"], state["prompt"], state["desc"], state["error"]
        )
        if secret_value:
            print(f"D {secret_value}", flush=True)
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
            response = self._process_command(command, args, state)
            if response == "BYE":
                break
            if response:
                print(response, flush=True)
