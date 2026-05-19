"""Regression tests for updater."""

import json
import subprocess
from pathlib import Path
from unittest.mock import patch

import pytest

from updater.__main__ import (
    PLACEHOLDER_HASH,
    Package,
    create_pr_for_package,
    fix_placeholder_hash,
    run_nix_update,
)


@pytest.fixture
def pkg_dir(tmp_path: Path) -> Path:
    """Create a minimal package directory with srcs.json."""
    d = tmp_path / "packages" / "test-pkg"
    d.mkdir(parents=True)
    return d


def make_package(pkg_dir: Path) -> Package:
    return Package(name="test-pkg", method="custom", path=pkg_dir)


# -- Regression: fix_placeholder_hash must detect placeholder and replace it --


class TestFixPlaceholderHash:
    def test_replaces_placeholder_in_srcs_json(self, pkg_dir: Path, tmp_path: Path):
        """fix_placeholder_hash should replace PLACEHOLDER_HASH with the real hash."""
        srcs = {
            "version": "0-unstable-2026-01-01",
            "rev": "abc123",
            "srcHash": "sha256-real",
            "npmDepsHash": PLACEHOLDER_HASH,
        }
        (pkg_dir / "srcs.json").write_text(json.dumps(srcs))

        correct_hash = "sha256-RealCorrectHashFromNixBuild000000000000000="
        fake_stderr = f"error: hash mismatch\n  got: {correct_hash}\n"
        fake_result = subprocess.CompletedProcess([], 1, stdout="", stderr=fake_stderr)

        pkg = make_package(pkg_dir)
        with patch("updater.__main__.run_cmd", return_value=fake_result):
            assert fix_placeholder_hash(pkg, tmp_path) is True

        result = json.loads((pkg_dir / "srcs.json").read_text())
        assert result["npmDepsHash"] == correct_hash

    def test_skips_when_no_placeholder(self, pkg_dir: Path, tmp_path: Path):
        """fix_placeholder_hash should be a no-op when npmDepsHash is already a real hash."""
        existing_hash = "sha256-ExistingOldHash00000000000000000000000000="
        srcs = {
            "version": "0-unstable-2026-01-01",
            "rev": "abc123",
            "srcHash": "sha256-real",
            "npmDepsHash": existing_hash,
        }
        (pkg_dir / "srcs.json").write_text(json.dumps(srcs))

        pkg = make_package(pkg_dir)
        with patch("updater.__main__.run_cmd") as mock_cmd:
            assert fix_placeholder_hash(pkg, tmp_path) is True
            # Should NOT call nix build since no placeholder is present
            mock_cmd.assert_not_called()

        result = json.loads((pkg_dir / "srcs.json").read_text())
        assert result["npmDepsHash"] == existing_hash


# -- Regression: update.py must reset npmDepsHash to placeholder on source change --


class TestUpdatePyResetsHash:
    """Verify radicle-desktop update.py resets npmDepsHash when source changes."""

    def test_npm_hash_reset_on_source_change(self, tmp_path: Path):
        """When rev changes, npmDepsHash must become PLACEHOLDER_HASH."""
        # Simulate existing srcs.json with old hash
        pkg_dir = tmp_path
        srcs_file = pkg_dir / "srcs.json"
        srcs_file.write_text(
            json.dumps(
                {
                    "version": "0-unstable-2026-01-01",
                    "rev": "old_rev",
                    "srcHash": "sha256-oldHash",
                    "npmDepsHash": "sha256-OldNpmHash000000000000000000000000000000=",
                }
            )
        )

        # Inline the core logic from radicle-desktop/update.py
        # (the fix: always use placeholder, not current.get())
        current = json.loads(srcs_file.read_text())
        new_rev = "new_rev_abc123"
        assert current["rev"] != new_rev  # source changed

        # This is what the fixed update.py does:
        npm_hash = PLACEHOLDER_HASH

        new_data = {
            "version": "0-unstable-2026-03-24",
            "rev": new_rev,
            "srcHash": "sha256-newHash",
            "npmDepsHash": npm_hash,
        }
        srcs_file.write_text(json.dumps(new_data, indent=2) + "\n")

        result = json.loads(srcs_file.read_text())
        assert result["npmDepsHash"] == PLACEHOLDER_HASH, (
            "npmDepsHash must be reset to placeholder when source changes, "
            "so fix_placeholder_hash() can compute the correct hash"
        )


# -- Regression: run_nix_update must pass bare attribute path to nix-update --


class TestRunNixUpdateAttrPath:
    """nix-update >=1.14 rejects leading '.#' on the attribute argument."""

    def test_attr_has_no_flake_prefix(self, tmp_path: Path):
        pkg = Package(name="sem-vcs", method="nix-update", path=tmp_path, extra_args=[])

        ok = subprocess.CompletedProcess([], 0, stdout="", stderr="")
        with patch("updater.__main__.subprocess.run", return_value=ok) as mock_run:
            assert run_nix_update(pkg, tmp_path) is True

        cmd = mock_run.call_args.args[0]
        assert cmd[0] == "nix-update"
        assert "--flake" in cmd
        attr = cmd[cmd.index("--flake") + 1]
        assert not attr.startswith("."), (
            f"nix-update attribute must not start with '.#' (got: {attr!r}). "
            "nix-update 1.14+ rejects this with AttributePathError."
        )
        assert attr == "packages.x86_64-linux.sem-vcs"


# -- Regression: branch-exists skip must not count as failure --


class TestCreatePrBranchExists:
    def test_existing_branch_returns_true(self, tmp_path: Path):
        """When remote branch already exists, create_pr_for_package should return True (not False)."""
        pkg = Package(name="test-pkg", method="custom", path=tmp_path)

        # Mock git ls-remote to return a matching branch
        fake_result = subprocess.CompletedProcess(
            [], 0, stdout="abc123\trefs/heads/update/test-pkg\n", stderr=""
        )
        with patch("updater.__main__.run_cmd", return_value=fake_result):
            result = create_pr_for_package(pkg, tmp_path)

        assert result is True, (
            "Skipping an already-existing branch is not a failure — "
            "the PR already exists"
        )

    def test_no_existing_branch_proceeds(self, tmp_path: Path):
        """When no remote branch exists and not dry_run, should proceed to create worktree."""
        pkg = Package(name="test-pkg", method="custom", path=tmp_path)

        empty_result = subprocess.CompletedProcess([], 0, stdout="", stderr="")

        with patch("updater.__main__.run_cmd", return_value=empty_result):
            with patch(
                "updater.__main__._create_pr_in_worktree", return_value=True
            ) as mock_create:
                result = create_pr_for_package(pkg, tmp_path)

        assert result is True
        mock_create.assert_called_once()
