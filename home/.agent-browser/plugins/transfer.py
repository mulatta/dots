#!/usr/bin/env python3
"""Bounded staging transfers through RustFS."""

import hashlib
import json
import os
import re
import select
import signal
import stat
import subprocess
import sys
import tempfile
import time
import uuid
import xml.etree.ElementTree as ET
from collections.abc import Iterator
from contextlib import contextmanager
from typing import Any
from urllib.parse import quote, urlencode

from rbw import credential

PROTOCOL = "agent-browser.plugin.v1"
LIMIT = 65536
FILE_LIMIT = 1024 * 1024 * 1024
LIST_LIMIT = 4096
CHUNK = 32768
OPERATIONS = {"transfer.list", "transfer.pull", "transfer.push"}
S3_URL = "https://s3.mulatta.io"
VAULT_ITEM = "neko-rustfs-client"


class VaultUnavailable(ValueError):
    pass


def name_value(value: Any) -> str:
    if (
        not isinstance(value, str)
        or not value
        or value in {".", ".."}
        or "/" in value
        or any(ord(c) < 32 or 127 <= ord(c) < 160 for c in value)
        or len(value.encode("utf-8")) > 255
    ):
        raise ValueError("invalid_name")
    return value


def absolute(value: Any) -> str:
    if not isinstance(value, str) or not value.startswith("/") or "\0" in value:
        raise ValueError("absolute_path_required")
    if any(part in {".", ".."} for part in value.split("/")):
        raise ValueError("invalid_path")
    return value


def regular(mode: int) -> None:
    if not stat.S_ISREG(mode):
        raise ValueError("regular_file_required")


@contextmanager
def directory(path: str) -> Iterator[int]:
    # Walk every component: O_NOFOLLOW on only the final path is insufficient.
    parts = absolute(path).split("/")
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_NONBLOCK
    fd = os.open("/", flags)
    try:
        for part in filter(None, parts):
            child = os.open(part, flags, dir_fd=fd)
            os.close(fd)
            fd = child
        yield fd
    finally:
        os.close(fd)


@contextmanager
def source_file(path: str) -> Iterator[int]:
    parent, name = os.path.split(absolute(path))
    name_value(name)
    with directory(parent) as parent_fd:
        fd = os.open(
            name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent_fd
        )
        try:
            info = os.fstat(fd)
            regular(info.st_mode)
            if info.st_size > FILE_LIMIT:
                raise ValueError("file_too_large")
            yield fd
        finally:
            os.close(fd)


@contextmanager
def destination_file(path: str, mode: int) -> Iterator[int]:
    parent, name = os.path.split(absolute(path))
    name_value(name)
    with directory(parent) as parent_fd:
        temporary = ".transfer-" + uuid.uuid4().hex
        fd = os.open(
            temporary,
            os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_NONBLOCK,
            mode,
            dir_fd=parent_fd,
        )
        try:
            regular(os.fstat(fd).st_mode)
            os.fchmod(fd, mode)
            yield fd
            os.fsync(fd)
            # link() publishes atomically and cannot replace an existing name.
            os.link(
                temporary,
                name,
                src_dir_fd=parent_fd,
                dst_dir_fd=parent_fd,
                follow_symlinks=False,
            )
        finally:
            os.close(fd)
            os.unlink(temporary, dir_fd=parent_fd)


def write_file(fd: int, data: bytes) -> None:
    while data:
        count = os.write(fd, data)
        if not count:
            raise OSError("short_write")
        data = data[count:]


def snapshot(fd: int) -> tuple[int, int, int]:
    info = os.fstat(fd)
    return info.st_size, info.st_mtime_ns, info.st_ctime_ns


def copy_file(source: int, destination: int) -> dict[str, Any]:
    before = snapshot(source)
    digest = hashlib.sha256()
    total = 0
    while data := os.read(source, CHUNK):
        total += len(data)
        if total > FILE_LIMIT:
            raise ValueError("file_too_large")
        write_file(destination, data)
        digest.update(data)
    if total != before[0] or snapshot(source) != before:
        raise ValueError("source_changed")
    return {"bytes": total, "sha256": digest.hexdigest()}


