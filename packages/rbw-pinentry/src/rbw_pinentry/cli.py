import argparse
import sys

from .pinentry import Pinentry, keyring, setup_logging


def build_parser() -> argparse.ArgumentParser:
    description = (
        "rbw pinentry that caches the master password in the OS secret store "
        "(macOS Keychain, Linux Secret Service)."
    )
    epilog = (
        "Setup:\n"
        "  rbw config set pinentry rbw-pinentry\n\n"
        "How it works:\n"
        "- Only the master-password prompt uses the cache; API keys and\n"
        "  two-factor codes are always asked for and never stored.\n"
        "- A miss asks with a dialog, or on rbw's terminal without a display,\n"
        "  and caches the answer.\n"
        "- A rejected password is removed from the cache and asked for again.\n"
        "- --clear removes this account's entry and the legacy per-profile entry."
    )
    parser = argparse.ArgumentParser(
        prog="rbw-pinentry",
        description=description,
        epilog=epilog,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "-c",
        "--clear",
        action="store_true",
        help="Clear the stored master password from secure storage and exit",
    )
    # Passed by rbw-agent. --ttyname is the prompt without a display; --timeout
    # (always 0) and --no-global-grab are accepted only so parsing succeeds.
    parser.add_argument("--timeout", type=str, help=argparse.SUPPRESS)
    parser.add_argument("--ttyname", type=str, help=argparse.SUPPRESS)
    parser.add_argument("--display", type=str, help=argparse.SUPPRESS)
    parser.add_argument("--no-global-grab", action="store_true", help=argparse.SUPPRESS)
    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args(sys.argv[1:])
    setup_logging()

    if args.clear:
        pinentry = Pinentry()
        try:
            removed = pinentry.clear_cached_password()
        except keyring.errors.KeyringError as e:
            print(f"Failed to clear cached password: {e}", file=sys.stderr)
            sys.exit(1)
        print(
            f"Cleared {removed} cached password(s) for profile: {pinentry.rbw_profile}"
        )
        sys.exit(0)

    pinentry = Pinentry(ttyname=args.ttyname, display=args.display)
    pinentry.handle_pinentry_session()
