import os
from dataclasses import dataclass
from pathlib import Path
from typing import final

from clan_lib.ssh.remote import Remote
from invoke.context import Context
from invoke.tasks import task

ROOT = Path(__file__).parent.resolve()
os.chdir(ROOT)


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
    length: int
    kind: str


@final
class Plaintext:
    __slots__ = ("_value",)

    def __init__(self, value: bytes) -> None:
        self._value = value

    def __repr__(self) -> str:
        return f"Plaintext(<redacted>, {len(self._value)} bytes)"

    __str__ = __repr__


def inspect(ref: SecretRef) -> list[Field]:
    raise NotImplementedError


def inspect_decrypted(ref: SecretRef) -> list[Field]:
    raise NotImplementedError


def reveal(ref: SecretRef) -> Plaintext:
    raise NotImplementedError


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
    raise NotImplementedError


@task
def unlock(_: Context, machine: str) -> None:
    """Hand a machine's disk passphrase to its initrd over ssh."""
    raise NotImplementedError


@task
def reboot(_: Context, machine: str, timeout: int = 600) -> None:
    """Reboot a machine, unlock its initrd if it has one, and wait until it is back."""
    raise NotImplementedError
