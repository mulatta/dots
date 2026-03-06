/**
 * Custom Instructions Extension - appends CLAUDE.md to system prompt
 *
 * Adapts the jj-only VCS rules for worktree-aware operation:
 * - Inside workmux worktrees (__worktrees/ in path): use git directly
 * - Outside worktrees: use jj (jj describe, jj new, jj log)
 */

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  pi.on("before_agent_start", async (event, _ctx) => {
    const home = process.env.HOME || "";
    const instructionsPath = join(home, ".claude", "CLAUDE.md");

    if (existsSync(instructionsPath)) {
      let instructions = readFileSync(instructionsPath, "utf-8");

      // Replace jj-only VCS section with worktree-aware rules
      instructions = instructions.replace(
        /## CRITICAL: Version Control.*?(?=\n## )/s,
        `## Version Control
- Inside workmux worktrees (__worktrees/ in path): use git directly
- Outside worktrees: use jj (jj describe, jj new, jj log)
- After workmux merge, jj auto-detects new commits (colocated repo)
- NEVER use git in the main worktree
`,
      );

      return {
        systemPrompt: event.systemPrompt + "\n\n" + instructions,
      };
    }
  });
}
