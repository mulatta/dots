import copy
import unittest

from strip_node_runtime import strip_node_runtime

PACKAGE = {
    "name": "open-knowledge",
    "devEngines": {
        "runtime": {"name": "node", "version": "24.21.0", "onFail": "download"},
        "packageManager": {"name": "pnpm", "version": "12.9.0"},
    },
}
LOCK = """lockfileVersion: '9.0'

importers:
  .:
    devDependencies:
      node:
        specifier: runtime:24.21.0
        version: runtime:24.21.0
      other:
        specifier: 1.0.0
        version: 1.0.0

packages:
  node@runtime:24.21.0:
    resolution:
      type: variations
      variants:
        - resolution:
            integrity: sha256-example
          target: {os: linux, cpu: x64}

  other@1.0.0:
    resolution: {integrity: sha512-example}

snapshots:
  node@runtime:24.21.0: {}

  other@1.0.0: {}
"""


class StripNodeRuntimeTests(unittest.TestCase):
    def test_removes_only_node_runtime(self):
        package, lock = strip_node_runtime(copy.deepcopy(PACKAGE), LOCK)
        self.assertEqual(
            package,
            {
                "name": "open-knowledge",
                "devEngines": {"packageManager": {"name": "pnpm", "version": "12.9.0"}},
            },
        )
        self.assertEqual(
            lock,
            LOCK.replace(
                "      node:\n        specifier: runtime:24.21.0\n"
                "        version: runtime:24.21.0\n",
                "",
            )
            .replace(
                "  node@runtime:24.21.0:\n    resolution:\n"
                "      type: variations\n      variants:\n"
                "        - resolution:\n            integrity: sha256-example\n"
                "          target: {os: linux, cpu: x64}\n\n",
                "",
            )
            .replace("  node@runtime:24.21.0: {}\n\n", ""),
        )

    def test_removes_empty_dev_engines(self):
        package = copy.deepcopy(PACKAGE)
        del package["devEngines"]["packageManager"]
        result, _ = strip_node_runtime(package, LOCK)
        self.assertNotIn("devEngines", result)
        self.assertEqual(package["devEngines"]["runtime"]["name"], "node")

    def test_does_not_mutate_package_on_failure(self):
        package = copy.deepcopy(PACKAGE)
        with self.assertRaises(ValueError):
            strip_node_runtime(package, LOCK.replace("snapshots:", "renamed:"))
        self.assertEqual(package, PACKAGE)

    def test_rejects_changed_runtime_policy(self):
        for change in [{"onFail": "error"}, {"newPolicy": True}]:
            package = copy.deepcopy(PACKAGE)
            package["devEngines"]["runtime"].update(change)
            with self.subTest(change=change), self.assertRaises(ValueError):
                strip_node_runtime(package, LOCK)

    def test_rejects_missing_or_changed_runtime(self):
        for runtime in [
            None,
            {},
            [],
            "node",
            {"name": "bun", "version": "24.21.0"},
            {"name": "node", "version": "24x21x0"},
            {"name": "node", "version": None},
        ]:
            with self.subTest(runtime=runtime), self.assertRaises(ValueError):
                package = copy.deepcopy(PACKAGE)
                package["devEngines"]["runtime"] = runtime
                strip_node_runtime(package, LOCK)
        with self.assertRaises(TypeError):
            strip_node_runtime({"name": "open-knowledge"}, LOCK)

    def test_rejects_changed_lockfile(self):
        for lock in [
            LOCK.replace("      node:\n", "      nodejs:\n"),
            LOCK.replace("runtime:24.21.0", "runtime:24x21x0"),
            LOCK.replace("        version: runtime:24.21.0\n", ""),
            LOCK.replace("  node@runtime:24.21.0: {}\n", ""),
            LOCK + "  unexpected@runtime:24.21.0: {}\n",
            LOCK.replace("snapshots:", "renamedSnapshots:"),
            LOCK.replace("      node:\n", "      node:\n        extra: true\n"),
            LOCK.replace(
                "  node@runtime:24.21.0: {}", "  node@runtime:24.21.0: {changed: true}"
            ),
        ]:
            with self.subTest(lock=lock), self.assertRaises(ValueError):
                strip_node_runtime(copy.deepcopy(PACKAGE), lock)


if __name__ == "__main__":
    unittest.main()
