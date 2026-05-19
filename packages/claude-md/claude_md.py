#!/usr/bin/env python3
"""Manage CLAUDE.local.md and .claude/ directories across repositories.

Centralizes project-level Claude Code configurations into a single
repository for version control, creating symlinks back to each project.
"""

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

CENTRAL_REPO_ENV = "CLAUDE_MD_REPO"
CENTRAL_REPO_DEFAULT = Path.home() / "git" / "claude-md"


def get_central_repo() -> Path:
    """Get the central claude-md repository path."""
    return Path(os.environ.get(CENTRAL_REPO_ENV, CENTRAL_REPO_DEFAULT))


def get_repo_root() -> Path:
    """Get the root of the current repository (jj or git)."""
    # Try jj first
    try:
        result = subprocess.run(
            ["jj", "workspace", "root"],
            capture_output=True,
            text=True,
            check=True,
        )
        return Path(result.stdout.strip())
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass

    # Fallback to git
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            check=True,
        )
        return Path(result.stdout.strip())
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("Error: not in a jj or git repository", file=sys.stderr)
        sys.exit(1)


def track_files(repo_path: Path, files: list[Path]) -> None:
    """Track files in the central repo (jj or git)."""
    jj_dir = repo_path / ".jj"
    relative_files = [str(f.relative_to(repo_path)) for f in files]

    if jj_dir.exists():
        subprocess.run(
            ["jj", "file", "track"] + relative_files,
            cwd=repo_path,
            check=False,
        )
    else:
        subprocess.run(
            ["git", "add", "-f"] + relative_files,
            cwd=repo_path,
            check=False,
        )


def show_diff(file1: Path, file2: Path) -> None:
    """Show diff between two files."""
    result = subprocess.run(
        ["diff", "-u", str(file1), str(file2)],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.stdout:
        print(result.stdout)


def ensure_central_repo(central: Path) -> None:
    """Ensure the central repository exists."""
    if not central.exists():
        central.mkdir(parents=True, exist_ok=True)
        subprocess.run(["jj", "init"], cwd=central, check=True)
        print(f"Initialized central repo: {central}")


def handle_path(local: Path, central: Path, central_repo: Path) -> None:
    """Handle a single file or directory: centralize and symlink."""
    # Already symlinked correctly
    if local.is_symlink() and local.resolve() == central.resolve():
        print(f"  already linked: {local.name}")
        return

    # Both exist — conflict
    if local.exists() and not local.is_symlink() and central.exists():
        print(f"  conflict: both exist", file=sys.stderr)
        if local.is_file() and central.is_file():
            show_diff(local, central)
        sys.exit(1)

    # Central exists, local doesn't — create symlink
    if central.exists() and not local.exists():
        local.symlink_to(central)
        print(f"  linked: {local.name} -> central")
        return

    # Local exists, central doesn't — move to central and symlink
    if local.exists() and not central.exists():
        central.parent.mkdir(parents=True, exist_ok=True)
        if local.is_dir():
            shutil.copytree(local, central)
            shutil.rmtree(local)
        else:
            shutil.copy2(local, central)
            local.unlink()
        local.symlink_to(central)
        track_files(central_repo, [central])
        print(f"  centralized: {local.name}")
        return

    # Neither exists
    print(f"  skipped: {local.name} (not found)")


def add_command(args: argparse.Namespace) -> None:
    """Centralize CLAUDE.local.md and .claude/ for current repository."""
    repo_root = get_repo_root()
    repo_name = repo_root.name
    central_repo = get_central_repo()

    ensure_central_repo(central_repo)

    print(f"Repository: {repo_name}")
    print(f"Central:    {central_repo / repo_name}")

    central_dir = central_repo / repo_name

    # Handle .claude/ directory
    handle_path(
        repo_root / ".claude",
        central_dir / ".claude",
        central_repo,
    )

    # Handle CLAUDE.local.md
    handle_path(
        repo_root / "CLAUDE.local.md",
        central_dir / "CLAUDE.local.md",
        central_repo,
    )


def list_command(args: argparse.Namespace) -> None:
    """List all managed repositories."""
    central_repo = get_central_repo()
    if not central_repo.exists():
        print("No central repo found.")
        return

    for entry in sorted(central_repo.iterdir()):
        if entry.is_dir() and not entry.name.startswith("."):
            files = [f.name for f in entry.iterdir()]
            print(f"  {entry.name}: {', '.join(files)}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Manage CLAUDE.local.md files across repositories"
    )
    subparsers = parser.add_subparsers(dest="command", help="Available commands")

    subparsers.add_parser(
        "add", help="Centralize CLAUDE.local.md and .claude/ for current repo"
    )
    subparsers.add_parser("list", help="List all managed repositories")

    args = parser.parse_args()

    if args.command == "add":
        add_command(args)
    elif args.command == "list":
        list_command(args)
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
