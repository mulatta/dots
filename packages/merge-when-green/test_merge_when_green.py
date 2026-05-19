#!/usr/bin/env python3
"""Unit tests for merge-when-green."""

import importlib.util
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

spec = importlib.util.spec_from_file_location(
    "merge_when_green", Path(__file__).parent / "merge-when-green.py"
)
mgwg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mgwg)


class TestGitHelpers(unittest.TestCase):
    def test_get_default_branch_success(self):
        with patch.object(mgwg, "run") as mock_run:
            mock_run.return_value = MagicMock(stdout="main\n", returncode=0)
            self.assertEqual(mgwg.get_default_branch(), "main")

    def test_get_default_branch_fallback(self):
        with patch.object(mgwg, "run") as mock_run:
            mock_run.return_value = MagicMock(stdout="", returncode=1)
            self.assertEqual(mgwg.get_default_branch(), "main")

    def test_get_remotes(self):
        with patch.object(mgwg, "run") as mock_run:
            mock_run.return_value = MagicMock(stdout="origin\nupstream\n", returncode=0)
            self.assertEqual(mgwg.get_remotes(), ["origin", "upstream"])

    def test_get_upstream_remote_prefers_upstream(self):
        with patch.object(mgwg, "get_remotes", return_value=["origin", "upstream"]):
            self.assertEqual(mgwg.get_upstream_remote(), "upstream")

    def test_get_upstream_remote_falls_back_to_origin(self):
        with patch.object(mgwg, "get_remotes", return_value=["origin"]):
            self.assertEqual(mgwg.get_upstream_remote(), "origin")

    def test_get_origin_owner_ssh(self):
        with patch.object(mgwg, "run") as mock_run:
            mock_run.return_value = MagicMock(
                stdout="git@github.com:mulatta/dots.git\n", returncode=0
            )
            self.assertEqual(mgwg.get_origin_owner(), "mulatta")

    def test_get_origin_owner_https(self):
        with patch.object(mgwg, "run") as mock_run:
            mock_run.return_value = MagicMock(
                stdout="https://github.com/mulatta/dots.git\n", returncode=0
            )
            self.assertEqual(mgwg.get_origin_owner(), "mulatta")

    def test_get_head_ref_uses_owner_for_fork(self):
        with patch.object(mgwg, "get_remotes", return_value=["origin", "upstream"]):
            with patch.object(mgwg, "get_origin_owner", return_value="mulatta"):
                self.assertEqual(mgwg.get_head_ref("feature"), "mulatta:feature")

    def test_branch_for_push_uses_current_branch(self):
        with patch.object(mgwg, "current_branch", return_value="feature"):
            self.assertEqual(mgwg.branch_for_push("main"), "feature")

    def test_branch_for_push_creates_scratch_branch_on_default(self):
        with patch.object(mgwg, "current_branch", return_value="main"):
            with patch.dict(os.environ, {"USER": "testuser"}):
                self.assertEqual(
                    mgwg.branch_for_push("main"), "merge-when-green-testuser"
                )


class TestFormatCheck(unittest.TestCase):
    def test_run_format_check_flake_fmt_fails(self):
        with patch.object(mgwg, "run") as mock_run:
            mock_run.return_value = MagicMock(
                stdout="", stderr="flake-fmt: command not found", returncode=127
            )
            self.assertFalse(mgwg.run_format_check())

    def test_run_format_check_success(self):
        with patch.object(mgwg, "run") as mock_run:
            mock_run.return_value = MagicMock(stdout="", stderr="", returncode=0)
            self.assertTrue(mgwg.run_format_check())


