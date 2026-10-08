"""Print a NIP-OA owner attestation tag for an agent key.

Reads the owner secret (nsec or hex) from stdin so it never appears in argv.
Mirrors buzz_sdk::nip_oa::compute_auth_tag.
"""

import hashlib
import json
import sys

from coincurve import PrivateKey, PublicKeyXOnly

BECH32_CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"


def _polymod(values: list[int]) -> int:
    generators = [0x3B6A57B2, 0x26508E6D, 0x1EA119FA, 0x3D4233DD, 0x2A1462B3]
    chk = 1
    for v in values:
        top = chk >> 25
        chk = (chk & 0x1FFFFFF) << 5 ^ v
        for i, g in enumerate(generators):
            if (top >> i) & 1:
                chk ^= g
    return chk


def decode_nsec(value: str) -> bytes:
    hrp, sep, data = value.lower().rpartition("1")
    if not sep or hrp != "nsec":
        raise ValueError("expected an nsec1 key")
    values = [BECH32_CHARSET.index(c) for c in data]
    hrp_expanded = [ord(c) >> 5 for c in hrp] + [0] + [ord(c) & 31 for c in hrp]
    if _polymod(hrp_expanded + values) != 1:
        raise ValueError("nsec checksum mismatch")
    acc, bits, out = 0, 0, bytearray()
    for v in values[:-6]:
        acc = (acc << 5) | v
        bits += 5
        while bits >= 8:
            bits -= 8
            out.append((acc >> bits) & 0xFF)
    if len(out) != 32:
        raise ValueError("nsec does not decode to 32 bytes")
    return bytes(out)


def parse_secret(value: str) -> bytes:
    value = value.strip()
    if value.lower().startswith("nsec1"):
        return decode_nsec(value)
    secret = bytes.fromhex(value)
    if len(secret) != 32:
        raise ValueError("hex secret must be 32 bytes")
    return secret


def main() -> int:
    if len(sys.argv) not in (3, 4):
        print(
            "usage: nip-oa-tag.py <agent-pubkey-hex> <owner-pubkey-hex> [conditions] < secret",
            file=sys.stderr,
        )
        return 2
    agent_hex, expected_owner_hex = sys.argv[1].lower(), sys.argv[2].lower()
    conditions = sys.argv[3] if len(sys.argv) == 4 else ""

    key = PrivateKey(parse_secret(sys.stdin.read()))
    owner_hex = key.public_key_xonly.format().hex()
    # The relay keeps the first owner it sees, so a wrong identity is permanent.
    if owner_hex != expected_owner_hex:
        print(f"owner key mismatch: secret belongs to {owner_hex}", file=sys.stderr)
        return 1
    if owner_hex == agent_hex:
        print("owner and agent keys must differ", file=sys.stderr)
        return 1

    message = hashlib.sha256(
        f"nostr:agent-auth:{agent_hex}:{conditions}".encode()
    ).digest()
    sig = key.sign_schnorr(message)
    if not PublicKeyXOnly(bytes.fromhex(owner_hex)).verify(sig, message):
        print("signature self-check failed", file=sys.stderr)
        return 1

    sys.stdout.write(
        json.dumps(["auth", owner_hex, conditions, sig.hex()], separators=(",", ":"))
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
