#!/usr/bin/env python3
"""Profile-aware wrapper for OMP."""

from __future__ import annotations

import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

import yaml

DEFAULT_PASSTHROUGH_COMMANDS = {
    "agents",
    "aliases",
    "auth-broker",
    "auth-gateway",
    "banner",
    "complete",
    "config",
    "cost",
    "dry-balance",
    "gen-completion",
    "init",
    "install",
    "join",
    "models",
    "plugin",
    "read",
    "say",
    "search",
    "setup",
    "shell",
    "ssh",
    "stats",
    "tiny-models",
    "token",
    "ttsr",
    "update",
    "usage",
    "worktree",
}

TOOL_ENV_KEYS = [
    "ANTHROPIC_API_KEY",
    "ANTHROPIC_OAUTH_TOKEN",
    "OPENAI_API_KEY",
    "GEMINI_API_KEY",
    "XAI_API_KEY",
    "OPENROUTER_API_KEY",
    "PERPLEXITY_API_KEY",
    "BRAVE_API_KEY",
    "TAVILY_API_KEY",
    "EXA_API_KEY",
]


def profiles_dir() -> Path:
    raw = os.environ.get("OMP_PROFILES_DIR", "~/.omp/profiles")
    return Path(os.path.expandvars(raw)).expanduser()


def expand_path(raw: str | os.PathLike[str]) -> Path:
    return Path(os.path.expandvars(str(raw))).expanduser()


def expand_str(raw: str) -> str:
    expanded = os.path.expandvars(raw)
    if expanded.startswith("~"):
        return str(Path(expanded).expanduser())
    return expanded


def parse_profile_arg(args: list[str]) -> tuple[str | None, list[str]]:
    remaining: list[str] = []
    profile: str | None = None
    index = 0
    while index < len(args):
        arg = args[index]
        if arg == "--profile" and index + 1 < len(args):
            profile = args[index + 1]
            index += 2
            continue
        if arg.startswith("--profile="):
            profile = arg.split("=", 1)[1]
            index += 1
            continue
        remaining.append(arg)
        index += 1
    return profile, remaining


def select_profile(args: list[str]) -> tuple[str | None, list[str], Path | None]:
    explicit, remaining = parse_profile_arg(args)
    if explicit:
        path = profiles_dir() / f"{explicit}.yml"
        return explicit, remaining, path

    env_profile = os.environ.get("OMP_PROFILE")
    if env_profile:
        path = profiles_dir() / f"{env_profile}.yml"
        if path.exists():
            return env_profile, remaining, path

    default = profiles_dir() / "default.yml"
    if default.exists():
        return "default", remaining, default
    return None, args, None


