#!/usr/bin/env python3
"""Start ksecretd with the KWallet password unsealed from the TPM.

Emulates pam_kwallet: ksecretd is exec'd with PAM_KWALLET5_LOGIN set and
`--pam-login <pipefd> <sockfd>`, reads the PBKDF2 hash from the pipe and env
vars from one connection on the listening socket before registering on D-Bus.
"""

from __future__ import annotations

import hashlib
import os
import socket
import subprocess
import sys
from pathlib import Path

# Matches kwalletbackend.cc
ITERATIONS = 50000
KEY_SIZE = 56
HASH_ALGO = "sha512"

SALT_PATH = Path.home() / ".local/share/kwalletd/kdewallet.salt"

FORWARDED_ENV = ("DISPLAY", "WAYLAND_DISPLAY", "XDG_RUNTIME_DIR")


def load_salt(salt_path: Path = SALT_PATH) -> bytes:
    data = salt_path.read_bytes()
    if len(data) != KEY_SIZE:
        print(
            f"WARNING: expected salt length {KEY_SIZE}, got {len(data)}",
            file=sys.stderr,
        )
    return data


def decrypt_password(cred_file: Path) -> bytes:
    result = subprocess.run(
        ["systemd-creds", "decrypt", "--user", str(cred_file), "-"],
        stdout=subprocess.PIPE,
        check=True,
    )
    return result.stdout.strip()


def derive_hash(password: bytes, salt: bytes) -> bytes:
    return hashlib.pbkdf2_hmac(HASH_ALGO, password, salt, ITERATIONS, KEY_SIZE)


def exec_ksecretd(ksecretd: str, password_hash: bytes) -> None:
    # Hash and env connection are queued in the kernel before exec, so no
    # helper process is needed.
    hash_r, hash_w = os.pipe()
    os.set_inheritable(hash_r, True)  # noqa: FBT003
    os.write(hash_w, password_hash)
    os.close(hash_w)

    # A path in the 0700 runtime dir, not an abstract name, so no other user
    # can queue a connection (and its env) ahead of ours.
    addr = (
        Path(os.environ["XDG_RUNTIME_DIR"]) / f"kwallet-tpm-unlock-{os.getpid()}.sock"
    )
    addr.unlink(missing_ok=True)
    listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    listener.bind(str(addr))
    listener.listen(1)
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.connect(str(addr))
            for key in FORWARDED_ENV:
                if (val := os.environ.get(key)) is not None:
                    client.sendall(f"{key}={val}\n".encode())
    finally:
        addr.unlink()

    sock_fd = listener.detach()
    os.set_inheritable(sock_fd, True)  # noqa: FBT003
    os.environ["PAM_KWALLET5_LOGIN"] = "1"
    os.execv(  # noqa: S606
        ksecretd,
        [ksecretd, "--pam-login", str(hash_r), str(sock_fd)],
    )


def main() -> None:
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <ksecretd> <credential-file>", file=sys.stderr)
        sys.exit(1)

    ksecretd = sys.argv[1]
    cred_file = Path(sys.argv[2])

    password_hash = derive_hash(decrypt_password(cred_file), load_salt())
    exec_ksecretd(ksecretd, password_hash)


if __name__ == "__main__":
    main()
