#!/usr/bin/env python3
"""
Unit tests for merge-when-green

Creates a temporary jj repository in /tmp for testing.
GitHub API calls are mocked.
"""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch, MagicMock

# Import the module under test
import importlib.util
spec = importlib.util.spec_from_file_location(
    "merge_when_green",
    Path(__file__).parent / "merge-when-green.py"
)
mgwg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mgwg)


class TestJJRepository(unittest.TestCase):
    """Test cases that require a real jj repository."""

    @classmethod
    def setUpClass(cls):
        """Create a temporary jj repository."""
        cls.test_dir = tempfile.mkdtemp(prefix="mgwg-test-")
        cls.orig_dir = os.getcwd()

        os.chdir(cls.test_dir)
        subprocess.run(["jj", "git", "init"], check=True, capture_output=True)
        subprocess.run(
            ["jj", "config", "set", "--repo", "user.name", "Test User"],
            check=True, capture_output=True
        )
        subprocess.run(
            ["jj", "config", "set", "--repo", "user.email", "test@example.com"],
            check=True, capture_output=True
        )
        Path("README.md").write_text("# Test Repo\n")
        subprocess.run(["jj", "commit", "-m", "Initial commit"], check=True, capture_output=True)

    @classmethod
    def tearDownClass(cls):
        os.chdir(cls.orig_dir)
        shutil.rmtree(cls.test_dir, ignore_errors=True)

    def setUp(self):
        os.chdir(self.test_dir)

    def test_get_current_bookmark_none(self):
        """Test get_current_bookmark when no bookmark exists."""
        result = mgwg.get_current_bookmark()
        self.assertIsNone(result)

    def test_get_current_bookmark_exists(self):
        """Test get_current_bookmark when bookmark exists."""
        bookmark_name = "test-bookmark-exists"
        subprocess.run(
            ["jj", "bookmark", "create", bookmark_name],
            check=True, capture_output=True
        )
        result = mgwg.get_current_bookmark()
        self.assertEqual(result, bookmark_name)
        subprocess.run(["jj", "bookmark", "delete", bookmark_name], check=False, capture_output=True)

    def test_get_current_bookmark_prefers_merge_when_green(self):
        """Test get_current_bookmark prefers merge-when-green-* pattern."""
        subprocess.run(["jj", "bookmark", "create", "aaa-first"], check=True, capture_output=True)
        subprocess.run(["jj", "bookmark", "create", "merge-when-green-user"], check=True, capture_output=True)
        subprocess.run(["jj", "bookmark", "create", "zzz-last"], check=True, capture_output=True)

        result = mgwg.get_current_bookmark()
        self.assertEqual(result, "merge-when-green-user")

        # Cleanup
        subprocess.run(["jj", "bookmark", "delete", "aaa-first"], check=False, capture_output=True)
        subprocess.run(["jj", "bookmark", "delete", "merge-when-green-user"], check=False, capture_output=True)
        subprocess.run(["jj", "bookmark", "delete", "zzz-last"], check=False, capture_output=True)

    def test_delete_bookmark(self):
        """Test deleting a bookmark."""
        bookmark_name = "test-delete-bookmark"
        subprocess.run(
            ["jj", "bookmark", "create", bookmark_name],
            check=True, capture_output=True
        )
        mgwg.delete_bookmark(bookmark_name)
        result = subprocess.run(
            ["jj", "bookmark", "list"],
            capture_output=True, text=True
        )
        self.assertNotIn(bookmark_name, result.stdout)


class TestValidation(unittest.TestCase):
    """Test validation functions."""

    def test_has_conflict_false(self):
        """Test has_conflict returns False for normal commit."""
        with patch.object(mgwg, 'run') as mock_run:
            mock_run.return_value = MagicMock(stdout="false", returncode=0)
            result = mgwg.has_conflict("@")
            self.assertFalse(result)

    def test_has_conflict_true(self):
        """Test has_conflict returns True for conflicted commit."""
        with patch.object(mgwg, 'run') as mock_run:
            mock_run.return_value = MagicMock(stdout="true", returncode=0)
            result = mgwg.has_conflict("@")
            self.assertTrue(result)

    def test_validate_state_conflict_exits(self):
        """Test validate_state exits on conflict."""
        with patch.object(mgwg, 'has_conflict', return_value=True):
            with self.assertRaises(SystemExit) as cm:
                mgwg.validate_state()
            self.assertEqual(cm.exception.code, 1)

    def test_validate_state_empty_exits(self):
        """Test validate_state exits when both @ and @- are empty."""
        with patch.object(mgwg, 'has_conflict', return_value=False):
            with patch.object(mgwg, 'is_commit_empty', return_value=True):
                with self.assertRaises(SystemExit) as cm:
                    mgwg.validate_state()
                self.assertEqual(cm.exception.code, 1)


