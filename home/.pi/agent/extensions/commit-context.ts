/**
 * /commit command — commits staged changes (or all if nothing staged).
 *
 * Injects live `git status` and `git log` output so the agent has full
 * context without wasting a tool-call turn.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const COMMIT_PROMPT = `
Commit the changes.

Read the \`commit\` skill in full and follow it:
\`~/git/harness/skills/commit/SKILL.md\`. It owns the selection, the message
style, and what to report. Do not work from memory of it.

The git state below is already loaded. Do not re-run those commands to get it.
`.trim();

export default function (pi: ExtensionAPI) {
  pi.registerCommand("commit", {
    description: "Commit staged changes (or all if nothing staged)",
    handler: async (_args, ctx) => {
      const [status, log] = await Promise.all([
        pi.exec("git", ["status"], { timeout: 5000 }),
        pi.exec("git", ["log", "--oneline", "-5"], { timeout: 5000 }),
      ]);

      const gitContext = [
        "## Current git state",
        "",
        "### git status",
        "```",
        status.stdout.trim(),
        "```",
        "",
        "### git log --oneline -5",
        "```",
        log.stdout.trim(),
        "```",
      ].join("\n");

      pi.sendUserMessage(`${COMMIT_PROMPT}\n\n${gitContext}`, {
        deliverAs: "followUp",
      });
    },
  });
}
