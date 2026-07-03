from __future__ import annotations

import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import ModuleType
from unittest.mock import patch

import yaml


def load_module() -> ModuleType:
    module_path = Path(__file__).with_name("omp_profile.py")
    spec = importlib.util.spec_from_file_location("omp_profile_module", module_path)
    assert spec is not None
    assert spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class OmpProfileTests(unittest.TestCase):
    def test_selects_explicit_profile_and_removes_flag(self) -> None:
        mod = load_module()
        with tempfile.TemporaryDirectory() as tmp:
            with patch.dict(os.environ, {"OMP_PROFILES_DIR": tmp}, clear=True):
                name, args, path = mod.select_profile(
                    ["--profile", "lim", "token", "anthropic"]
                )

        self.assertEqual(name, "lim")
        self.assertEqual(args, ["token", "anthropic"])
        self.assertEqual(path.name, "lim.yml")

    def test_passthrough_omits_launch_flags(self) -> None:
        mod = load_module()
        profile = {
            "sessionDir": "~/.omp/state/lim/sessions",
            "config": {"skills": {"includeSkills": ["zhost-cli"]}},
            "prompt": {"text": "prompt"},
            "enabledTools": ["read", "bash"],
        }

        args = mod.build_omp_args(
            "lim", profile, ["auth-broker", "login", "anthropic"], True
        )

        self.assertEqual(args, ["auth-broker", "login", "anthropic"])
        self.assertNotIn("--config", args)
        self.assertNotIn("--append-system-prompt", args)

    def test_run_profile_sets_agent_dir_and_tool_path(self) -> None:
        mod = load_module()
        calls: list[tuple[list[str], dict[str, str]]] = []

        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            profile = {
                "backend": "omp-real",
                "agentDir": str(home / ".omp/state/lim/agent"),
                "sessionDir": str(home / ".omp/state/lim/sessions"),
                "toolPath": ["/tool/bin"],
                "enabledTools": ["read"],
            }

            def fake_run(
                cmd: list[str], **kwargs: object
            ) -> subprocess.CompletedProcess[str]:
                env = kwargs.get("env")
                if cmd == ["pueued", "-d"]:
                    return subprocess.CompletedProcess(cmd, 0)
                assert isinstance(env, dict)
                calls.append((cmd, env.copy()))
                return subprocess.CompletedProcess(cmd, 0)

            with (
                patch.dict(os.environ, {"HOME": str(home)}, clear=True),
                patch.object(mod.subprocess, "run", side_effect=fake_run),
            ):
                self.assertEqual(mod.run_profile("lim", profile, ["hello"]), 0)

        self.assertEqual(calls[0][0][0], "omp-real")
        self.assertIn("--session-dir", calls[0][0])
        self.assertEqual(calls[0][1]["PI_CODING_AGENT_DIR"], profile["agentDir"])
        self.assertTrue(calls[0][1]["PATH"].startswith("/tool/bin"))

    def test_profile_yaml_round_trips(self) -> None:
        data = {"backend": "omp", "enabledTools": ["read", "bash"]}
        rendered = yaml.safe_dump(data)
        self.assertEqual(yaml.safe_load(rendered), data)


if __name__ == "__main__":
    unittest.main()
