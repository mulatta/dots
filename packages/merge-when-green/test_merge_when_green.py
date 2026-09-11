"""Exercise platform detection without authenticated forge clients."""

import json
import os
import runpy
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

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


class GiteaProtocolTest(unittest.TestCase):
    def setUp(self) -> None:
        self.module = runpy.run_path(str(SCRIPT))
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.cwd = Path.cwd()
        self.path = os.environ["PATH"]
        git = shutil.which("git")
        assert git is not None
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        (bin_dir / "git").symlink_to(git)
        os.environ["PATH"] = str(bin_dir)
        self.token = os.environ.get("GITEA_TOKEN")
        os.environ["GITEA_TOKEN"] = "fixture-token"
        subprocess.run(["git", "init", "--quiet", str(self.root)], check=True)
        os.chdir(self.root)
        self.routes: dict[str, tuple[int, Any]] = {}
        self.requests: list[tuple[str, str, Any]] = []
        routes, requests = self.routes, self.requests

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:
                self.respond()

            def do_POST(self) -> None:
                self.respond()

            def respond(self) -> None:
                body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
                requests.append(
                    (self.command, self.path, json.loads(body) if body else None)
                )
                if self.headers.get("Authorization") != "token fixture-token":
                    status, data = 401, {"message": "unauthorized"}
                else:
                    status, data = routes.get(
                        self.path, (404, {"message": "not found"})
                    )
                self.send_response(status)
                if status == 302:
                    self.send_header("Location", data["location"])
                self.end_headers()
                if status != 204:
                    self.wfile.write(json.dumps(data).encode())

            def log_message(self, format: str, *args: Any) -> None:
                pass

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.origin = f"http://127.0.0.1:{self.server.server_port}"
        subprocess.run(
            ["git", "remote", "add", "origin", f"{self.origin}/mulatta/blog.git"],
            check=True,
        )
        self.api = "/api/v1/repos/mulatta/blog"
        self.routes[f"{self.api}/pulls/42"] = (
            200,
            {"state": "open", "head": {"sha": "abc"}},
        )

    def tearDown(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        os.chdir(self.cwd)
        os.environ["PATH"] = self.path
        self.temp.cleanup()
        if self.token is None:
            os.environ.pop("GITEA_TOKEN", None)
        else:
            os.environ["GITEA_TOKEN"] = self.token

    def test_remote_forms(self) -> None:
        for remote, expected in [
            ("gitea@git.mulatta.io:mulatta/blog.git", "https://git.mulatta.io"),
            (
                "ssh://gitea@git.mulatta.io:2222/mulatta/blog.git",
                "https://git.mulatta.io",
            ),
            (f"{self.origin}/mulatta/blog.git", self.origin),
        ]:
            subprocess.run(["git", "remote", "set-url", "origin", remote], check=True)
            self.assertEqual(
                self.module["get_repo_info"](), (expected, "mulatta", "blog")
            )

    def test_paginated_existing_pr_excludes_fork(self) -> None:
        self.routes[f"{self.api}/pulls?state=open&limit=50&page=1"] = (
            200,
            [
                {
                    "number": 1,
                    "base": {"ref": "main"},
                    "head": {"ref": "topic", "repo": {"full_name": "fork/blog"}},
                },
                {
                    "number": 2,
                    "base": {"ref": "release"},
                    "head": {"ref": "topic", "repo": {"full_name": "mulatta/blog"}},
                },
            ],
        )
        self.routes[f"{self.api}/pulls?state=open&limit=50&page=2"] = (
            200,
            [
                {
                    "number": 42,
                    "base": {"ref": "main"},
                    "head": {"ref": "topic", "repo": {"full_name": "mulatta/blog"}},
                }
            ],
        )
        self.routes[f"{self.api}/pulls/42/merge"] = (204, None)
        self.assertEqual(
            self.module["enable_automerge_existing_pr"](
                "topic", self.module["Platform"].GITEA, "main"
            ),
            "42",
        )

    def test_create_and_enable(self) -> None:
        self.routes[f"{self.api}/pulls"] = (201, {"number": 42})
        self.routes[f"{self.api}/pulls/42/merge"] = (204, None)
        self.assertEqual(
            self.module["create_pr_gitea"]("topic", "main", "Title", "Body"), "42"
        )
        self.assertEqual(
            self.requests[0][2],
            {"head": "topic", "base": "main", "title": "Title", "body": "Body"},
        )
        self.assertTrue(self.requests[2][2]["merge_when_checks_succeed"])
        self.assertEqual(self.requests[2][2]["do"], "merge")
        self.assertEqual(self.requests[2][2]["head_commit_id"], "abc")

    def test_merge_error_propagates(self) -> None:
        for status in (401, 403, 405, 409, 422, 500):
            self.routes[f"{self.api}/pulls/42/merge"] = (
                status,
                {"message": "rejected"},
            )
            with self.assertRaises(RuntimeError):
                self.module["gitea_enable_automerge"]("42")

    def test_direct_terminal_state(self) -> None:
        for merged in (True, False):
            self.routes[f"{self.api}/pulls/42"] = (
                200,
                {"state": "closed", "merged": merged},
            )
            self.assertIs(self.module["check_gitea_pr_state"]("42"), merged)
        self.routes[f"{self.api}/pulls/42"] = (404, {})
        with self.assertRaises(RuntimeError):
            self.module["check_gitea_pr_state"]("42")

    def test_empty_list_and_default_branch(self) -> None:
        self.routes[f"{self.api}/pulls?state=open&limit=50&page=1"] = (200, [])
        self.assertFalse(
            self.module["check_pr_exists"]("missing", self.module["Platform"].GITEA)
        )
        self.routes[self.api] = (200, {"default_branch": "release/stable"})
        self.assertEqual(
            self.module["get_default_branch"](self.module["Platform"].GITEA),
            "release/stable",
        )

    def test_pending_and_second_page_failure(self) -> None:
        self.routes[f"{self.api}/pulls/42"] = (
            200,
            {"state": "open", "head": {"sha": "abc"}},
        )
        first = f"{self.api}/commits/abc/status?limit=50&page=1"
        self.routes[first] = (
            200,
            {"statuses": [{"context": "build", "status": "pending"}]},
        )
        self.routes[f"{self.api}/commits/abc/status?limit=50&page=2"] = (
            200,
            {"statuses": [{"context": "lint", "status": "warning"}]},
        )
        self.routes[f"{self.api}/commits/abc/status?limit=50&page=3"] = (
            200,
            {"statuses": None},
        )
        self.assertIsNone(self.module["check_gitea_pr_state"]("42"))
        self.routes[first] = (
            200,
            {"statuses": [{"context": "build", "status": "skipped"}]},
        )
        self.assertIs(self.module["check_gitea_pr_state"]("42"), False)
        self.routes[first] = (200, {"statuses": None})
        self.assertIsNone(self.module["check_gitea_pr_state"]("42"))

    def test_malformed_pr_responses_fail(self) -> None:
        for value in (None, {}, {"message": "bad"}):
            self.routes[f"{self.api}/pulls?state=open&limit=50&page=1"] = (200, value)
            with self.assertRaises(RuntimeError):
                self.module["find_gitea_pr"]("topic")
        for pr_value in ({"number": "topic"}, {"number": None}, {}):
            self.routes[f"{self.api}/pulls"] = (201, pr_value)
            with self.assertRaises(RuntimeError):
                self.module["create_pr_gitea"]("topic", "main", "Title", "Body")

    def test_login_instance_matching(self) -> None:
        select = self.module["select_gitea_url"]
        logins = [
            {
                "name": "mulatta",
                "url": "https://git.mulatta.io",
                "ssh_host": "gitea-ssh",
                "default": "true",
            }
        ]
        self.assertEqual(
            select(logins, "https://gitea-ssh", False), "https://git.mulatta.io"
        )
        self.assertEqual(
            select(logins, "https://git.mulatta.io:443", True), "https://git.mulatta.io"
        )
        for origin in (
            "https://git.mulatta.io:8443",
            "http://git.mulatta.io",
            "https://mulatta.io",
            "https://git.mulatta.io.evil",
        ):
            with self.assertRaises(RuntimeError):
                select(logins, origin, True)
        with self.assertRaises(RuntimeError):
            select(
                logins + [{"url": "https://git.mulatta.io:8443"}],
                "https://git.mulatta.io",
                False,
            )

    def test_redirect_rejected(self) -> None:
        self.routes[self.api] = (302, {"location": f"{self.origin}/redirected"})
        self.routes["/redirected"] = (200, {})
        with self.assertRaisesRegex(RuntimeError, "HTTP 302"):
            self.module["gitea_api"]("")
        self.assertEqual(len(self.requests), 1)

    def test_token_required(self) -> None:
        os.environ.pop("GITEA_TOKEN")
        with self.assertRaisesRegex(RuntimeError, "GITEA_TOKEN is required"):
            self.module["gitea_api"]("")
        self.assertEqual(self.requests, [])

    def test_settled_failed_ci(self) -> None:
        self.routes[f"{self.api}/pulls/42"] = (
            200,
            {"state": "open", "head": {"sha": "abc"}},
        )
        self.routes[f"{self.api}/commits/abc/status?limit=50&page=1"] = (
            200,
            {
                "statuses": [
                    {"context": "build", "status": "failure"},
                    {"context": "lint", "status": "success"},
                ]
            },
        )
        self.routes[f"{self.api}/commits/abc/status?limit=50&page=2"] = (
            200,
            {"statuses": []},
        )
        self.assertIs(self.module["check_gitea_pr_state"]("42"), False)


if __name__ == "__main__":
    unittest.main()