def load_profile(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        data = yaml.safe_load(handle) or {}
    if not isinstance(data, dict):
        raise ValueError(f"profile must be a mapping: {path}")
    return data


def first_command(args: list[str]) -> str | None:
    if not args:
        return None
    return args[0] if not args[0].startswith("-") else None


def is_passthrough(profile: dict[str, Any], args: list[str]) -> bool:
    command = first_command(args)
    if command is None:
        return False
    commands = set(profile.get("passthroughCommands") or [])
    if profile.get("defaultPassthroughCommands", True):
        commands |= DEFAULT_PASSTHROUGH_COMMANDS
    return command in commands


def ensure_dirs(paths: list[str]) -> None:
    for raw in paths:
        expand_path(raw).mkdir(parents=True, exist_ok=True)


def build_env(profile: dict[str, Any]) -> dict[str, str]:
    env = os.environ.copy()
    home = Path.home()

    tool_paths = [expand_str(str(path)) for path in profile.get("toolPath") or []]
    if tool_paths:
        env["PATH"] = os.pathsep.join([*tool_paths, env.get("PATH", "")])

    for key, value in (profile.get("env") or {}).items():
        env[str(key)] = expand_str(str(value))

    env.setdefault("XDG_DATA_HOME", str(home / ".local/share"))
    env.setdefault("XDG_CACHE_HOME", str(home / ".cache"))
    env.setdefault("XDG_CONFIG_HOME", str(home / ".config"))

    agent_dir = profile.get("agentDir")
    if agent_dir:
        env["PI_CODING_AGENT_DIR"] = str(expand_path(agent_dir))

    return env


def runtime_dir(profile_name: str, profile: dict[str, Any]) -> Path:
    raw = profile.get("runtimeDir") or f"~/.cache/omp/profiles/{profile_name}/runtime"
    path = expand_path(raw)
    path.mkdir(parents=True, exist_ok=True)
    return path


def write_runtime_config(profile_name: str, profile: dict[str, Any]) -> Path | None:
    config = profile.get("config")
    if not config:
        return None
    path = runtime_dir(profile_name, profile) / "config.yml"
    path.write_text(yaml.safe_dump(config, sort_keys=False), encoding="utf-8")
    return path


def write_runtime_prompt(profile_name: str, profile: dict[str, Any]) -> Path | None:
    prompt = profile.get("prompt") or {}
    if not prompt:
        return None

    parts: list[str] = []
    text = prompt.get("text")
    if text:
        parts.append(str(text))

    prompt_file = prompt.get("file")
    if prompt_file:
        parts.append(expand_path(prompt_file).read_text(encoding="utf-8"))

    if not parts:
        return None

    path = runtime_dir(profile_name, profile) / "APPEND_SYSTEM.md"
    path.write_text("\n".join(parts), encoding="utf-8")
    return path


def build_omp_args(
    profile_name: str,
    profile: dict[str, Any],
    args: list[str],
    passthrough: bool,
) -> list[str]:
    if passthrough:
        return args

    omp_args: list[str] = []

    config_path = write_runtime_config(profile_name, profile)
    if config_path is not None:
        omp_args.extend(["--config", str(config_path)])

    session_dir = profile.get("sessionDir")
    if session_dir:
        omp_args.extend(["--session-dir", str(expand_path(session_dir))])

    prompt_path = write_runtime_prompt(profile_name, profile)
    if prompt_path is not None:
        omp_args.extend(["--append-system-prompt", str(prompt_path)])

    enabled_tools = profile.get("enabledTools")
    if enabled_tools:
        if isinstance(enabled_tools, list):
            enabled_tools = ",".join(str(tool) for tool in enabled_tools)
        omp_args.extend(["--tools", str(enabled_tools)])

    omp_args.extend(args)
    return omp_args


def add_existing_bind(args: list[str], flag: str, path: Path) -> None:
    if path.exists():
        args.extend([flag, str(path), str(path)])


def sandbox_enabled(profile: dict[str, Any], passthrough: bool) -> bool:
    if passthrough:
        return False
    sandbox = profile.get("sandbox") or {}
    return bool(sandbox.get("linuxBubblewrap")) and platform.system() == "Linux"


def run_pueued(env: dict[str, str]) -> None:
    try:
        subprocess.run(
            ["pueued", "-d"],
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=5,
            check=False,
        )
    except (FileNotFoundError, subprocess.SubprocessError):
        pass


def run_plain(command: list[str], env: dict[str, str]) -> int:
    result = subprocess.run(command, env=env, check=False)
    return result.returncode


def run_sandboxed(
    command: list[str], env: dict[str, str], profile: dict[str, Any]
) -> int:
    bwrap = shutil.which("bwrap", path=env.get("PATH"))
    if bwrap is None:
        return run_plain(command, env)

    home = Path.home()
    xdg_runtime = env.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    sandbox = profile.get("sandbox") or {}

    bwrap_args = [
        bwrap,
        "--ro-bind",
        "/nix/store",
        "/nix/store",
        "--ro-bind",
        "/etc",
        "/etc",
        "--ro-bind",
        "/run",
        "/run",
        "--dev",
        "/dev",
        "--proc",
        "/proc",
        "--tmpfs",
        "/tmp",
    ]

    add_existing_bind(bwrap_args, "--bind", expand_path(xdg_runtime))
    for raw in sandbox.get("rw") or []:
        add_existing_bind(bwrap_args, "--bind", expand_path(raw))
    for raw in sandbox.get("ro") or []:
        add_existing_bind(bwrap_args, "--ro-bind", expand_path(raw))

    env_keys = [
        "HOME",
        "PATH",
        "TERM",
        "LANG",
        "XDG_RUNTIME_DIR",
        "XDG_DATA_HOME",
        "XDG_CACHE_HOME",
        "XDG_CONFIG_HOME",
        "PI_CODING_AGENT_DIR",
        *TOOL_ENV_KEYS,
        *[str(key) for key in sandbox.get("envKeys") or []],
    ]
    env["HOME"] = str(home)
    env["XDG_RUNTIME_DIR"] = xdg_runtime

    for key in env_keys:
        if key in env:
            bwrap_args.extend(["--setenv", key, env[key]])

    bwrap_args.extend(
        [
            "--chdir",
            str(home),
            "--share-net",
            "--unshare-pid",
            "--die-with-parent",
            *command,
        ]
    )
    return run_plain(bwrap_args, env)


def backend_command(profile: dict[str, Any]) -> str:
    return str(profile.get("backend") or os.environ.get("OMP_PROFILE_BACKEND") or "omp")


def run_profile(profile_name: str, profile: dict[str, Any], args: list[str]) -> int:
    dirs = [
        *(profile.get("ensureDirs") or []),
        *([profile["agentDir"]] if profile.get("agentDir") else []),
        *([profile["sessionDir"]] if profile.get("sessionDir") else []),
    ]
    ensure_dirs([str(path) for path in dirs])

    env = build_env(profile)
    run_pueued(env)

    passthrough = is_passthrough(profile, args)
    command = [
        backend_command(profile),
        *build_omp_args(profile_name, profile, args, passthrough),
    ]
    if sandbox_enabled(profile, passthrough):
        return run_sandboxed(command, env, profile)
    return run_plain(command, env)


def main() -> int:
    profile_name, args, path = select_profile(sys.argv[1:])
    if profile_name is None or path is None:
        backend = os.environ.get("OMP_PROFILE_BACKEND") or "omp"
        return run_plain([backend, *args], os.environ.copy())

    if not path.exists():
        print(f"omp-profile: profile not found: {path}", file=sys.stderr)
        return 2

    try:
        profile = load_profile(path)
    except (OSError, ValueError, yaml.YAMLError) as error:
        print(f"omp-profile: {error}", file=sys.stderr)
        return 2

    return run_profile(profile_name, profile, args)


if __name__ == "__main__":
    sys.exit(main())
