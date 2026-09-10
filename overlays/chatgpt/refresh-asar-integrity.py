#!/usr/bin/env python3
"""Refresh integrity hashes after patching ChatGPT's ASAR archive."""

import hashlib
import json
import plistlib
import struct
import sys
from pathlib import Path


def refresh_asar_integrity(data: bytes) -> tuple[bytes, str]:
    """Refresh per-file hashes and return data plus the ASAR header hash."""
    header_pickle_size = struct.unpack_from("<I", data, 4)[0]
    header_size = struct.unpack_from("<I", data, 12)[0]
    header_start = 16
    content_start = 8 + header_pickle_size
    header = json.loads(data[header_start : header_start + header_size])

    def refresh_files(files: dict[str, dict[str, object]]) -> None:
        for entry in files.values():
            nested = entry.get("files")
            if isinstance(nested, dict):
                refresh_files(nested)
                continue

            integrity = entry.get("integrity")
            offset = entry.get("offset")
            size = entry.get("size")
            if (
                not isinstance(integrity, dict)
                or offset is None
                or not isinstance(size, int)
            ):
                continue

            start = content_start + int(str(offset))
            content = data[start : start + size]
            block_size = integrity.get("blockSize")
            if not isinstance(block_size, int):
                sys.exit("invalid ASAR integrity block size")
            integrity["hash"] = hashlib.sha256(content).hexdigest()
            blocks = [
                hashlib.sha256(content[index : index + block_size]).hexdigest()
                for index in range(0, len(content), block_size)
            ]
            integrity["blocks"] = blocks or [hashlib.sha256(b"").hexdigest()]

    files = header.get("files")
    if not isinstance(files, dict):
        sys.exit("invalid ASAR header")
    refresh_files(files)

    encoded_header = json.dumps(header, separators=(",", ":")).encode()
    if len(encoded_header) != header_size:
        sys.exit(
            f"ASAR header size changed: expected {header_size}, got {len(encoded_header)}"
        )
    updated = data[:header_start] + encoded_header + data[header_start + header_size :]
    return updated, hashlib.sha256(encoded_header).hexdigest()


def main() -> None:
    """Refresh app.asar and its matching Electron Info.plist entry."""
    asar = Path(sys.argv[1])
    data, header_hash = refresh_asar_integrity(asar.read_bytes())
    asar.write_bytes(data)

    info_plist = asar.parent.parent / "Info.plist"
    raw_plist = info_plist.read_bytes()
    plist = plistlib.loads(raw_plist)
    plist["ElectronAsarIntegrity"]["Resources/app.asar"]["hash"] = header_hash
    fmt = plistlib.FMT_BINARY if raw_plist.startswith(b"bplist") else plistlib.FMT_XML
    info_plist.write_bytes(plistlib.dumps(plist, fmt=fmt, sort_keys=False))


if __name__ == "__main__":
    main()
