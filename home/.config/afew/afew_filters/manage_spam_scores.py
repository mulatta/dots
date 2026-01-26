"""CLI for managing spam scores database."""

import argparse
import email
import email.policy
import subprocess
import sys
from enum import Enum

from spam_database import SpamDatabase


class OrderBy(str, Enum):
    """Enum for ordering options."""

    SCORE = "score"
    EMAIL = "email"
    LAST_SEEN = "last_seen"
    TOTAL_MESSAGES = "total_messages"


# --- Training commands (stdin email input) ---


def parse_email_from_stdin() -> tuple[str | None, str | None]:
    """Extract From address and Message-ID from email on stdin."""
    msg_bytes = sys.stdin.buffer.read()
    msg = email.message_from_bytes(msg_bytes, policy=email.policy.default)
    from_header = msg.get("From", "") or None
    message_id = msg.get("Message-ID", "") or None
    return from_header, message_id


def apply_notmuch_tags(message_id: str, add_tags: list[str], remove_tags: list[str]) -> bool:
    """Apply tags to message via notmuch."""
    if not message_id:
        return False

    tag_args = []
    for tag in add_tags:
        tag_args.append(f"+{tag}")
    for tag in remove_tags:
        tag_args.append(f"-{tag}")

    if not tag_args:
        return True

    mid = message_id.strip("<>")
    query = f"id:{mid}"

    try:
        subprocess.run(
            ["notmuch", "tag"] + tag_args + ["--", query],
            check=True,
            capture_output=True,
        )
        return True
    except subprocess.CalledProcessError as e:
        print(f"Error applying tags: {e.stderr.decode()}", file=sys.stderr)
        return False


def cmd_train_spam(args: argparse.Namespace) -> int:
    """Mark email as spam: update score + apply tags."""
    from_addr, message_id = parse_email_from_stdin()

    if not from_addr:
        print("Error: Could not extract From address", file=sys.stderr)
        return 1

    db = SpamDatabase()
    db.init_database()
    db.update_spam_score(from_addr, is_spam=True, confidence=100)
    email_addr = db.extract_email_address(from_addr)
    score = db.get_spam_score(from_addr)

    if message_id:
        apply_notmuch_tags(
            message_id,
            add_tags=["spam", "spam-manual"],
            remove_tags=["inbox", "unread", "ham", "ham-auto", "ham-manual"],
        )

    print(f"Trained as spam: {email_addr} (score: {score:.2f})", file=sys.stderr)
    return 0


def cmd_train_ham(args: argparse.Namespace) -> int:
    """Mark email as ham: update score + apply tags."""
    from_addr, message_id = parse_email_from_stdin()

    if not from_addr:
        print("Error: Could not extract From address", file=sys.stderr)
        return 1

    db = SpamDatabase()
    db.init_database()
    db.update_spam_score(from_addr, is_spam=False, confidence=100)
    email_addr = db.extract_email_address(from_addr)
    score = db.get_spam_score(from_addr)

    if message_id:
        apply_notmuch_tags(
            message_id,
            add_tags=["ham", "ham-manual", "inbox"],
            remove_tags=["spam", "spam-auto", "spam-manual"],
        )

    print(f"Trained as ham: {email_addr} (score: {score:.2f})", file=sys.stderr)
    return 0


# --- Database management commands ---


def cmd_list(args: argparse.Namespace) -> int:
    """List email addresses with their spam scores."""
    db = SpamDatabase()
    if not db.db_path.exists():
        print("No spam scores database found.")
        return 0

    with db.get_connection() as conn:
        base_query = """
            SELECT email, score, spam_count, ham_count, total_messages, last_seen
            FROM spam_scores
        """

        match args.order:
            case OrderBy.EMAIL:
                base_query += " ORDER BY email ASC"
            case OrderBy.LAST_SEEN:
                base_query += " ORDER BY last_seen DESC"
            case OrderBy.TOTAL_MESSAGES:
                base_query += " ORDER BY total_messages DESC"
            case OrderBy.SCORE | _:
                base_query += " ORDER BY score DESC"

        if args.limit:
            base_query += " LIMIT ?"
            cursor = conn.execute(base_query, (args.limit,))
        else:
            cursor = conn.execute(base_query)

        print(f"{'Email':<40} {'Score':>8} {'Spam':>6} {'Ham':>6} {'Total':>7} {'Last Seen'}")
        print("-" * 90)

        for row in cursor:
            email_addr, score, spam_count, ham_count, total, last_seen = row
            email_display = email_addr[:38] + ".." if len(email_addr) > 40 else email_addr
            print(f"{email_display:<40} {score:>8.2f} {spam_count:>6} {ham_count:>6} {total:>7} {last_seen}")

    return 0