class S3:
    def __init__(self) -> None:
        try:
            subprocess.run(
                ["rbw", "unlocked"], capture_output=True, timeout=3, check=True
            )
            response = subprocess.run(
                ["rbw", "get", "--raw", "--", VAULT_ITEM],
                capture_output=True,
                timeout=8,
                check=True,
            )
            entry = json.loads(response.stdout)
            if not isinstance(entry, dict):
                raise TypeError("invalid_vault_item")
            login = credential(entry, S3_URL)
            if not re.fullmatch(r"[A-Za-z0-9_-]+", login["username"]):
                raise ValueError("invalid_access_key")
            if not re.fullmatch(r"[A-Za-z0-9+/=_-]+", login["password"]):
                raise ValueError("invalid_secret_key")
            self.auth = (
                "user = "
                + json.dumps(login["username"] + ":" + login["password"])
                + "\n"
            )
        except (OSError, ValueError, TypeError, subprocess.SubprocessError) as exc:
            raise VaultUnavailable() from exc

    def request(self, url: str, output: Any, upload: str | None = None) -> None:
        args = [
            "curl",
            "-q",
            "--silent",
            "--fail",
            "--max-time",
            "44",
            "--max-filesize",
            str(FILE_LIMIT),
            "--aws-sigv4",
            "aws:amz:us-east-1:s3",
            "--config",
            "-",
        ]
        if upload is not None:
            args += ["--header", "If-None-Match: *", "--upload-file", upload]
        subprocess.run(
            [*args, url],
            input=self.auth.encode(),
            stdout=output,
            stderr=subprocess.DEVNULL,
            check=True,
        )

    def listing(self, area: str) -> list[dict[str, Any]]:
        if area != "downloads":
            raise ValueError("s3_client_lists_downloads_only")
        query = {"list-type": "2", "prefix": "downloads/", "max-keys": "1000"}
        files: list[dict[str, Any]] = []
        while True:
            with tempfile.TemporaryFile() as output:
                self.request(f"{S3_URL}/neko-transfer?{urlencode(query)}", output)
                output.seek(0)
                page = ET.fromstring(output.read(2 * 1024 * 1024))
            for obj in page.findall("{*}Contents"):
                key = obj.findtext("{*}Key", "")
                if not key.startswith("downloads/"):
                    raise ValueError("invalid_object_key")
                try:
                    name = name_value(key.removeprefix("downloads/"))
                except ValueError:
                    continue
                files.append(
                    {
                        "name": name,
                        "size": int(obj.findtext("{*}Size", "")),
                        "modified": obj.findtext("{*}LastModified"),
                    }
                )
                if len(files) > LIST_LIMIT:
                    raise ValueError("listing_too_large")
            if page.findtext("{*}IsTruncated") != "true":
                return files
            token = page.findtext("{*}NextContinuationToken")
            if not token or token == query.get("continuation-token"):
                raise ValueError("invalid_continuation_token")
            query["continuation-token"] = token

    def pull(self, name: str, path: str) -> dict[str, Any]:
        with tempfile.TemporaryFile() as data, destination_file(path, 0o600) as target:
            self.request(
                f"{S3_URL}/neko-transfer/downloads/{quote(name, safe='')}", data
            )
            data.seek(0)
            return copy_file(data.fileno(), target)

    def push(self, path: str, name: str) -> dict[str, Any]:
        if name.startswith(".") or name.endswith((".partial", ".crdownload")):
            raise ValueError("reserved_staging_name")
        with source_file(path) as source, tempfile.NamedTemporaryFile() as data:
            result = copy_file(source, data.fileno())
            self.request(
                f"{S3_URL}/neko-transfer/uploads/{quote(name, safe='')}",
                subprocess.DEVNULL,
                data.name,
            )
        return {"browserPathReady": False, **result}


def handle(message: Any) -> dict[str, Any]:
    if not isinstance(message, dict) or message.get("protocol") != PROTOCOL:
        raise ValueError("invalid_protocol")
    operation = message.get("type")
    if operation == "plugin.manifest":
        return {
            "manifest": {
                "name": "transfer",
                "capabilities": ["command.run"],
                "description": "Transfer browser staging files",
            }
        }
    if (
        not isinstance(operation, str)
        or operation not in OPERATIONS
        or message.get("capability") != "command.run"
    ):
        raise ValueError("unsupported_request")
    request = message.get("request")
    if not isinstance(request, dict):
        raise TypeError("invalid_request")
    if operation == "transfer.list":
        return {"data": {"files": S3().listing(request.get("area"))}}
    if operation == "transfer.pull":
        name = name_value(request.get("name"))
        path = absolute(request.get("output"))
        return {"data": {"output": path, **S3().pull(name, path)}}
    path = absolute(request.get("input"))
    name = name_value(request.get("name", os.path.basename(path)))
    return {
        "data": {
            "browserPath": "/home/neko/staging/uploads/" + name,
            **S3().push(path, name),
        }
    }


def timeout_handler(signum: int, frame: Any) -> None:
    raise TimeoutError("transfer_deadline")


def main() -> None:
    start = time.monotonic()
    signal.signal(signal.SIGALRM, timeout_handler)
    # Leave cleanup and JSON serialization room inside the caller's 60 seconds.
    signal.setitimer(signal.ITIMER_REAL, 48)
    try:
        raw = sys.stdin.buffer.read(LIMIT + 1)
        if len(raw) > LIMIT:
            raise ValueError("request_too_large")
        body = {"success": True, **handle(json.loads(raw))}
    except VaultUnavailable:
        body = {
            "success": False,
            "error": "Unlock rbw and check the neko-rustfs-client item",
        }
    except (
        ValueError,
        TypeError,
        OSError,
        subprocess.SubprocessError,
        RecursionError,
        ET.ParseError,
    ):
        body = {
            "success": False,
            "error": "Transfer failed; check request, paths and transport access",
        }
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
    # Bound stdout too: a parent that stops draining must not keep us alive.
    output = (json.dumps({"protocol": PROTOCOL, **body}) + "\n").encode("utf-8")
    fd = sys.stdout.fileno()
    os.set_blocking(fd, False)
    while output:
        remaining = start + 50 - time.monotonic()
        if remaining <= 0 or not select.select([], [fd], [], remaining)[1]:
            return
        try:
            written = os.write(fd, output)
        except (BrokenPipeError, BlockingIOError):
            return
        if not written:
            return
        output = output[written:]


if __name__ == "__main__":
    main()
