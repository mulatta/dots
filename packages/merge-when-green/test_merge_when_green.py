"""Exercise platform detection without authenticated forge clients."""

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("merge-when-green.py")


class DetectPlatformTest(unittest.TestCase):
    def test_github_remote_needs_no_forge_client(self) -> None:
        git = shutil.which("git")
        self.assertIsNotNone(git)
        assert git is not None
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run([git, "init", "--quiet", directory], check=True)
            subprocess.run(
                [git, "remote", "add", "origin", "git@github.com:example/project.git"],
                cwd=root,
                check=True,
            )
            # Only git is available: remote identity must not depend on gh login.
            bin_dir = root / "bin"
            bin_dir.mkdir()
            (bin_dir / "git").symlink_to(git)
            code = (
                f"import runpy; module = runpy.run_path({str(SCRIPT)!r}); "
                "assert module['detect_platform']() == module['Platform'].GITHUB"
            )
            result = subprocess.run(
                [sys.executable, "-c", code],
                cwd=root,
                env={**os.environ, "PATH": str(bin_dir)},
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
