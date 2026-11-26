import base64
import json
import re
from dataclasses import dataclass
from functools import cache
from pathlib import Path
from typing import Any, NoReturn, final

import yaml
from clan_cli.secrets.sops import decrypt_file_raw, load_age_plugins
from clan_lib.errors import ClanCmdError, ClanError
from clan_lib.flake import Flake
from clan_lib.machines.machines import Machine
from clan_lib.ssh.remote import Remote
from clan_lib.vars.get import get_machine_var
from invoke.context import Context
from invoke.exceptions import Exit
from invoke.tasks import task

ROOT = Path(__file__).parent.resolve()


@dataclass(frozen=True)
class SopsFile:
    path: Path
    key: str | None = None


@dataclass(frozen=True)
class ClanVar:
    machine: str
    var: str


type SecretRef = SopsFile | ClanVar


@dataclass(frozen=True)
class Field:
    name: str
    length: int | None
    kind: str | None

    def row(self) -> str:
        length = None if self.length is None else str(self.length)
        return "\t".join(part for part in (self.name, length, self.kind) if part)


@final
class Plaintext:
    __slots__ = ("_value",)

    def __init__(self, value: bytes) -> None:
        self._value = value

    def __repr__(self) -> str:
        return f"Plaintext(<redacted>, {len(self._value)} bytes)"

    __str__ = __repr__


ENC = re.compile(
    r"ENC\[AES256_GCM,data:(?P<data>[^,]*),iv:[^,]*,tag:[^,]*,type:(?P<type>\w+)\]"
)
DOTENV_LINE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*=")
DOTENV_PAIR = re.compile(r"(?P<key>[A-Z_][A-Z0-9_]*)=(?P<value>.*[^=].*)")
HEX = re.compile(r"[0-9a-fA-F]+")
BASE64 = re.compile(r"[A-Za-z0-9+/]+={0,2}")


def _fail(message: str) -> NoReturn:
    raise Exit(message)


@cache
def _flake() -> Flake:
    return Flake(str(ROOT))


def _key(ref: SecretRef) -> str | None:
    return ref.key if isinstance(ref, SopsFile) else None


def _path(ref: SecretRef) -> Path:
    if isinstance(ref, SopsFile):
        path = ref.path / "secret" if ref.path.is_dir() else ref.path
    else:
        try:
            var = get_machine_var(Machine(ref.machine, _flake()), ref.var)
        except ClanError as error:
            _fail(str(error))
        if not var.secret:
            _fail(f"{ref.var} is public; `clan vars list {ref.machine}` prints it")
        if var._store is None or var._generator is None:
            _fail(f"{ref.var} has no store")
        path = var._store.directory(var._generator.key, var.name) / "secret"
    if not path.is_file():
        _fail(f"{path} does not exist")
    return path


def _format(path: Path) -> str:
    return {".yaml": "yaml", ".yml": "yaml", ".env": "dotenv"}.get(path.suffix, "json")


def _encrypted(path: Path) -> dict[str, Any]:
    fmt = _format(path)
    try:
        text = path.read_text()
    except UnicodeDecodeError:
        text = ""
    if fmt == "dotenv":
        return {
            key: value
            for line in text.splitlines()
            if DOTENV_LINE.match(line) and not line.startswith("sops_")
            for key, _, value in [line.partition("=")]
        }
    try:
        document = yaml.safe_load(text) if fmt == "yaml" else json.loads(text)
    except (yaml.YAMLError, ValueError):
        document = None
    if not isinstance(document, dict) or "sops" not in document:
        _fail(f"{path} is not a sops file")
    return {str(key): value for key, value in document.items() if key != "sops"}


def _is_blob(path: Path, document: dict[str, Any]) -> bool:
    return _format(path) == "json" and set(document) == {"data"}


def _decrypted(path: Path, raw: bytes) -> dict[str, Any]:
    fmt = _format(path)
    try:
        if fmt == "dotenv":
            document = {
                key: value.replace("\\n", "\n")
                for key, _, value in (
                    line.partition("=") for line in raw.decode().split("\n")
                )
                if key and not key.startswith("#")
            }
        else:
            document = yaml.safe_load(raw) if fmt == "yaml" else json.loads(raw)
    except (yaml.YAMLError, ValueError):
        document = None
    if not isinstance(document, dict):
        _fail(f"{path} did not decrypt to {fmt}")
    return document


def _leaves(node: Any, prefix: str = "") -> list[tuple[str, Any]]:
    items: list[tuple[Any, Any]]
    if isinstance(node, dict):
        items = list(node.items())
    elif isinstance(node, list):
        items = list(enumerate(node))
    else:
        return [(prefix, node)]
    return [
        leaf
        for key, value in items
        for leaf in _leaves(value, f"{prefix}.{key}" if prefix else str(key))
    ]


def _leaf(leaves: list[tuple[str, Any]], key: str) -> Any:
    for name, value in leaves:
        if name == key:
            return value
    _fail(f"no leaf {key}")


