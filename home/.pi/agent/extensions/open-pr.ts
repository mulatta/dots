/**
 * /open-pr command — write a PR description and open the PR.
 *
 * Preloads git diff, log, and status so the agent can write the description
 * without spending tool-call turns gathering context.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { currentBranch, git, prBase } from "./_git.ts";

const OPEN_PR_PROMPT = `
Write a PR description and open the PR.

Read the Open PR playbook in full and follow it:
\`~/.claude/skills/mulatta-mode/playbooks/opening-a-pr.md\`. It owns the scope,
the description, the title, and how the PR opens. Do not work from memory of
it.

The git state below is already loaded. Do not re-run those commands to get it.
`.trim();

// Anything larger than this is probably noise (lockfiles, generated code).
// The agent can re-run git diff with pathspecs if it needs more.
const DIFF_LIMIT = 200_000;

// GitHub:  .github/PULL_REQUEST_TEMPLATE.md, docs/..., root
// Gitea:   same as GitHub plus .gitea/ (mirrors .github/)
// GitLab:  .gitlab/merge_request_templates/Default.md
// All forges accept both upper- and lowercase filenames, so match
// case-insensitively against readdir() instead of hardcoding every variant.
const TEMPLATE_LOCATIONS: Array<[dir: string, name: string]> = [
  [".github", "pull_request_template.md"],
  [".gitea", "pull_request_template.md"],
  [".gitlab/merge_request_templates", "default.md"],
  ["docs", "pull_request_template.md"],
  [".", "pull_request_template.md"],
];

function findPrTemplate(
  repoRoot: string,
): { path: string; body: string } | undefined {
  for (const [dir, name] of TEMPLATE_LOCATIONS) {
    let entries: string[];
    try {
      entries = readdirSync(join(repoRoot, dir));
    } catch {
      continue;
    }
    const hit = entries.find((e) => e.toLowerCase() === name);
    if (hit) {
      const path = join(dir, hit);
      try {
        return { path, body: readFileSync(join(repoRoot, path), "utf8") };
      } catch {
        // unreadable (permissions, broken symlink) — keep looking
      }
    }
  }
  return undefined;
}

export default function (pi: ExtensionAPI) {
  pi.registerCommand("open-pr", {
    description: "Write a PR description and open the PR",
    handler: async (_args, _ctx) => {
      const [cur, repoRoot] = await Promise.all([
        currentBranch(pi.exec),
        git(pi.exec, ["rev-parse", "--show-toplevel"]),
      ]);
      const baseBranch = await prBase(pi.exec);

      const [status, log, diff] = await Promise.all([
        pi.exec("git", ["status"], { timeout: 5000 }),
        pi.exec("git", ["log", `${baseBranch}..HEAD`, "--format=%s%n%n%b"], {
          timeout: 5000,
        }),
        pi.exec("git", ["diff", `${baseBranch}...HEAD`, "--stat", "-p"], {
          timeout: 10000,
        }),
      ]);

      const template = findPrTemplate(repoRoot);

      let diffOut = diff.stdout;
      if (diffOut.length > DIFF_LIMIT) {
        diffOut = diffOut.slice(0, DIFF_LIMIT) +
          `\n\n[... diff truncated at ${DIFF_LIMIT} bytes, re-run git diff with pathspecs if needed ...]`;
      }

      const templateSection = template
        ? [
          `Found \`${template.path}\` — the playbook says to fill this in:`,
          "",
          "```markdown",
          template.body.trim(),
          "```",
        ].join("\n")
        : "(no PR template found in repo; write the description the playbook's way)";

      const gitContext = [
        "## Current git state",
        "",
        `Current branch: \`${cur}\``,
        `Base branch: \`${baseBranch}\``,
        "",
        "### git status",
        "```",
        status.stdout.trim(),
        "```",
        "",
        `### git log ${baseBranch}..HEAD`,
        "```",
        log.stdout.trim() || "(no commits ahead of base)",
        "```",
        "",
        "### Repo PR template",
        templateSection,
        "",
        `### git diff ${baseBranch}...HEAD`,
        "```diff",
        diffOut.trim() || "(no diff)",
        "```",
      ].join("\n");

      pi.sendUserMessage(`${OPEN_PR_PROMPT}\n\n${gitContext}`, {
        deliverAs: "followUp",
      });
    },
  });
}