class TestTargetRevision(unittest.TestCase):
    """Test cases for target revision detection."""

    def test_get_target_revision_with_description(self):
        """Test get_target_revision when @ has description."""
        with patch.object(mgwg, 'get_description', return_value="feat: something"):
            with patch.object(mgwg, 'is_commit_empty', return_value=False):
                result = mgwg.get_target_revision()
                self.assertEqual(result, "@")

    def test_get_target_revision_empty_with_no_description(self):
        """Test get_target_revision when @ is empty and has no description."""
        with patch.object(mgwg, 'get_description', return_value=""):
            with patch.object(mgwg, 'is_commit_empty', return_value=True):
                result = mgwg.get_target_revision()
                self.assertEqual(result, "@-")

    def test_get_target_revision_changes_no_description_exits(self):
        """Test get_target_revision exits when @ has changes but no description."""
        with patch.object(mgwg, 'get_description', return_value=""):
            with patch.object(mgwg, 'is_commit_empty', return_value=False):
                with self.assertRaises(SystemExit) as cm:
                    mgwg.get_target_revision(title_provided=False)
                self.assertEqual(cm.exception.code, 1)

    def test_get_target_revision_changes_no_description_with_title(self):
        """Test get_target_revision allows @ with changes but no description if title provided."""
        with patch.object(mgwg, 'get_description', return_value=""):
            with patch.object(mgwg, 'is_commit_empty', return_value=False):
                result = mgwg.get_target_revision(title_provided=True)
                self.assertEqual(result, "@")


class TestBookmarkManagement(unittest.TestCase):
    """Test bookmark creation and management."""

    def test_get_or_create_bookmark_existing(self):
        """Test get_or_create_bookmark uses existing bookmark."""
        with patch.object(mgwg, 'get_current_bookmark', return_value="my-feature"):
            bookmark = mgwg.get_or_create_bookmark()
            self.assertEqual(bookmark, "my-feature")

    def test_get_or_create_bookmark_creates_merge_when_green(self):
        """Test get_or_create_bookmark creates merge-when-green-<user> when none exists."""
        with patch.object(mgwg, 'get_current_bookmark', return_value=None):
            with patch.object(mgwg, 'get_target_revision', return_value="@"):
                with patch.object(mgwg, 'run'):
                    with patch.dict(os.environ, {'USER': 'testuser'}):
                        bookmark = mgwg.get_or_create_bookmark()
                        self.assertEqual(bookmark, "merge-when-green-testuser")


class TestFormatCheck(unittest.TestCase):
    """Test cases for format check functionality."""

    def test_run_format_check_jmt_fails(self):
        """Test run_format_check when jmt fails."""
        with patch.object(mgwg, 'run') as mock_run:
            mock_run.return_value = MagicMock(
                stdout="",
                stderr="jmt: command not found",
                returncode=127
            )
            result = mgwg.run_format_check()
            self.assertFalse(result)

    def test_run_format_check_success(self):
        """Test run_format_check when everything succeeds."""
        with patch.object(mgwg, 'run') as mock_run:
            mock_run.return_value = MagicMock(
                stdout="",
                stderr="",
                returncode=0
            )
            result = mgwg.run_format_check()
            self.assertTrue(result)


