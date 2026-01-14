#!/usr/bin/env python3
"""
jmt - Generate jj fix config from flake's treefmt formatter

Caches the formatter build (like flake-fmt) and generates jj fix configuration
from treefmt.toml, filtering out linters and tools that don't support stdin.
"""

import hashlib
import os
import re
import subprocess
import sys
from pathlib import Path

# Tools completely excluded from jj fix
EXCLUDED_TOOLS: set[str] = set()

# Linters: show warnings via pass-through (stderr), pass content unchanged (stdout)
PASSTHROUGH_LINTERS = {
    "shellcheck",
    "statix",
}

# Tools that need special stdin arguments
STDIN_ARGS = {
    "yamlfmt": ["-"],
    "keep-sorted": ["-"],
    "tofu": ["-"],      # tofu fmt -
    "terraform": ["-"], # terraform fmt -
}

# Tools that need wrapper scripts (no stdin support, but do modify files)
NEEDS_WRAPPER = {
    "deadnix",     # Requires file path, uses --edit
    "ruff-isort",  # ruff check --fix doesn't support stdin/stdout
}


def debug(msg: str) -> None:
    if os.environ.get("JMT_DEBUG"):
        print(f"[debug] {msg}", file=sys.stderr)


def find_flake_root() -> Path | None:
    """Find the nearest flake.nix by walking up."""
    cwd = Path.cwd()
    for parent in [cwd, *cwd.parents]:
        if (parent / "flake.nix").exists():
            return parent
    return None


def get_cache_dir() -> Path:
    """Get cache directory following XDG spec."""
    xdg_cache = os.environ.get("XDG_CACHE_HOME")
    if xdg_cache:
        base = Path(xdg_cache)
    else:
        base = Path.home() / ".cache"
    return base / "jmt"


def get_cache_path(flake_root: Path) -> Path:
    """Get cache path for this flake."""
    key = hashlib.sha256(str(flake_root).encode()).hexdigest()[:16]
    return get_cache_dir() / key


def needs_rebuild(flake_root: Path, cache_path: Path) -> bool:
    """Check if formatter needs to be rebuilt."""
    if os.environ.get("NO_CACHE"):
        debug("NO_CACHE set, forcing rebuild")
        return True

    if not cache_path.exists():
        debug("Cache doesn't exist")
        return True

    # Use lstat() to get symlink's own mtime (not the target in nix store)
    cache_mtime = cache_path.lstat().st_mtime

    # Check flake files
    for filename in ["flake.nix", "flake.lock"]:
        file_path = flake_root / filename
        if file_path.exists():
            file_mtime = file_path.stat().st_mtime
            if file_mtime > cache_mtime:
                debug(f"{filename} is newer than cache")
                return True

    # Check formatter directory (flake-module.nix etc.)
    formatter_dir = flake_root / "formatter"
    if formatter_dir.exists():
        for file_path in formatter_dir.glob("*.nix"):
            file_mtime = file_path.stat().st_mtime
            if file_mtime > cache_mtime:
                debug(f"{file_path.name} is newer than cache")
                return True

    debug("Cache is valid")
    return False


def get_system() -> str:
    """Get current Nix system."""
    result = subprocess.run(
        ["nix", "eval", "--raw", "--impure", "--expr", "builtins.currentSystem"],
        capture_output=True,
        text=True,
    )
    return result.stdout.strip() or "x86_64-linux"


def build_formatter(flake_root: Path, cache_path: Path) -> Path | None:
    """Build formatter and cache it."""
    system = get_system()
    attr = f".#formatter.{system}"

    cache_path.parent.mkdir(parents=True, exist_ok=True)

    print(f"Building formatter for {system}...", file=sys.stderr)
    result = subprocess.run(
        ["nix", "build", attr, "--out-link", str(cache_path)],
        cwd=flake_root,
    )

    if result.returncode != 0:
        print("Failed to build formatter", file=sys.stderr)
        return None

    return cache_path


def find_treefmt_config(formatter_path: Path) -> Path | None:
    """Extract treefmt.toml path from wrapper script."""
    wrapper = formatter_path / "bin" / "treefmt"
    if not wrapper.exists():
        # Try finding any executable
        bin_dir = formatter_path / "bin"
        if bin_dir.exists():
            for f in bin_dir.iterdir():
                if f.is_file():
                    wrapper = f
                    break

    if not wrapper.exists():
        return None

    content = wrapper.read_text()

    # Look for --config-file= pattern
    match = re.search(r"--config-file=([^\s]+)", content)
    if match:
        return Path(match.group(1))

    return None


def parse_treefmt_config(config_path: Path) -> dict:
    """Parse treefmt.toml and extract formatter info."""
    try:
        import tomllib
    except ImportError:
        import tomli as tomllib

    content = config_path.read_text()
    return tomllib.loads(content)


