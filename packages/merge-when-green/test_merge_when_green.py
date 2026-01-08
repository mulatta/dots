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

        # Initialize jj repo
        os.chdir(cls.test_dir)
        subprocess.run(["jj", "git", "init"], check=True, capture_output=True)

        # Configure jj user
        subprocess.run(
            ["jj", "config", "set", "--repo", "user.name", "Test User"],
            check=True, capture_output=True
        )
        subprocess.run(
            ["jj", "config", "set", "--repo", "user.email", "test@example.com"],
            check=True, capture_output=True
        )

        # Create initial commit
        Path("README.md").write_text("# Test Repo\n")
        subprocess.run(["jj", "commit", "-m", "Initial commit"], check=True, capture_output=True)

    @classmethod
    def tearDownClass(cls):
        """Clean up temporary repository."""
        os.chdir(cls.orig_dir)
        shutil.rmtree(cls.test_dir, ignore_errors=True)

    def setUp(self):
        """Ensure we're in the test directory."""
        os.chdir(self.test_dir)

    def test_get_current_bookmark_none(self):
        """Test get_current_bookmark when no bookmark exists."""
        result = mgwg.get_current_bookmark()
        self.assertIsNone(result)

    def test_create_bookmark(self):
        """Test creating a bookmark from commit message."""
        # Create a commit with a descriptive message
        Path("feature.txt").write_text("new feature\n")
        subprocess.run(
            ["jj", "commit", "-m", "feat(auth): add login feature"],
            check=True, capture_output=True
        )

        # Create bookmark for current commit
        bookmark = mgwg.create_bookmark()

        # Verify bookmark was created
        result = subprocess.run(
            ["jj", "bookmark", "list"],
            capture_output=True, text=True
        )
        self.assertIn(bookmark, result.stdout)

        # Cleanup
        subprocess.run(["jj", "bookmark", "delete", bookmark], check=False, capture_output=True)

    def test_create_bookmark_with_name(self):
        """Test creating a bookmark with explicit name."""
        bookmark_name = "test-explicit-bookmark"
        bookmark = mgwg.create_bookmark(bookmark_name)

        self.assertEqual(bookmark, bookmark_name)

        # Verify bookmark exists
        result = subprocess.run(
            ["jj", "bookmark", "list"],
            capture_output=True, text=True
        )
        self.assertIn(bookmark_name, result.stdout)

        # Cleanup
        subprocess.run(["jj", "bookmark", "delete", bookmark_name], check=False, capture_output=True)

    def test_get_current_bookmark_exists(self):
        """Test get_current_bookmark when bookmark exists."""
        # Create a bookmark on current commit
        bookmark_name = "test-bookmark-exists"
        subprocess.run(
            ["jj", "bookmark", "create", bookmark_name],
            check=True, capture_output=True
        )

        result = mgwg.get_current_bookmark()
        self.assertEqual(result, bookmark_name)

        # Cleanup
        subprocess.run(["jj", "bookmark", "delete", bookmark_name], check=False, capture_output=True)

    def test_has_changes_no_changes(self):
        """Test has_changes when there are no changes."""
        # Create a "main" bookmark to simulate origin
        subprocess.run(
            ["jj", "bookmark", "create", "main"],
            check=False, capture_output=True
        )

        # Mock main@origin by checking against main
        with patch.object(mgwg, 'has_changes') as mock_has_changes:
            mock_has_changes.return_value = False
            result = mock_has_changes("main")
            self.assertFalse(result)

    def test_has_changes_with_changes(self):
        """Test has_changes when there are changes."""
        # Create new commit
        Path("new_file.txt").write_text("content\n")
        subprocess.run(
            ["jj", "commit", "-m", "add new file"],
            check=True, capture_output=True
        )

        # This should detect changes
        with patch.object(mgwg, 'has_changes') as mock_has_changes:
            mock_has_changes.return_value = True
            result = mock_has_changes("main")
            self.assertTrue(result)

    def test_delete_bookmark(self):
        """Test deleting a bookmark."""
        bookmark_name = "test-delete-bookmark"
        subprocess.run(
            ["jj", "bookmark", "create", bookmark_name],
            check=True, capture_output=True
        )

        # Delete it
        mgwg.delete_bookmark(bookmark_name)

        # Verify it's gone
        result = subprocess.run(
            ["jj", "bookmark", "list"],
            capture_output=True, text=True
        )
        self.assertNotIn(bookmark_name, result.stdout)


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

    def test_get_target_revision_changes_no_description_error(self):
        """Test get_target_revision raises error when @ has changes but no description."""
        with patch.object(mgwg, 'get_description', return_value=""):
            with patch.object(mgwg, 'is_commit_empty', return_value=False):
                with self.assertRaises(mgwg.TargetRevisionError):
                    mgwg.get_target_revision(title_provided=False)

    def test_get_target_revision_changes_no_description_with_title(self):
        """Test get_target_revision allows @ with changes but no description if title provided."""
        with patch.object(mgwg, 'get_description', return_value=""):
            with patch.object(mgwg, 'is_commit_empty', return_value=False):
                result = mgwg.get_target_revision(title_provided=True)
                self.assertEqual(result, "@")

    def test_is_commit_empty_true(self):
        """Test is_commit_empty returns True for empty commit."""
        with patch.object(mgwg, 'run') as mock_run:
            mock_run.return_value = MagicMock(stdout="true", returncode=0)
            result = mgwg.is_commit_empty("@")
            self.assertTrue(result)

    def test_is_commit_empty_false(self):
        """Test is_commit_empty returns False for non-empty commit."""
        with patch.object(mgwg, 'run') as mock_run:
            mock_run.return_value = MagicMock(stdout="false", returncode=0)
            result = mgwg.is_commit_empty("@")
            self.assertFalse(result)

    def test_get_description(self):
        """Test get_description returns commit description."""
        with patch.object(mgwg, 'run') as mock_run:
            mock_run.return_value = MagicMock(stdout="feat: my feature\n", returncode=0)
            result = mgwg.get_description("@")
            self.assertEqual(result, "feat: my feature")


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
            mock_run.return_value = MagicMock(
                stdout="main\n",
                returncode=0
            )
            result = mgwg.get_default_branch()
            self.assertEqual(result, "main")

    def test_get_default_branch_fallback(self):
        """Test get_default_branch fallback when gh fails."""
        with patch.object(mgwg, 'run') as mock_run:
            mock_run.return_value = MagicMock(
                stdout="",
                returncode=1
            )
            result = mgwg.get_default_branch()
            self.assertEqual(result, "main")

    def test_pr_exists_true(self):
        """Test pr_exists when PR exists."""
        with patch.object(mgwg, 'run') as mock_run:
            mock_run.return_value = MagicMock(
                stdout='{"state": "OPEN"}',
                returncode=0
            )
            result = mgwg.pr_exists("test-branch")
            self.assertTrue(result)

    def test_pr_exists_false_closed(self):
        """Test pr_exists when PR is closed."""
        with patch.object(mgwg, 'run') as mock_run:
            mock_run.return_value = MagicMock(
                stdout='{"state": "CLOSED"}',
                returncode=0
            )
            result = mgwg.pr_exists("test-branch")
            self.assertFalse(result)

    def test_pr_exists_false_not_found(self):
        """Test pr_exists when PR doesn't exist."""
        with patch.object(mgwg, 'run') as mock_run:
            mock_run.return_value = MagicMock(
                stdout="",
                returncode=1
            )
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

        self.assertEqual(passed, 2)  # SUCCESS CheckRun + SUCCESS StatusContext
        self.assertEqual(failed, 1)  # FAILURE CheckRun
        self.assertEqual(pending, 2)  # IN_PROGRESS CheckRun + PENDING StatusContext

    def test_get_pr_status_success(self):
        """Test get_pr_status with successful response."""
        mock_response = {
            "state": "OPEN",
            "mergeable": "MERGEABLE",
            "autoMergeRequest": {"enabledAt": "2024-01-01"},
            "statusCheckRollup": []
        }

        with patch.object(mgwg, 'run') as mock_run:
            mock_run.return_value = MagicMock(
                stdout=__import__('json').dumps(mock_response),
                returncode=0
            )
            result = mgwg.get_pr_status("test-branch")
            self.assertEqual(result["state"], "OPEN")
            self.assertIsNotNone(result["autoMergeRequest"])

    def test_get_pr_status_failure(self):
        """Test get_pr_status when gh fails."""
        with patch.object(mgwg, 'run') as mock_run:
            mock_run.return_value = MagicMock(
                stdout="",
                returncode=1
            )
            result = mgwg.get_pr_status("test-branch")
            self.assertIsNone(result)


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
        self.assertTrue(mgwg.Colors.RESET.startswith("\033["))