class TestGitHubMocked(unittest.TestCase):
    """Test cases with mocked GitHub CLI."""

    def test_get_default_branch_success(self):
        """Test get_default_branch with successful gh response."""
        with patch.object(mgwg, 'run') as mock_run:
            mock_run.return_value = MagicMock(stdout="main\n", returncode=0)
            result = mgwg.get_default_branch()
            self.assertEqual(result, "main")

    def test_get_default_branch_fallback(self):
        """Test get_default_branch fallback when gh fails."""
        with patch.object(mgwg, 'run') as mock_run:
            mock_run.return_value = MagicMock(stdout="", returncode=1)
            result = mgwg.get_default_branch()
            self.assertEqual(result, "main")

    def test_pr_exists_true(self):
        """Test pr_exists when PR exists."""
        with patch.object(mgwg, 'run') as mock_run:
            mock_run.return_value = MagicMock(stdout='{"state": "OPEN"}', returncode=0)
            result = mgwg.pr_exists("test-branch")
            self.assertTrue(result)

    def test_pr_exists_false_closed(self):
        """Test pr_exists when PR is closed."""
        with patch.object(mgwg, 'run') as mock_run:
            mock_run.return_value = MagicMock(stdout='{"state": "CLOSED"}', returncode=0)
            result = mgwg.pr_exists("test-branch")
            self.assertFalse(result)

    def test_pr_exists_false_not_found(self):
        """Test pr_exists when PR doesn't exist."""
        with patch.object(mgwg, 'run') as mock_run:
            mock_run.return_value = MagicMock(stdout="", returncode=1)
            result = mgwg.pr_exists("test-branch")
            self.assertFalse(result)

    def test_count_checks(self):
        """Test count_checks with various check states."""
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

    def test_enable_auto_merge_rebase(self):
        """Test enable_auto_merge uses rebase strategy."""
        with patch.object(mgwg, 'run') as mock_run:
            mock_run.return_value = MagicMock(returncode=0)
            mgwg.enable_auto_merge("test-branch")
            call_args = mock_run.call_args[0][0]
            self.assertIn("--rebase", call_args)
            self.assertIn("--auto", call_args)


class TestHelperFunctions(unittest.TestCase):
    """Test helper functions that don't need a repository."""

    def test_run_capture(self):
        """Test run with capture=True."""
        result = mgwg.run(["echo", "hello"], capture=True)
        self.assertEqual(result.stdout.strip(), "hello")
        self.assertEqual(result.returncode, 0)

    def test_run_check_false(self):
        """Test run with check=False doesn't raise."""
        result = mgwg.run(["false"], check=False, capture=True)
        self.assertNotEqual(result.returncode, 0)

    def test_colors(self):
        """Test color codes are defined."""
        self.assertTrue(mgwg.Colors.GREEN.startswith("\033["))
        self.assertTrue(mgwg.Colors.RED.startswith("\033["))
        self.assertTrue(mgwg.Colors.YELLOW.startswith("\033["))


class TestIntegration(unittest.TestCase):
    """Integration tests with temporary repository."""

    @classmethod
    def setUpClass(cls):
        cls.test_dir = tempfile.mkdtemp(prefix="mgwg-integration-")
        cls.orig_dir = os.getcwd()

        os.chdir(cls.test_dir)
        subprocess.run(["jj", "git", "init"], check=True, capture_output=True)
        subprocess.run(
            ["jj", "config", "set", "--repo", "user.name", "Test"],
            check=True, capture_output=True
        )
        subprocess.run(
            ["jj", "config", "set", "--repo", "user.email", "test@test.com"],
            check=True, capture_output=True
        )
        Path("README.md").write_text("# Project\n")
        subprocess.run(["jj", "commit", "-m", "init"], check=True, capture_output=True)
        subprocess.run(["jj", "bookmark", "create", "main"], check=True, capture_output=True)

    @classmethod
    def tearDownClass(cls):
        os.chdir(cls.orig_dir)
        shutil.rmtree(cls.test_dir, ignore_errors=True)

    def setUp(self):
        os.chdir(self.test_dir)

    def test_full_bookmark_workflow(self):
        """Test complete bookmark creation workflow."""
        subprocess.run(
            ["jj", "new", "-m", "feat: add feature"],
            check=True, capture_output=True
        )
        Path("feature.py").write_text("# feature\n")

        # @- has 'main' bookmark from setup, so get_current_bookmark returns it
        # Delete main bookmark to test the "no bookmark" case
        subprocess.run(
            ["jj", "bookmark", "delete", "main"],
            check=False, capture_output=True
        )

        # Now no bookmark on @ or @-
        bookmark = mgwg.get_current_bookmark()
        self.assertIsNone(bookmark)

        # get_or_create_bookmark creates merge-when-green-<user>
        with patch.dict(os.environ, {'USER': 'testuser'}):
            new_bookmark = mgwg.get_or_create_bookmark()
        self.assertEqual(new_bookmark, "merge-when-green-testuser")

        # Cleanup
        mgwg.delete_bookmark(new_bookmark)


if __name__ == "__main__":
    unittest.main(verbosity=2)
