"""Regression tests for updater."""

import importlib.util
import json
import subprocess
from pathlib import Path
from unittest.mock import Mock, patch

import pytest

from updater.__main__ import (
    PLACEHOLDER_HASH,
    Package,
    create_pr_for_package,
    fix_placeholder_hash,
    run_custom_update,
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


# -- Regression: radicle-desktop update.py must match the DMG package schema --


def load_radicle_update_module():
    update_script = (
        Path(__file__).resolve().parents[1] / "radicle-desktop" / "update.py"
    )
    spec = importlib.util.spec_from_file_location(
        "test_radicle_desktop_update", update_script
    )
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class TestRadicleDesktopUpdatePy:
    """Verify radicle-desktop update.py writes the fetchurl DMG schema."""

    def test_writes_version_url_hash_without_npm_placeholder(
        self, tmp_path: Path, monkeypatch
    ):
        srcs_file = tmp_path / "srcs.json"
        srcs_file.write_text(
            json.dumps(
                {
                    "version": "0.10.0",
                    "url": "https://example.invalid/radicle-desktop-0.10.0-aarch64.dmg",
                    "hash": "sha256-old",
                }
            )
        )

        module = load_radicle_update_module()
        module.__file__ = str(tmp_path / "update.py")
        mirror_url = "https://github.com/mulatta/dots/releases/download/radicle-desktop-mirror/radicle-desktop-0.11.0-aarch64.dmg"
        mirror_hash = "sha256-newDmgHash0000000000000000000000000000000="

        monkeypatch.setattr(
            module,
            "get_latest_version",
            lambda: {"version": "0.11.0", "sha": "b02c1556"},
            raising=False,
        )
        monkeypatch.setattr(
            module,
            "mirror_to_github",
            lambda version, sha: mirror_url,
            raising=False,
        )
        monkeypatch.setattr(
            module, "get_nix_hash", lambda url: mirror_hash, raising=False
        )
        monkeypatch.setattr(
            module,
            "get_latest_commit",
            lambda: ("b02c1556", 1779451373),
            raising=False,
        )
        monkeypatch.setattr(
            module, "nix_prefetch_git", lambda url, rev: "sha256-src", raising=False
        )

        module.main()

        result = json.loads(srcs_file.read_text())
        assert result == {"version": "0.11.0", "url": mirror_url, "hash": mirror_hash}
        assert PLACEHOLDER_HASH not in srcs_file.read_text()

    def test_skips_when_latest_version_matches_current(
        self, tmp_path: Path, monkeypatch
    ):
        srcs_file = tmp_path / "srcs.json"
        current = {
            "version": "0.11.0",
            "url": "https://example.invalid/radicle-desktop-0.11.0-aarch64.dmg",
            "hash": "sha256-current",
        }
        srcs_file.write_text(json.dumps(current, indent=2) + "\n")

        module = load_radicle_update_module()
        module.__file__ = str(tmp_path / "update.py")
        mirror_to_github = Mock()
        get_nix_hash = Mock()

        monkeypatch.setattr(
            module,
            "get_latest_version",
            lambda: {"version": "0.11.0", "sha": "b02c1556"},
            raising=False,
        )
        monkeypatch.setattr(module, "mirror_to_github", mirror_to_github, raising=False)
        monkeypatch.setattr(module, "get_nix_hash", get_nix_hash, raising=False)

        module.main()

        assert json.loads(srcs_file.read_text()) == current
        mirror_to_github.assert_not_called()
        get_nix_hash.assert_not_called()


# -- Regression: run_nix_update must pass bare attribute path to nix-update --


class TestRunNixUpdateAttrPath:
    """nix-update >=1.14 rejects leading '.#' on the attribute argument."""

    def test_attr_has_no_flake_prefix(self, tmp_path: Path):
        pkg = Package(
            name="example-pkg", method="nix-update", path=tmp_path, extra_args=[]
        )

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
        assert attr == "packages.x86_64-linux.example-pkg"


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


# -- Regression: a child update.py parsing argparse must not see the parent's
# argv, and its SystemExit must not abort the whole run. rsshub/update.py uses
# argparse; when imported it parsed the updater's sys.argv (`--pr`), which
# argparse rejected with sys.exit(2) — SystemExit is BaseException, escaped the
# except Exception guard, and crashed the scheduled job with exit code 2. --


class TestRunCustomUpdateArgvIsolation:
    def _write_update_py(self, pkg_dir: Path, body: str) -> None:
        (pkg_dir / "update.py").write_text(body)

    def test_argparse_child_does_not_see_parent_argv(self, pkg_dir: Path, monkeypatch):
        """An update.py using argparse must not inherit the updater's argv."""
        self._write_update_py(
            pkg_dir,
            "import argparse\n"
            "def main():\n"
            "    p = argparse.ArgumentParser()\n"
            "    p.add_argument('--check', action='store_true')\n"
            "    p.parse_args()\n",
        )
        # Simulate the updater being invoked as `updater --pr`.
        monkeypatch.setattr("sys.argv", ["updater", "--pr"])

        assert run_custom_update(make_package(pkg_dir)) is True

    def test_child_systemexit_does_not_propagate(self, pkg_dir: Path):
        """A SystemExit inside update.py is a per-package failure, not a crash."""
        self._write_update_py(
            pkg_dir,
            "def main():\n    raise SystemExit('boom')\n",
        )
        # Must return False (failure) rather than raising out of the loop.
        assert run_custom_update(make_package(pkg_dir)) is False