class TestPullRequest(unittest.TestCase):
    def test_pr_exists_true(self):
        with patch.object(mgwg, "get_head_ref", return_value="test-branch"):
            with patch.object(mgwg, "run") as mock_run:
                mock_run.return_value = MagicMock(
                    stdout='{"state": "OPEN"}', returncode=0
                )
                self.assertTrue(mgwg.pr_exists("test-branch"))

    def test_pr_exists_false_closed(self):
        with patch.object(mgwg, "get_head_ref", return_value="test-branch"):
            with patch.object(mgwg, "run") as mock_run:
                mock_run.return_value = MagicMock(
                    stdout='{"state": "CLOSED"}', returncode=0
                )
                self.assertFalse(mgwg.pr_exists("test-branch"))

    def test_enable_auto_merge_uses_rebase(self):
        with patch.object(mgwg, "get_head_ref", return_value="test-branch"):
            with patch.object(mgwg, "run") as mock_run:
                mock_run.return_value = MagicMock(returncode=0)
                self.assertTrue(mgwg.enable_auto_merge("test-branch"))
                call_args = mock_run.call_args[0][0]
                self.assertIn("--rebase", call_args)
                self.assertIn("--auto", call_args)

    def test_count_checks(self):
        checks = [
            {"__typename": "CheckRun", "status": "COMPLETED", "conclusion": "SUCCESS"},
            {"__typename": "CheckRun", "status": "COMPLETED", "conclusion": "FAILURE"},
            {"__typename": "CheckRun", "status": "IN_PROGRESS", "conclusion": None},
            {"__typename": "StatusContext", "state": "SUCCESS"},
            {"__typename": "StatusContext", "state": "PENDING"},
        ]
        passed, failed, pending = mgwg.count_checks(checks)
        self.assertEqual(passed, 2)
        self.assertEqual(failed, 1)
        self.assertEqual(pending, 2)

    def test_get_merge_queue_status(self):
        repo = MagicMock(
            stdout='{"owner": {"login": "owner"}, "name": "repo"}', returncode=0
        )
        queue = MagicMock(
            stdout=(
                '{"data": {"repository": {"pullRequest": {'
                '"isInMergeQueue": true, '
                '"mergeQueueEntry": {"state": "QUEUED", "position": 2}'
                "}}}}"
            ),
            returncode=0,
        )
        with patch.object(mgwg, "run", side_effect=[repo, queue]):
            in_queue, label = mgwg.get_merge_queue_status(123)
            self.assertTrue(in_queue)
            self.assertEqual(label, "queue pos 2, QUEUED")

    def test_wait_for_merge_allows_missing_automerge_in_queue(self):
        pr_open = {
            "number": 123,
            "state": "OPEN",
            "mergeable": "MERGEABLE",
            "autoMergeRequest": None,
            "statusCheckRollup": [],
        }
        pr_merged = {**pr_open, "state": "MERGED"}
        with patch.object(mgwg, "get_pr_status", side_effect=[pr_open, pr_merged]):
            with patch.object(
                mgwg, "get_merge_queue_status", return_value=(True, "QUEUED")
            ):
                with patch.object(mgwg, "time") as mock_time:
                    mock_time.strftime.return_value = "12:00:00"
                    self.assertTrue(mgwg.wait_for_merge("test-branch"))


class TestMessages(unittest.TestCase):
    def test_get_pr_message_from_arg_title_only(self):
        self.assertEqual(mgwg.get_pr_message("title", "main", "origin"), ("title", ""))

    def test_get_pr_message_from_arg_title_and_body(self):
        self.assertEqual(
            mgwg.get_pr_message("title\n\nbody", "main", "origin"),
            ("title", "\nbody"),
        )

    def test_get_pr_message_from_editor(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            editor = Path(tmpdir) / "editor.py"
            editor.write_text(
                "#!/usr/bin/env python3\n"
                "import pathlib, sys\n"
                "pathlib.Path(sys.argv[1]).write_text('edited title\\nbody')\n"
            )
            editor.chmod(0o755)
            with patch.dict(os.environ, {"EDITOR": str(editor)}):
                with patch.object(mgwg, "run") as mock_run:
                    mock_run.return_value = MagicMock(
                        stdout="commit title\n", returncode=0
                    )
                    self.assertEqual(
                        mgwg.get_pr_message_from_editor("main", "origin"),
                        ("edited title", "body"),
                    )


class TestRun(unittest.TestCase):
    def test_run_capture(self):
        result = mgwg.run(["echo", "hello"], capture=True)
        self.assertEqual(result.stdout.strip(), "hello")
        self.assertEqual(result.returncode, 0)

    def test_run_check_false(self):
        result = mgwg.run(["false"], check=False, capture=True)
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