def cmd_show(args: argparse.Namespace) -> int:
    """Show score for a specific sender."""
    db = SpamDatabase()
    if not db.db_path.exists():
        print("No spam scores database found.")
        return 1

    email_addr = args.email.lower()

    with db.get_connection() as conn:
        cursor = conn.execute(
            "SELECT score, total_messages, spam_count, ham_count, last_seen "
            "FROM spam_scores WHERE email = ?",
            (email_addr,),
        )
        row = cursor.fetchone()

    if row:
        score, total, spam, ham, last_seen = row
        print(f"Email: {email_addr}")
        print(f"Score: {score:.2f}")
        print(f"Total messages: {total}")
        print(f"Spam count: {spam}")
        print(f"Ham count: {ham}")
        print(f"Last seen: {last_seen}")
        return 0
    else:
        print(f"No record found for: {email_addr}", file=sys.stderr)
        return 1


def cmd_reset(args: argparse.Namespace) -> int:
    """Reset the spam score for an email address."""
    db = SpamDatabase()
    if not db.db_path.exists():
        print("No spam scores database found.")
        return 1

    email_addr = args.email.lower()

    with db.get_connection() as conn:
        conn.execute("DELETE FROM spam_scores WHERE email = ?", (email_addr,))
        if conn.total_changes > 0:
            print(f"Reset score for {email_addr}")
            conn.commit()
            return 0
        else:
            print(f"No score found for {email_addr}", file=sys.stderr)
            return 1


def cmd_set(args: argparse.Namespace) -> int:
    """Manually set the spam score for an email address."""
    db = SpamDatabase()
    db.init_database()

    email_addr = args.email.lower()
    score = args.score
    spam_count = 1 if score > 0 else 0
    ham_count = 0 if score > 0 else 1

    with db.get_connection() as conn:
        conn.execute(
            """INSERT OR REPLACE INTO spam_scores
               (email, score, spam_count, ham_count)
               VALUES (?, ?, ?, ?)""",
            (email_addr, score, spam_count, ham_count),
        )
        conn.commit()
    print(f"Set score for {email_addr} to {score}")
    return 0


def cmd_stats(args: argparse.Namespace) -> int:
    """Show database statistics."""
    db = SpamDatabase()
    if not db.db_path.exists():
        print("No spam scores database found.")
        return 0

    with db.get_connection() as conn:
        cursor = conn.execute("SELECT COUNT(*) FROM spam_scores")
        total_emails = cursor.fetchone()[0]

        cursor = conn.execute("SELECT COUNT(*) FROM spam_scores WHERE score >= 2.0")
        spam_emails = cursor.fetchone()[0]

        cursor = conn.execute("SELECT COUNT(*) FROM spam_scores WHERE score <= -2.0")
        ham_emails = cursor.fetchone()[0]

        cursor = conn.execute(
            "SELECT COUNT(*) FROM spam_scores WHERE score > -2.0 AND score < 2.0"
        )
        uncertain_emails = cursor.fetchone()[0]

        cursor = conn.execute("SELECT SUM(total_messages) FROM spam_scores")
        total_messages = cursor.fetchone()[0] or 0

    print("Database Statistics:")
    print(f"  Total email addresses: {total_emails}")
    print(f"  Spam addresses (score >= 2.0): {spam_emails}")
    print(f"  Ham addresses (score <= -2.0): {ham_emails}")
    print(f"  Uncertain addresses: {uncertain_emails}")
    print(f"  Total messages processed: {total_messages}")
    return 0


def main() -> None:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Manage spam scores database",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    subparsers = parser.add_subparsers(dest="command")

    # Training commands (read email from stdin)
    subparsers.add_parser(
        "train-spam",
        help="Mark email (from stdin) as spam and update sender score",
    )
    subparsers.add_parser(
        "train-ham",
        help="Mark email (from stdin) as ham and update sender score",
    )

    # List command
    list_parser = subparsers.add_parser("list", help="List email scores")
    list_parser.add_argument("-n", "--limit", type=int, help="Limit number of results")
    list_parser.add_argument(
        "-o",
        "--order",
        choices=[e.value for e in OrderBy],
        default=OrderBy.SCORE.value,
        help="Order results by field (default: score)",
    )

    # Show command
    show_parser = subparsers.add_parser("show", help="Show score for a specific sender")
    show_parser.add_argument("email", help="Email address to look up")

    # Reset command
    reset_parser = subparsers.add_parser("reset", help="Reset score for an email")
    reset_parser.add_argument("email", help="Email address to reset")

    # Set command
    set_parser = subparsers.add_parser("set", help="Manually set score for an email")
    set_parser.add_argument("email", help="Email address")
    set_parser.add_argument("score", type=float, help="Score to set")

    # Stats command
    subparsers.add_parser("stats", help="Show database statistics")

    args = parser.parse_args()

    # Convert order string to enum if present
    if hasattr(args, "order") and isinstance(args.order, str):
        args.order = OrderBy(args.order)

    commands = {
        "train-spam": cmd_train_spam,
        "train-ham": cmd_train_ham,
        "list": cmd_list,
        "show": cmd_show,
        "reset": cmd_reset,
        "set": cmd_set,
        "stats": cmd_stats,
    }

    if args.command in commands:
        sys.exit(commands[args.command](args))
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
