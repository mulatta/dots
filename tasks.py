import base64
import json
import logging
import re
import tempfile
import time
from collections.abc import Callable, Generator
from contextlib import ExitStack, contextmanager
from dataclasses import dataclass
from functools import cache
from pathlib import Path
from typing import Any, NoReturn, final

import yaml
from clan_cli.secrets.sops import decrypt_file_raw, load_age_plugins
from clan_lib.cmd import Log, RunOpts
from clan_lib.custom_logger import setup_logging
from clan_lib.errors import ClanCmdError, ClanError, CmdOut
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
    remote.run(
        cmd,
        RunOpts(input=secret._value, sensitive_input=True, log=Log.NONE),
        control_master=False,
    )


@dataclass(frozen=True)
class InitrdUnlock:
    key: ClanVar
    address: str
    port: int = 2222
    jump: str = "root@malt.x"
    host_key: str = "initrd-ssh/id_ed25519.pub"


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


AGENT = "systemd-tty-ask-password-agent"
PROBE = {"BatchMode": "yes", "ConnectTimeout": "5"}
PROBE_SECONDS = 15
POLL_SECONDS = 2


@contextmanager
def _initrd(machine: str, entry: InitrdUnlock) -> Generator[Remote]:
    try:
        var = get_machine_var(Machine(machine, _flake()), entry.host_key)
        public = b"" if var.secret else var.value
    except (ClanError, ValueError) as error:
        _fail(f"cannot pin the initrd host key of {machine}: {error}")
    fields = public.decode(errors="replace").split()
    if len(fields) < 2 or not fields[0].startswith("ssh-"):
        _fail(f"{entry.host_key} of {machine} is not a public ssh host key")
    with tempfile.TemporaryDirectory(prefix="initrd-") as tmp:
        known_hosts = Path(tmp) / "known_hosts"
        known_hosts.write_text(
            f"[{entry.address}]:{entry.port} {' '.join(fields[:2])}\n"
        )
        yield Remote(
            address=entry.address,
            port=entry.port,
            host_key_check="strict",
            ssh_options={
                **PROBE,
                "UserKnownHostsFile": str(known_hosts),
                "GlobalKnownHostsFile": "/dev/null",
                "ProxyJump": entry.jump,
                "ControlPath": "none",
            },
        )


def _ssh(remote: Remote, cmd: list[str]) -> CmdOut | None:
    try:
        out = remote.run(
            cmd,
            RunOpts(check=False, log=Log.NONE, timeout=PROBE_SECONDS),
            quiet=True,
            control_master=False,
        )
    except ClanCmdError:
        return None
    if "Host key verification failed." in out.stderr:
        _fail(f"{remote.target}: host key verification failed")
    return out


def _answer(remote: Remote, cmd: list[str]) -> str | None:
    out = _ssh(remote, cmd)
    return out.stdout if out is not None and out.returncode == 0 else None


def _asks(initrd: Remote) -> str | None:
    return "" if _answer(initrd, [AGENT, "--list"]) else None


def _booted(target: Remote) -> str | None:
    out = _answer(target, ["readlink", "/run/booted-system"])
    return None if out is None else out.strip()


def _send_key(machine: str, entry: InitrdUnlock, initrd: Remote) -> str:
    try:
        send_stdin(reveal(entry.key), initrd, [AGENT])
    except ClanCmdError as error:
        reason = error.cmd.stderr.strip().splitlines()[-1:]
        _fail(f"{AGENT} on {machine} failed: {' '.join(reason)}")
    return ""


@dataclass(frozen=True)
class Step:
    name: str
    done: Callable[[], str | None]


def _run_steps(machine: str, steps: list[Step], timeout: int) -> None:
    deadline = time.monotonic() + timeout
    for step in steps:
        while (detail := step.done()) is None:
            if time.monotonic() >= deadline:
                _fail(f"{machine}: timed out after {timeout}s waiting for {step.name}")
            time.sleep(POLL_SECONDS)
        print(f"{machine}: {step.name} {detail}".rstrip(), flush=True)


def _request_reboot(target: Remote) -> str:
    out = _ssh(target, ["systemctl", "reboot"])
    if out is not None and out.returncode not in (0, 255):
        _fail(f"systemctl reboot failed: {out.stderr.strip()}")
    return ""


@task
def unlock(_: Context, machine: str) -> None:
    """Hand a machine's disk passphrase to its initrd over ssh."""
    entry = UNLOCK.get(machine)
    if entry is None:
        _fail(f"{machine} has no initrd unlock; known: {', '.join(UNLOCK)}")
    with _initrd(machine, entry) as initrd:
        if _asks(initrd) is None:
            _fail(
                f"{machine}: no initrd at {entry.address}:{entry.port} asks for a key"
            )
        _send_key(machine, entry, initrd)
    print(f"{machine}: unlock")


def _reachable(machine: str, action: str) -> Remote:
    try:
        target = Machine(machine, _flake()).target_host()
    except ClanError as error:
        _fail(str(error))
    target = target.override(ssh_options={**target.ssh_options, **PROBE})
    if _booted(target) is None:
        _fail(f"{machine} does not answer at {target.target}; nothing was {action}")
    return target


