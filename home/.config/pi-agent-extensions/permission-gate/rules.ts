/**
 * permission-gate user rules — argv-based so quoted mentions (e.g.
 * `echo "ssh ..."`) don't trigger them. Built-in duplicates are omitted.
 */

// Match `cmd sub1 sub2 ...` anywhere in the pipeline. `sub` may be a
// string (exact) or string[] (any-of).
const is = (pipe: string[][], cmd: string, ...subs: (string | string[])[]) =>
  pipe.some((argv) =>
    argv[0] === cmd &&
    subs.every((sub, i) =>
      Array.isArray(sub) ? sub.includes(argv[i + 1]) : argv[i + 1] === sub,
    ),
  );

export default {
  extraRules: [
    { label: "ssh", test: (p) => is(p, "ssh") },
    { label: "send email", test: (p) => is(p, "msmtp") },

    // Forced rebuilds are usually wrong; edit the nix expression instead.
    // `nix build --rebuild` and `nix-build`/`nix-store --check` do the same.
    {
      label: "nix forced rebuild",
      test: (p) =>
        p.some(
          (argv) =>
            (argv[0] === "nix" && argv.includes("--rebuild")) ||
            ((argv[0] === "nix-build" || argv[0] === "nix-store") &&
              argv.includes("--check")),
        ),
    },
    {
      label: "deploy to machine",
      test: (p) => is(p, "clan", "machines", "update"),
    },

    // `git checkout [<tree-ish>] -- <paths>` resets tracked files.
    {
      label: "git checkout (reset files)",
      test: (p) =>
        p.some((argv) => {
          if (argv[0] !== "git") return false;
          const checkout = argv.indexOf("checkout");
          const separator = argv.indexOf("--", checkout + 1);
          return checkout > 0 && separator > checkout && separator < argv.length - 1;
        }),
    },

    // GitHub
    {
      label: "create GitHub issue",
      test: (p) => is(p, "gh", "issue", "create"),
    },
    {
      label: "modify GitHub issue",
      test: (p) => is(p, "gh", "issue", ["close", "delete", "edit", "comment"]),
    },
    { label: "create GitHub PR", test: (p) => is(p, "gh", "pr", "create") },
    {
      label: "modify GitHub PR",
      test: (p) => is(p, "gh", "pr", ["close", "merge", "edit", "comment", "review"]),
    },

    // Gitea
    {
      label: "create Gitea issue/PR",
      test: (p) => is(p, "tea", ["issue", "pr"], "create"),
    },
    {
      label: "modify Gitea issue/PR",
      test: (p) => is(p, "tea", ["issue", "pr"], ["close", "edit"]),
    },
    { label: "Gitea comment", test: (p) => is(p, "tea", "comment") },
  ],
};
