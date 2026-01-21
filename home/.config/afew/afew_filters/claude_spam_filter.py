"""Custom afew filter using Claude Code to classify emails as spam/ham."""

import email
import email.policy
import json
import logging
import os
import subprocess
import tempfile
from pathlib import Path
from typing import Any

from afew.FilterRegistry import register_filter
from afew.filters.BaseFilter import Filter
from notmuch2._errors import NullPointerError

from .spam_database import SpamDatabase

logger = logging.getLogger(__name__)

# JSON schema for Claude's structured output
SPAM_CLASSIFICATION_SCHEMA = json.dumps({
    "type": "object",
    "properties": {
        "is_spam": {"type": "boolean"},
        "confidence": {"type": "integer", "minimum": 0, "maximum": 100},
        "reason": {"type": "string"},
    },
    "required": ["is_spam", "confidence", "reason"],
})


@register_filter
class ClaudeSpamFilter(Filter):
    """Use Claude Code to analyze emails from unknown senders for spam detection."""

    message = "Analyzing emails with Claude Code for spam detection"
    # Configuration: restrict to specific maildir path
    maildir_path: str | None = None
    # Thresholds for auto-classification
    spam_threshold: float = 2.0
    ham_threshold: float = -2.0
    # Max messages to process in initial run
    max_initial_messages: int = 40

    def __init__(self, database: Any, **kwargs: Any) -> None:
        super().__init__(database, **kwargs)

        # Build query for unanalyzed emails
        base_query = "NOT tag:spam AND NOT tag:ham AND NOT tag:claude-analyzed"
        if self.maildir_path:
            self.query = f"folder:{self.maildir_path} AND {base_query}"
        else:
            self.query = base_query

        # Initialize spam database
        self.spam_db = SpamDatabase()
        self.spam_db.init_database()

        # Lazy-loaded khard contacts
        self._khard_contacts: set[str] | None = None

        # Check message count for initial run protection
        self._check_initial_message_count(database)

    def _check_initial_message_count(self, database: Any) -> None:
        """Skip Claude if too many unanalyzed messages (initial sync)."""
        try:
            messages = database.get_messages(self.query)
            self.message_count = len(list(messages))
            self.skip_claude = self.message_count > int(self.max_initial_messages)

            if self.skip_claude:
                logger.warning(
                    "Found %d unanalyzed messages (limit: %d). "
                    "Marking all as analyzed to start fresh.",
                    self.message_count,
                    int(self.max_initial_messages),
                )
                subprocess.run(
                    ["notmuch", "tag", "+claude-analyzed", "--", self.query],
                    check=False,
                    capture_output=True,
                )
        except Exception:
            logger.exception("Error counting messages")
            self.skip_claude = False
            self.message_count = 0

    @property
    def khard_contacts(self) -> set[str]:
        """Lazy-load khard contacts."""
        if self._khard_contacts is None:
            self._khard_contacts = self._load_khard_contacts()
        return self._khard_contacts

    def _load_khard_contacts(self) -> set[str]:
        """Load email addresses from khard."""
        try:
            env = os.environ.copy()
            env["LC_ALL"] = "C"
            result = subprocess.run(
                ["khard", "email", "--parsable", "--remove-first-line"],
                check=False,
                capture_output=True,
                text=True,
                timeout=5,
                env=env,
            )
            if result.returncode == 0:
                contacts = set()
                for line in result.stdout.strip().split("\n"):
                    if line and "\t" in line:
                        email_addr = line.split("\t")[0].strip().lower()
                        if "@" in email_addr:
                            contacts.add(email_addr)
                logger.info("Loaded %d contacts from khard", len(contacts))
                return contacts
        except (subprocess.SubprocessError, OSError):
            logger.exception("Error loading khard contacts")
        return set()

    def _is_known_sender(self, from_addr: str) -> bool:
        """Check if sender is in khard contacts."""
        email_addr = self.spam_db.extract_email_address(from_addr)
        return email_addr in self.khard_contacts

    def _extract_email_content(self, filename: str) -> tuple[str, list[str]]:
        """Extract body text and attachments from email file."""
        try:
            with Path(filename).open("rb") as f:
                msg = email.message_from_binary_file(
                    f, policy=email.policy.default
                )
                return self._process_email_parts(msg)
        except OSError:
            logger.exception("Error reading email file")
            return "[Error reading body]", []

    def _process_email_parts(self, msg: Any) -> tuple[str, list[str]]:
        """Process MIME parts to extract body and attachments."""
        body = ""
        attachments = []

        for part in msg.walk():
            content_type = part.get_content_type()
            disposition = str(part.get("Content-Disposition", ""))

            if "attachment" in disposition:
                filename = part.get_filename()
                if filename:
                    attachments.append(f"{filename} ({content_type})")
            elif part.is_multipart():
                continue
            elif content_type == "text/plain" and not body:
                body = self._extract_text(part)
            elif content_type == "text/html" and not body:
                body = self._extract_html(part)

        if not body:
            body = "[No text content]" if not attachments else "[See attachments]"

        return body[:1500], attachments  # Limit body length

    def _extract_text(self, part: Any) -> str:
        """Extract plain text content."""
        try:
            payload = part.get_payload(decode=True)
            if isinstance(payload, bytes):
                return payload.decode("utf-8", errors="ignore")
        except (AttributeError, TypeError):
            pass
        return ""

    def _extract_html(self, part: Any) -> str:
        """Extract HTML content and convert to text using w3m."""
        try:
            payload = part.get_payload(decode=True)
            if isinstance(payload, bytes):
                html = payload.decode("utf-8", errors="ignore")
                result = subprocess.run(
                    ["w3m", "-dump", "-T", "text/html"],
                    input=html,
                    capture_output=True,
                    text=True,
                    timeout=5,
                )
                if result.returncode == 0:
                    return result.stdout
        except (subprocess.SubprocessError, AttributeError, TypeError):
            pass
        return ""

    def _get_headers(self, message: Any) -> dict[str, str]:
        """Extract relevant headers from message."""
        headers = {}
        header_names = [
            "Subject", "From", "To", "Date", "Reply-To",
            "Return-Path", "List-Unsubscribe", "X-Mailer",
        ]
        for name in header_names:
            try:
                headers[name.lower().replace("-", "_")] = message.header(name)
            except (LookupError, NullPointerError):
                headers[name.lower().replace("-", "_")] = ""
        return headers

    def _build_prompt(
        self, headers: dict[str, str], body: str, attachments: list[str]
    ) -> str:
        """Build the prompt for Claude analysis."""
        return f"""Analyze this email and determine if it is spam.

Email headers:
- From: {headers.get("from", "")}
- To: {headers.get("to", "")}
- Subject: {headers.get("subject", "")}
- Date: {headers.get("date", "")}
- Reply-To: {headers.get("reply_to", "")}
- Return-Path: {headers.get("return_path", "")}
- List-Unsubscribe: {headers.get("list_unsubscribe", "")}
- X-Mailer: {headers.get("x_mailer", "")}

Attachments: {", ".join(attachments) if attachments else "None"}

Body:
{body}

Consider these spam indicators:
- Suspicious sender/reply-to mismatch
- Phishing attempts or scam patterns
- Unsolicited commercial content
- Bulk mailing indicators
- Suspicious attachments
- Urgency tactics or threatening language

Respond with your classification."""

    def _call_claude(self, prompt: str) -> dict[str, Any] | None:
        """Call Claude Code with JSON schema for structured output."""
        try:
            with tempfile.TemporaryDirectory() as tmpdir:
                result = subprocess.run(
                    [
                        "claude",
                        "-p",
                        "--model", "sonnet",
                        "--output-format", "json",
                        "--json-schema", SPAM_CLASSIFICATION_SCHEMA,
                        "--disallowed-tools",
                        "Bash,Edit,Write,Read,Grep,Glob,Task,WebSearch,WebFetch,"
                        "TodoWrite,NotebookEdit,ExitPlanMode,KillShell",
                    ],
                    input=prompt,
                    capture_output=True,
                    text=True,
                    timeout=60,
                    cwd=tmpdir,
                )

                if result.returncode == 0:
                    response = json.loads(result.stdout)
                    return response.get("structured_output")
                else:
                    logger.error("Claude error: %s", result.stderr)

        except subprocess.TimeoutExpired:
            logger.warning("Claude timed out")
        except (json.JSONDecodeError, OSError) as e:
            logger.exception("Error calling Claude: %s", e)

        return None

    def handle_message(self, message: Any) -> None:
        """Process each message for spam classification."""
        if self.skip_claude:
            return

        try:
            from_addr = message.header("From")
        except (LookupError, NullPointerError):
            from_addr = ""

        # Skip known contacts
        if self._is_known_sender(from_addr):
            logger.debug("Skipping known sender: %s", from_addr)
            return

        # Try auto-classification by sender score
        if self._auto_classify(message, from_addr):
            return

        # Call Claude for unknown/uncertain senders
        self._classify_with_claude(message, from_addr)

    def _auto_classify(self, message: Any, from_addr: str) -> bool:
        """Auto-classify based on accumulated sender score."""
        score = self.spam_db.get_spam_score(from_addr)
        if score is None:
            return False

        if score >= self.spam_threshold:
            logger.info("Auto-spam (score=%.2f): %s", score, from_addr)
            self.add_tags(message, "spam", "spam-auto")
            return True
        elif score <= self.ham_threshold:
            logger.info("Auto-ham (score=%.2f): %s", score, from_addr)
            self.add_tags(message, "ham", "ham-auto")
            return True

        return False

    def _classify_with_claude(self, message: Any, from_addr: str) -> None:
        """Classify message using Claude."""
        headers = self._get_headers(message)
        filename = str(next(message.filenames()))
        body, attachments = self._extract_email_content(filename)

        prompt = self._build_prompt(headers, body, attachments)
        result = self._call_claude(prompt)

        if not result:
            logger.warning("No classification result for: %s", from_addr)
            return

        is_spam = result.get("is_spam", False)
        confidence = result.get("confidence", 50)
        reason = result.get("reason", "")

        logger.info(
            "Claude: %s (confidence=%d) - %s | %s",
            "SPAM" if is_spam else "HAM",
            confidence,
            from_addr,
            reason[:100],
        )

        self.spam_db.update_spam_score(from_addr, is_spam, confidence)

        # Apply tags
        self.add_tags(message, "claude-analyzed")
        if is_spam:
            self.add_tags(message, "spam", "claude-spam")
            self._add_confidence_tags(message, confidence)
        else:
            self.add_tags(message, "ham", "claude-ham")

    def _add_confidence_tags(self, message: Any, confidence: int) -> None:
        """Add confidence level tags for spam classification."""
        if confidence >= 90:
            self.add_tags(message, "spam-high-confidence")
        elif confidence >= 70:
            self.add_tags(message, "spam-medium-confidence")
        else:
            self.add_tags(message, "spam-low-confidence")
