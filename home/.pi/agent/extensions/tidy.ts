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
Tidy this branch's history.

Read the \`tidy\` skill in full and follow it:
\`~/.claude/skills/tidy/SKILL.md\`. It owns the commit quality bar, the
plan-before-rewrite gate, the git-surgeon operations, and the backup ref. Do
not work from memory of it.

The inventory below is already loaded. Treat it as a structural inventory, not
complete evidence: inspect tangled files and ambiguous hunks yourself.
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