class TestIntegration(unittest.TestCase):
    """Integration tests with temporary repository."""

    @classmethod
    def setUpClass(cls):
        """Create a more complete test environment."""
        cls.test_dir = tempfile.mkdtemp(prefix="mgwg-integration-")
        cls.orig_dir = os.getcwd()

        os.chdir(cls.test_dir)

        # Initialize jj repo with git backend
        subprocess.run(["jj", "git", "init"], check=True, capture_output=True)
        subprocess.run(
            ["jj", "config", "set", "--repo", "user.name", "Test"],
            check=True, capture_output=True
        )
        subprocess.run(
            ["jj", "config", "set", "--repo", "user.email", "test@test.com"],
            check=True, capture_output=True
        )

        # Create initial structure
        Path("README.md").write_text("# Project\n")
        subprocess.run(["jj", "commit", "-m", "init"], check=True, capture_output=True)

        # Create main bookmark
        subprocess.run(["jj", "bookmark", "create", "main"], check=True, capture_output=True)

    @classmethod
    def tearDownClass(cls):
        os.chdir(cls.orig_dir)
        shutil.rmtree(cls.test_dir, ignore_errors=True)

    def setUp(self):
        os.chdir(self.test_dir)

    def test_full_bookmark_workflow(self):
        """Test complete bookmark creation workflow."""
        # Create a feature using jj new (keeps description on @)
        subprocess.run(
            ["jj", "new", "-m", "feat: add feature"],
            check=True, capture_output=True
        )
        Path("feature.py").write_text("# feature\n")

        # Initially no bookmark
        bookmark = mgwg.get_current_bookmark()
        self.assertIsNone(bookmark)

        # Create bookmark (should use @ since it has description)
        new_bookmark = mgwg.create_bookmark()
        self.assertIsNotNone(new_bookmark)
        self.assertIn("feat", new_bookmark)

        # Now bookmark exists
        found_bookmark = mgwg.get_current_bookmark()
        self.assertEqual(found_bookmark, new_bookmark)

        # Delete bookmark
        mgwg.delete_bookmark(new_bookmark)
        self.assertIsNone(mgwg.get_current_bookmark())

    def test_bookmark_on_parent_after_commit(self):
        """Test that bookmark is created on @- after jj commit."""
        # Use jj commit which leaves @ empty
        Path("another.py").write_text("# another\n")
        subprocess.run(
            ["jj", "commit", "-m", "fix: another fix"],
            check=True, capture_output=True
        )

        # @ is now empty, but @- has the commit
        # create_bookmark should use @-
        new_bookmark = mgwg.create_bookmark()
        self.assertIn("fix", new_bookmark)

        # Cleanup
        mgwg.delete_bookmark(new_bookmark)


if __name__ == "__main__":
    unittest.main(verbosity=2)