def glob_to_jj_pattern(pattern: str) -> str:
    """Convert treefmt include pattern to jj fix glob pattern."""
    # treefmt uses simple globs like "*.nix", jj fix needs "glob:'**/*.nix'"
    if pattern.startswith("**/"):
        return f"glob:'{pattern}'"
    elif pattern.startswith("*."):
        return f"glob:'**/{pattern}'"
    else:
        return f"glob:'{pattern}'"


def get_inline_command(name: str, command: str, options: list[str], mode: str) -> list[str]:
    """Generate inline bash -c command for tools that need wrapping.

    mode: "edit" (modify file) or "passthrough" (show warnings only)
    """
    # Filter options
    filtered_opts = [opt for opt in options if opt not in ["-w", "--write"]]
    opts_str = " ".join(f'"{opt}"' for opt in filtered_opts)

    # File extension for temp file
    ext_map = {
        "deadnix": ".nix",
        "statix": ".nix",
        "shellcheck": ".sh",
        "ruff-isort": ".py",
    }
    ext = ext_map.get(name, "")

    # Use JMT_MKTEMP env var for GNU-compatible mktemp (macOS compatibility)
    mktemp_cmd = os.environ.get("JMT_MKTEMP", "mktemp")

    if mode == "passthrough":
        # Linter: show warnings on stderr, pass content unchanged
        script = f't=$({mktemp_cmd} --suffix={ext}); cat >"$t"; {command} {opts_str} "$t" >&2 || true; cat "$t"; rm "$t"'
    else:
        # Editor: modify file and output result
        script = f't=$({mktemp_cmd} --suffix={ext}); cat >"$t"; {command} {opts_str} "$t" >/dev/null 2>&1 || true; cat "$t"; rm "$t"'

    return ["bash", "-c", script]


def get_stdin_command(name: str, command: str, options: list[str], wrapper_type: str | None = None) -> list[str]:
    """Get command with proper stdin arguments.

    wrapper_type: None, "edit", or "passthrough"
    """
    cmd_name = Path(command).name

    # Use inline bash for tools that need wrapping
    if wrapper_type == "edit" and name in NEEDS_WRAPPER:
        return get_inline_command(name, command, options, "edit")
    if wrapper_type == "passthrough" and name in PASSTHROUGH_LINTERS:
        return get_inline_command(name, command, options, "passthrough")

    # Filter out file-modifying options
    filtered_opts = [
        opt for opt in options
        if opt not in ["-w", "--write", "-e", "--edit", "--fix"]
    ]

    base_cmd = [command] + filtered_opts

    # Add stdin argument if needed
    if cmd_name in STDIN_ARGS:
        return base_cmd + STDIN_ARGS[cmd_name]

    # Special case for terraform/tofu fmt
    if "fmt" in filtered_opts and cmd_name in ("tofu", "terraform"):
        return base_cmd + ["-"]

    return base_cmd


def to_toml_array(items: list[str]) -> str:
    """Convert list to TOML array format."""
    escaped = []
    for item in items:
        # Escape backslashes and double quotes for TOML
        item = item.replace("\\", "\\\\").replace('"', '\\"')
        escaped.append(f'"{item}"')
    return "[" + ", ".join(escaped) + "]"


def generate_jj_config(treefmt_config: dict, only_tools: set[str] | None = None) -> str:
    """Generate jj fix configuration from treefmt config."""
    lines = ["# Generated by jmt", "# Do not edit manually", ""]

    formatters = treefmt_config.get("formatter", {})
    global_excludes = treefmt_config.get("global", {}).get("excludes", [])

    for name, config in sorted(formatters.items()):
        if name in EXCLUDED_TOOLS:
            debug(f"Skipping excluded tool: {name}")
            continue
        if only_tools is not None and name not in only_tools:
            debug(f"Skipping tool (not in --only): {name}")
            continue

        command = config.get("command", "")
        if not command:
            continue

        includes = config.get("includes", [])
        if not includes:
            continue

        options = config.get("options", [])
        excludes = config.get("excludes", [])

        # Determine wrapper type
        if name in NEEDS_WRAPPER:
            wrapper_type = "edit"
        elif name in PASSTHROUGH_LINTERS:
            wrapper_type = "passthrough"
        else:
            wrapper_type = None

        cmd = get_stdin_command(name, command, options, wrapper_type=wrapper_type)

        # Convert patterns with excludes
        patterns = []
        for inc in includes:
            base_pattern = glob_to_jj_pattern(inc)
            # Apply excludes using fileset difference operator
            all_excludes = excludes + global_excludes
            if all_excludes:
                exclude_patterns = " ~ ".join(glob_to_jj_pattern(e) for e in all_excludes)
                patterns.append(f"({base_pattern} ~ {exclude_patterns})")
            else:
                patterns.append(base_pattern)

        lines.append(f"[fix.tools.{name}]")
        lines.append(f"command = {to_toml_array(cmd)}")
        lines.append(f"patterns = {to_toml_array(patterns)}")
        lines.append("")

    return "\n".join(lines)


