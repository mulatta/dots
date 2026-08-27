import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { existsSync } from "node:fs";
import { isAbsolute, resolve } from "node:path";
import {
  currentBranch,
  gitRequired,
  localBase,
  resolveCommit,
} from "./_git.ts";

const TIDY_PROMPT = `
Tidy branch history into cohesive, reviewable commits while preserving final
tree and intent. Turn tangled incremental changes such as \`A -> A+B -> B\`
into direct logical changes such as \`A -> B\`.

## Commit quality bar

Each final commit must:

- have one clear purpose
- be understandable on its own from its diff and message
- avoid mixing unrelated files or hunks
- include tests, docs, and config with code they validate or explain
- stay small enough to review without hiding multiple concerns
- leave tree buildable and reviewable when practical

Split commits containing independent concepts. Combine commits only when one is
a fixup, cleanup, rename support, or test/docs companion for same concept. Do
not squash everything unless whole change is one small logical unit.

Use imperative, concise commit subjects following repository convention. Prefer
\`<context>: <description>\` when existing history uses scoped subjects. Avoid
Conventional Commit prefixes unless repository history uses them. Explain why,
not merely what, in commit bodies when needed.

## Required workflow

1. Treat preloaded data as structural inventory, not complete evidence.
2. Use git-surgeon skill for history inspection. Investigate tangled files and
   ambiguous hunks with its \`hunks --commit\`, \`--full\`, \`--blame\`, and
   \`show\` operations instead of loading full branch patch.
3. Present rewrite plan before changing history. For each proposed commit, give
   subject, purpose, and files or hunks it contains.
4. Before any history mutation, require clean worktree and index. If either has
   uncommitted changes, ask user how to handle them. Do not invoke git-surgeon,
   raw rebase, reset, stash, add, commit, or other mutating commands until tree
   is clean or user explicitly approves handling plan. Never rely on
   git-surgeon's automatic stash behavior.
5. After plan is accepted, prefer git-surgeon \`split\`, \`fold\`, \`move\`,
   \`squash\`, \`amend\`, and \`reword\` operations. Do not construct an
   interactive rebase manually. Use lower-level Git only when git-surgeon cannot
   express approved rewrite.
6. Preserve final tree exactly unless user explicitly approves a difference.
   Compare rewritten HEAD tree with backup commit.
7. Run relevant narrow formatters, linters, or tests.
8. Inspect final history and use \`git range-diff\` when useful.
9. Report final commits, verification commands, remaining risks, and retained
   backup ref. Mention \`git for-each-ref refs/backup/tidy\` for listing backups.

Never force-push or update remote refs unless explicitly requested. Backup ref
shown below protects original HEAD; do not replace or delete it.
`.trim();

const CONTEXT_LIMIT = 15_000;
const OPERATION_PATHS = [
  ["rebase-merge", "rebase"],
  ["rebase-apply", "rebase"],
  ["MERGE_HEAD", "merge"],
  ["CHERRY_PICK_HEAD", "cherry-pick"],
] as const;

function truncateMarkdown(output: string, label: string): string {
  if (output.length <= CONTEXT_LIMIT) return output;

  const truncated = output.slice(0, CONTEXT_LIMIT);
  const openFence = (truncated.match(/^```/gm)?.length ?? 0) % 2 === 1;
  const closingFence = openFence ? "\n```" : "";
  return `${truncated}${closingFence}\n\n[${label} truncated at ${CONTEXT_LIMIT} characters; inspect narrower history with git-surgeon]`;
}

async function operationsInProgress(pi: ExtensionAPI, cwd: string) {
  const found = new Set<string>();
  for (const [gitPath, operation] of OPERATION_PATHS) {
    const path = await gitRequired(pi.exec, ["rev-parse", "--git-path", gitPath]);
    if (existsSync(isAbsolute(path) ? path : resolve(cwd, path))) {
      found.add(operation);
    }
  }
  return [...found];
}

function backupRef(oid: string): string {
  const timestamp = new Date().toISOString().replaceAll(/[-:.TZ]/g, "");
  return `refs/backup/tidy/${timestamp}-${oid.slice(0, 12)}`;
}

export default function (pi: ExtensionAPI) {
  pi.registerCommand("tidy", {
    description: "Tidy tangled history into logical commits",
    handler: async (args, ctx) => {
      const refs = args.trim().split(/\s+/).filter(Boolean);
      if (refs.length > 2) {
        ctx.ui.notify("Usage: /tidy [base-ref] [head-ref]", "error");
        return;
      }

      try {
        const branch = await currentBranch(pi.exec);
        const baseRef = refs[0] ?? await localBase(pi.exec);
        const headRef = refs[1] ?? "HEAD";
        const [baseOid, headOid, operations] = await Promise.all([
          resolveCommit(pi.exec, baseRef),
          resolveCommit(pi.exec, headRef),
          operationsInProgress(pi, ctx.cwd),
        ]);

        if (operations.length > 0) {
          ctx.ui.notify(
            `Finish or abort in-progress ${operations.join(", ")} before tidying history`,
            "error",
          );
          return;
        }

        const mergeBase = await gitRequired(pi.exec, [
          "merge-base",
          baseOid,
          headOid,
        ]);
        const range = `${mergeBase}..${headOid}`;
        const [commits, mergeCommits] = await Promise.all([
          gitRequired(pi.exec, [
            "log",
            "--reverse",
            "--format=%h %s",
            range,
          ]),
          gitRequired(pi.exec, [
            "rev-list",
            "--merges",
            "--reverse",
            range,
          ]),
        ]);

        if (!commits) {
          ctx.ui.notify(`No commits to tidy between ${baseRef} and ${headRef}`, "info");
          return;
        }

        const backup = backupRef(headOid);
        await gitRequired(pi.exec, ["update-ref", backup, headOid]);

        const [status, finalStat, matrix] = await Promise.all([
          gitRequired(pi.exec, ["status", "--short"]),
          gitRequired(pi.exec, ["diff", "--stat", range], 10_000),
          gitRequired(
            pi.exec,
            [
              "log",
              "--reverse",
              "--format=commit %h %s",
              "--name-status",
              range,
            ],
            10_000,
          ),
        ]);

        const context = truncateMarkdown([
          "## Preloaded Git inventory",
          "",
          `- Current branch: \`${branch || "(detached HEAD)"}\``,
          `- Base ref: \`${baseRef}\` (\`${baseOid.slice(0, 12)}\`)`,
          `- Head ref: \`${headRef}\` (\`${headOid.slice(0, 12)}\`)`,
          `- Rewrite base (merge base): \`${mergeBase.slice(0, 12)}\``,
          `- Backup ref: \`${backup}\``,
          `- Worktree: ${status ? "dirty" : "clean"}`,
          `- Merge commits in range: ${mergeCommits ? "yes" : "no"}`,
          ...(mergeCommits
            ? [`- Merge commit IDs: \`${mergeCommits.split("\n").join(", ")}\``]
            : []),
          "",
          "### Worktree status",
          "```text",
          status || "(clean)",
          "```",
          "",
          "### Existing commits (oldest first)",
          "```text",
          commits,
          "```",
          "",
          "### Final tree stat",
          "```text",
          finalStat || "(no changes)",
          "```",
          "",
          "### Commit/file matrix (oldest first)",
          "```text",
          matrix || "(no changes)",
          "```",
        ].join("\n"), "Git inventory");

        pi.sendUserMessage(`${TIDY_PROMPT}\n\n${context}`, {
          deliverAs: "followUp",
        });
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        ctx.ui.notify(`Cannot prepare tidy: ${message}`, "error");
      }
    },
  });
}
