#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
import pathlib
import sys
import tempfile
import unittest
from unittest.mock import patch

MODULE_PATH = pathlib.Path(__file__).with_name("jmap-handoff.py")
spec = importlib.util.spec_from_file_location("jmap_handoff", MODULE_PATH)
assert spec is not None
jmap_handoff = importlib.util.module_from_spec(spec)
sys.modules["jmap_handoff"] = jmap_handoff
assert spec.loader is not None
spec.loader.exec_module(jmap_handoff)


class FakeClient:
    account_id = "account"

    def __init__(self, response: list[object]):
        self.response = response

    def request(self, method_calls: list[list[object]]) -> list[object]:
        self.method_calls = method_calls
        return self.response


class JmapHandoffTests(unittest.TestCase):
    def test_maildir_filename_uses_sanitized_message_id(self) -> None:
        self.assertEqual(
            jmap_handoff.maildir_filename(["<weird/id with spaces@example.org>"], "M1"),
            "weird_id_with_spaces@example.org:2,FS",
        )

    def test_maildir_filename_falls_back_to_email_id(self) -> None:
        self.assertEqual(jmap_handoff.maildir_filename([], "M123"), "M123:2,FS")

    def test_expand_download_url_quotes_template_values(self) -> None:
        url = jmap_handoff.expand_download_url(
            "https://mail.example/download/{accountId}/{blobId}/{name}?accept={type}",
            "acc 1",
            "blob/2",
        )
        self.assertEqual(
            url,
            "https://mail.example/download/acc%201/blob%2F2/message.eml?accept=message%2Frfc822",
        )

    def test_default_session_url_uses_stalwart_domain(self) -> None:
        with patch.dict(os.environ, {"JMAP_PASSWORD": "secret"}, clear=True):
            config = jmap_handoff.load_config()
        self.assertEqual(
            config.session_url, "https://stalwart.mulatta.io/.well-known/jmap"
        )

    def test_select_account_id_by_name(self) -> None:
        session = {"accounts": {"h": {"name": "noa"}, "b": {"name": "seungwon"}}}
        self.assertEqual(jmap_handoff.select_account_id(session, "seungwon"), "b")

    def test_select_account_id_uses_primary_mail_account(self) -> None:
        session = {"primaryAccounts": {jmap_handoff.JMAP_MAIL: "h"}}
        self.assertEqual(jmap_handoff.select_account_id(session, None), "h")

    def test_build_flagged_filter_without_mailbox(self) -> None:
        self.assertEqual(
            jmap_handoff.build_flagged_filter(None), {"hasKeyword": "$flagged"}
        )

    def test_build_flagged_filter_with_mailbox(self) -> None:
        self.assertEqual(
            jmap_handoff.build_flagged_filter("mbox1"),
            {
                "operator": "AND",
                "conditions": [{"hasKeyword": "$flagged"}, {"inMailbox": "mbox1"}],
            },
        )

    def test_mailbox_path_walks_parents(self) -> None:
        root = {"id": "root", "name": "Shared"}
        user = {"id": "user", "name": "seungwon", "parentId": "root"}
        inbox = {"id": "inbox", "name": "INBOX", "parentId": "user"}
        self.assertEqual(
            jmap_handoff.mailbox_path(
                inbox, {"root": root, "user": user, "inbox": inbox}
            ),
            "Shared/seungwon/INBOX",
        )

    def test_clear_flagged_accepts_updated_response(self) -> None:
        client = FakeClient([["Email/set", {"updated": {"M1": None}}, "clear"]])
        jmap_handoff.clear_flagged(client, "M1")

    def test_clear_flagged_rejects_not_updated_response(self) -> None:
        client = FakeClient(
            [["Email/set", {"notUpdated": {"M1": {"type": "forbidden"}}}, "clear"]]
        )
        with self.assertRaisesRegex(jmap_handoff.JmapError, "failed to clear"):
            jmap_handoff.clear_flagged(client, "M1")

    def test_clear_flagged_requires_updated_response(self) -> None:
        client = FakeClient([["Email/set", {"updated": {}}, "clear"]])
        with self.assertRaisesRegex(jmap_handoff.JmapError, "no updated response"):
            jmap_handoff.clear_flagged(client, "M1")

    def test_deliver_raw_writes_once_to_cur(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            maildir = pathlib.Path(tmp) / "Maildir"
            filename = "msg@example.org:2,FS"
            first = jmap_handoff.deliver_raw(
                maildir, filename, b"Subject: hi\r\n\r\nbody"
            )
            second = jmap_handoff.deliver_raw(
                maildir, filename, b"Subject: bye\r\n\r\nbody"
            )

            self.assertTrue(first)
            self.assertFalse(second)
            self.assertEqual(
                (maildir / "cur" / filename).read_bytes(), b"Subject: hi\r\n\r\nbody"
            )
            self.assertTrue((maildir / "new").is_dir())
            self.assertTrue((maildir / "tmp").is_dir())

    def test_build_flagged_trigger_line_encodes_named_fields(self) -> None:
        line = jmap_handoff.build_flagged_trigger_line(
            filename="msg id@example.org:2,FS",
            email_id="M/1",
            message_ids=["<msg id@example.org>"],
            subject="Hello world",
            received_at="2026-05-12T13:00:00Z",
        )

        self.assertEqual(
            line,
            "mail.flagged "
            "schema=opencrow.trigger.v1 "
            "action=handoff "
            "filename=msg%20id%40example.org%3A2%2CFS "
            "email_id=M%2F1 "
            "message_id=%3Cmsg%20id%40example.org%3E "
            "subject=Hello%20world "
            "received_at=2026-05-12T13%3A00%3A00Z "
            "event_id=mail%3Aflagged%3AM%2F1",
        )

    def test_notify_trigger_does_not_block_without_reader(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            pipe = pathlib.Path(tmp) / "trigger.pipe"
            os.mkfifo(pipe)
            jmap_handoff.notify_trigger(pipe, "mail.flagged filename=file")


if __name__ == "__main__":
    unittest.main()