def get_jj_repo_path(flake_root: Path) -> Path | None:
    """Get the actual jj repo path, handling worktrees."""
    jj_dir = flake_root / ".jj"
    if not jj_dir.exists():
        return None

    repo_path = jj_dir / "repo"

    # In worktrees, .jj/repo is a file containing the path to the actual repo
    if repo_path.is_file():
        actual_path = Path(repo_path.read_text().strip())
        if actual_path.exists():
            return actual_path
        return None

    # In normal repos, .jj/repo is a directory
    if repo_path.is_dir():
        return repo_path

    return None


def write_jj_config(config: str, flake_root: Path) -> bool:
    """Write config to .jj/repo/config.toml."""
    repo_path = get_jj_repo_path(flake_root)
    if not repo_path:
        print(f"Not a jj repository: {flake_root}", file=sys.stderr)
        return False

    jj_config = repo_path / "config.toml"

    # Read existing config if any
    existing = ""
    if jj_config.exists():
        existing = jj_config.read_text()

    # Remove old generated section
    marker = "# Generated by jmt"
    if marker in existing:
        start_idx = existing.index(marker)
        rest = existing[start_idx:]
        end_match = re.search(r"\n\[(?!fix\.tools\.)", rest)
        if end_match:
            end_idx = start_idx + end_match.start()
            existing = existing[:start_idx] + existing[end_idx:]
        else:
            existing = existing[:start_idx]

    # Append new config
    new_content = existing.rstrip() + "\n\n" + config if existing.strip() else config

    jj_config.write_text(new_content)
    print(f"Written to {jj_config}", file=sys.stderr)
    return True


def run_jj_fix(flake_root: Path, extra_args: list[str] | None = None) -> int:
    """Run jj fix with optional extra arguments."""
    cmd = ["jj", "fix"] + (extra_args or [])
    print(f"Running {' '.join(cmd)}...", file=sys.stderr)
    result = subprocess.run(cmd, cwd=flake_root)
    return result.returncode


def list_tools(treefmt_config: dict) -> None:
    """List available formatter tools."""
    formatters = treefmt_config.get("formatter", {})
    print("Available tools:")
    for name, config in sorted(formatters.items()):
        if name in EXCLUDED_TOOLS:
            continue
        includes = config.get("includes", [])
        # Show tool name with patterns (not /nix/store paths)
        patterns = ", ".join(includes[:3])
        if len(includes) > 3:
            patterns += f", ... (+{len(includes) - 3})"
        status = ""
        if name in PASSTHROUGH_LINTERS:
            status = " [linter]"
        elif name in NEEDS_WRAPPER:
            status = " [wrapper]"
        print(f"  {name}{status}: {patterns}")


def parse_args() -> tuple[list[str], list[str]]:
    """Parse arguments, splitting on -- for jj fix args."""
    args = sys.argv[1:]
    if "--" in args:
        idx = args.index("--")
        return args[:idx], args[idx + 1:]
    return args, []


def main() -> int:
    jmt_args, jj_args = parse_args()
    print_only = "--print" in jmt_args
    sync_only = "--sync" in jmt_args
    list_only = "--list" in jmt_args
    only_tools: set[str] | None = None

    # Parse --only option
    for arg in jmt_args:
        if arg.startswith("--only="):
            only_tools = set(arg[7:].split(","))
        elif arg == "--only":
            idx = jmt_args.index(arg)
            if idx + 1 < len(jmt_args):
                only_tools = set(jmt_args[idx + 1].split(","))

    flake_root = find_flake_root()
    if not flake_root:
        print("Not in a flake directory", file=sys.stderr)
        return 1

    debug(f"Flake root: {flake_root}")

    cache_path = get_cache_path(flake_root)
    debug(f"Cache path: {cache_path}")

    # Build if needed
    if needs_rebuild(flake_root, cache_path):
        if not build_formatter(flake_root, cache_path):
            return 1
    else:
        print("Using cached formatter", file=sys.stderr)

    # Find treefmt config
    config_path = find_treefmt_config(cache_path)
    if not config_path:
        print("Could not find treefmt config", file=sys.stderr)
        return 1

    debug(f"Treefmt config: {config_path}")

    # Parse and generate
    treefmt_config = parse_treefmt_config(config_path)

    # List mode
    if list_only:
        list_tools(treefmt_config)
        return 0

    jj_config = generate_jj_config(treefmt_config, only_tools)

    # Output modes
    if print_only:
        print(jj_config)
        return 0

    if not write_jj_config(jj_config, flake_root):
        return 1

    # Run jj fix unless --sync
    if not sync_only:
        return run_jj_fix(flake_root, jj_args if jj_args else None)

    print("Done!", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