def _ciphertext(name: str, value: Any) -> Field:
    match = ENC.fullmatch(value) if isinstance(value, str) else None
    if match is None:
        return Field(name, None, "unencrypted")
    return Field(name, len(base64.b64decode(match["data"])), match["type"])


def _kind(text: str) -> str:
    if text.startswith("-----BEGIN "):
        return "pem"
    if "\n" in text:
        return "multiline"
    if not text.isprintable():
        return "binary"
    if HEX.fullmatch(text):
        return "hex"
    if len(text) % 4 == 0 and BASE64.fullmatch(text) and re.search(r"[+/=]", text):
        return "base64"
    return "printable"


def _plain(name: str, value: Any) -> Field:
    if isinstance(value, bool):
        return Field(name, len(str(value).lower()), "bool")
    if isinstance(value, int | float):
        return Field(name, len(str(value)), type(value).__name__)
    if value is None:
        return Field(name, 0, "null")
    return Field(name, len(str(value).encode()), _kind(str(value)))


def _opaque(content: bytes) -> list[Field]:
    try:
        text = content.decode()
    except UnicodeDecodeError:
        return [
            Field("format", None, "binary"),
            Field("bytes", len(content), None),
            Field("kind", None, "binary"),
        ]
    lines = text.splitlines()
    entries = [line for line in lines if line and not line.startswith("#")]
    pairs = [pair for line in entries if (pair := DOTENV_PAIR.fullmatch(line))]
    if lines and len(pairs) == len(entries):
        return [Field("format", None, "dotenv")] + [
            _plain(pair["key"], pair["value"]) for pair in pairs
        ]
    try:
        document = json.loads(text)
    except ValueError:
        document = None
    if isinstance(document, dict):
        return [Field("format", None, "json")] + [
            _plain(key, value) for key, value in _leaves(document)
        ]
    return [
        Field("format", None, "binary"),
        Field("bytes", len(content), None),
        Field("lines", len(lines), None),
        Field("kind", None, _kind(text.removesuffix("\n"))),
    ]


def inspect(ref: SecretRef) -> list[Field]:
    path = _path(ref)
    document = _encrypted(path)
    key = _key(ref)
    if key is not None:
        return [_ciphertext(key, _leaf(_leaves(document), key))]
    if _is_blob(path, document):
        length = _ciphertext("data", document["data"]).length
        return [Field("format", None, "binary"), Field("bytes", length, None)]
    return [Field("format", None, _format(path))] + [
        _ciphertext(name, value) for name, value in _leaves(document)
    ]


def inspect_decrypted(ref: SecretRef) -> list[Field]:
    secret = reveal(ref)
    key = _key(ref)
    if key is not None:
        return [_plain(key, secret._value.decode())]
    path = _path(ref)
    if _is_blob(path, _encrypted(path)):
        fields = _opaque(secret._value)
        if fields[0].name == "format":
            return fields
        return [Field("format", None, "binary"), *fields]
    return [Field("format", None, _format(path))] + [
        _plain(name, value) for name, value in _leaves(_decrypted(path, secret._value))
    ]


def reveal(ref: SecretRef) -> Plaintext:
    path = _path(ref)
    key = _key(ref)
    if key is not None:
        _leaf(_leaves(_encrypted(path)), key)
    try:
        raw = decrypt_file_raw(path, load_age_plugins(_flake()))
    except ClanCmdError as error:
        reason = error.cmd.stderr.strip().splitlines()[-1:]
        _fail(f"sops could not decrypt {path}: {' '.join(reason)}")
    except ClanError as error:
        _fail(str(error))
    if key is None:
        return Plaintext(raw)
    value = _leaf(_leaves(_decrypted(path, raw)), key)
    if isinstance(value, bool):
        value = str(value).lower()
    return Plaintext(b"" if value is None else str(value).encode())


def send_stdin(secret: Plaintext, remote: Remote, cmd: list[str]) -> None:
    raise NotImplementedError


@dataclass(frozen=True)
class InitrdUnlock:
    key: ClanVar
    address: str
    port: int = 2222
    jump: str = "root@malt.x"


UNLOCK: dict[str, InitrdUnlock] = {
    "citra": InitrdUnlock(key=ClanVar("citra", "zfs/key"), address="192.168.35.114"),
}


@task
def inspect_secret(
    _: Context, target: str, var: str = "", decrypt: bool = False
) -> None:
    """Print key names, lengths and kinds of a secret, never its value."""
    ref = ClanVar(target, var) if var else SopsFile(Path(target))
    for field in inspect_decrypted(ref) if decrypt else inspect(ref):
        print(field.row())


@task
def unlock(_: Context, machine: str) -> None:
    """Hand a machine's disk passphrase to its initrd over ssh."""
    raise NotImplementedError


@task
def reboot(_: Context, machine: str, timeout: int = 600) -> None:
    """Reboot a machine, unlock its initrd if it has one, and wait until it is back."""
    raise NotImplementedError
