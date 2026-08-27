/**
 * Shared git helpers for pi extensions.
 *
 * Several commands (commit/merge/rebase/review/open-pr) need the same
 * "what branch am I on" and "what is my base branch" answers. Centralising
 * them keeps the fallback order consistent and avoids the .code/.exitCode
 * drift that already crept in once.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export type Exec = ExtensionAPI["exec"];

/** Run git, return trimmed stdout on success or "" on failure. */
export async function git(
  exec: Exec,
  args: string[],
  timeout = 5000,
): Promise<string> {
  const r = await exec("git", args, { timeout });
  return r.code === 0 ? r.stdout.trim() : "";
}

export async function currentBranch(exec: Exec): Promise<string> {
  return git(exec, ["branch", "--show-current"]);
}

/** Resolve the remote's configured default branch, or "". */
export async function remoteDefault(exec: Exec): Promise<string> {
  return git(exec, [
    "symbolic-ref",
    "--short",
    "refs/remotes/origin/HEAD",
  ]);
}

/** Local default branch for rebase/diff: origin/HEAD → main → master. */
export async function localBase(exec: Exec): Promise<string> {
  const remote = await remoteDefault(exec);
  if (remote.startsWith("origin/")) {
    const local = remote.slice("origin/".length);
    if (await git(exec, ["rev-parse", "--verify", "-q", local])) return local;
  }

  for (const branch of ["main", "master"]) {
    if (await git(exec, ["rev-parse", "--verify", "-q", branch])) return branch;
  }
  return "main";
}

/** Remote default branch for PR diffs, with local branches as a fallback. */
export async function prBase(exec: Exec): Promise<string> {
  const remote = await remoteDefault(exec);
  if (remote) return remote;

  for (const branch of ["origin/main", "origin/master"]) {
    if (await git(exec, ["rev-parse", "--verify", "-q", branch])) return branch;
  }
  return localBase(exec);
}

// pi's loader treats every *.ts in extensions/ as an extension and errors on
// modules without a default export. This file is a helper library, so export
// a no-op factory to keep the loader quiet.
export default function (_pi: ExtensionAPI) {}