@task
def reboot(_: Context, machine: str, timeout: int = 600) -> None:
    """Reboot a machine, unlock its initrd if it has one, and wait until it is back."""
    target = _reachable(machine, "rebooted")
    entry = UNLOCK.get(machine)
    with ExitStack() as stack:
        steps = [
            Step("reboot", lambda: _request_reboot(target)),
            Step("down", lambda: "" if _answer(target, ["true"]) is None else None),
        ]
        if entry is not None:
            initrd = stack.enter_context(_initrd(machine, entry))
            steps += [
                Step("initrd", lambda: _asks(initrd)),
                Step("unlock", lambda: _send_key(machine, entry, initrd)),
            ]
        steps.append(Step("up", lambda: _booted(target)))
        _run_steps(machine, steps, timeout)


PROFILE = "/nix/var/nix/profiles/system"
GENERATION = re.compile(
    r"\s*(?P<number>\d+)\s+(?P<date>\S+)\s+(?P<time>\S+)\s*(?P<current>\(current\))?\s*"
)
KERNEL = re.compile(r"linux-(?P<version>[\w.-]+?)/")


@dataclass(frozen=True)
class Generation:
    number: int
    created: str
    kernel: str
    current: bool


def _nixos(machine: str, action: str) -> Remote:
    target = _reachable(machine, action)
    if (
        _answer(target, ["test", "-x", f"{PROFILE}/bin/switch-to-configuration"])
        is None
    ):
        _fail(f"{machine} is not NixOS; nix-darwin rolls back with darwin-rebuild")
    return target


def _generations(machine: str, target: Remote) -> list[Generation]:
    listed = _answer(target, ["nix-env", "-p", PROFILE, "--list-generations"])
    kernels = _answer(
        target,
        [
            "sh",
            "-c",
            f'for l in {PROFILE}-*-link; do echo "$l $(readlink "$l/kernel")"; done',
        ],
    )
    if listed is None or kernels is None:
        _fail(f"{machine}: cannot list its system generations")
    kernel = {
        line.split()[0]: match["version"]
        for line in kernels.splitlines()
        if (match := KERNEL.search(line))
    }
    generations = [
        Generation(
            number=int(match["number"]),
            created=f"{match['date']} {match['time'][:5]}",
            kernel=kernel.get(f"{PROFILE}-{match['number']}-link", "?"),
            current=bool(match["current"]),
        )
        for match in map(GENERATION.fullmatch, listed.splitlines())
        if match is not None
    ]
    if not any(g.current for g in generations):
        _fail(f"{machine}: no system generation is marked current")
    return generations


def _diff(machine: str, target: Remote, current: int, goal: int) -> None:
    target.run(
        [
            "nix",
            "store",
            "diff-closures",
            f"{PROFILE}-{current}-link",
            f"{PROFILE}-{goal}-link",
        ],
        RunOpts(check=False, log=Log.BOTH, prefix=machine),
        control_master=False,
    )


@task
def generations(_: Context, machine: str, diff: int = 0) -> None:
    """List a NixOS machine's system generations, or diff the current one with --diff."""
    # clan_lib streams the remote output through logging, which invoke leaves unset.
    setup_logging(logging.INFO)
    target = _nixos(machine, "listed")
    listed = _generations(machine, target)
    current = next(g for g in listed if g.current)
    if not diff:
        for g in listed:
            mark = "current" if g.current else ""
            print(f"{g.number}\t{g.created}\t{g.kernel}\t{mark}".rstrip())
        return
    if diff not in {g.number for g in listed}:
        _fail(f"{machine}: no generation {diff}")
    _diff(machine, target, current.number, diff)


@task
def rollback(_: Context, machine: str, to: int = 0) -> None:
    """Switch a NixOS machine to its previous system generation, or to --to."""
    setup_logging(logging.INFO)
    target = _nixos(machine, "rolled back")
    listed = _generations(machine, target)
    current = next(g for g in listed if g.current)
    numbers = [g.number for g in listed]
    goal = to or max((n for n in numbers if n < current.number), default=0)
    if goal == current.number or goal not in numbers:
        known = ", ".join(map(str, numbers))
        _fail(
            f"{machine}: cannot switch from {current.number} to {goal or '-'}; has {known}"
        )
    print(f"{machine}: generation {current.number} -> {goal}", flush=True)
    _diff(machine, target, current.number, goal)
    target.run(
        ["nix-env", "-p", PROFILE, "--switch-generation", str(goal)],
        RunOpts(log=Log.BOTH, prefix=machine),
        control_master=False,
    )
    # systemd-run keeps the switch going if ssh drops, as clan machines update does.
    switch = [
        "systemd-run",
        "--pipe",
        "--wait",
        "--quiet",
        "--collect",
        "--no-ask-password",
        "--service-type=exec",
        f"--unit=inv-rollback-{goal}-{int(time.time())}",
        "-E",
        "LOCALE_ARCHIVE",
        "--",
        f"{PROFILE}/bin/switch-to-configuration",
        "switch",
    ]
    try:
        target.run(switch, RunOpts(log=Log.BOTH, prefix=machine), control_master=False)
    except ClanCmdError:
        _fail(
            f"{machine}: the profile is at {goal} but switching to it failed; "
            f"`inv rollback {machine} --to {current.number}` returns"
        )
    failed = (
        _answer(target, ["systemctl", "--failed", "--no-legend", "--plain"]) or ""
    ).split("\n")
    units = [line.split()[0] for line in failed if line.strip()]
    print(f"{machine}: running {goal}, failed units: {', '.join(units) or 'none'}")
    goal_kernel = next(g.kernel for g in listed if g.number == goal)
    if goal_kernel != current.kernel:
        print(
            f"{machine}: kernel {current.kernel} -> {goal_kernel} takes effect after a reboot"
        )
