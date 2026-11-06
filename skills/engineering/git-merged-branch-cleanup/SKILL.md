---
name: git-merged-branch-cleanup
description: >
  Delete local and remote Git branches whose work is already merged into the base
  branch. Use when the user asks to "delete merged branches", "clean up branches",
  "prune stale branches", "apague as branches mergeadas", or after a batch of pull
  requests has been merged. Detects both true merges (ancestry) and squash/rebase
  merges (via GitHub's merged PRs), refuses branches with commits that were never
  merged, and protects long-lived branches. Ships a script that defaults to dry-run.
---

# Git merged branch cleanup

Deleting merged branches looks like one command (`git branch -d`) and is not. On repos
that squash-merge pull requests, `git branch --merged` is blind: the branch never
becomes an ancestor of the base branch, so every command based on `--merged` misses
almost everything. On repos where people push one more commit after opening the PR, the
merged flag is a lie and deleting the branch loses work. This skill handles both.

## Trigger

Activate when the user asks to remove merged / stale / old branches, either locally or
on the remote, for any repository — including Portuguese phrasings such as
"apague as branches mergeadas" and "limpe as branches antigas".

## Quick start

Run from anywhere inside the repository:

```bash
# 1. Always look first. Dry-run is the default and prints nothing destructive.
"$SKILL_DIR/scripts/cleanup-merged-branches.sh"

# 2. If the plan looks right, apply it.
"$SKILL_DIR/scripts/cleanup-merged-branches.sh" --apply

# Only one side, or a different base/remote:
"$SKILL_DIR/scripts/cleanup-merged-branches.sh" --apply --remote
"$SKILL_DIR/scripts/cleanup-merged-branches.sh" --apply --base develop --remote upstream
```

`$SKILL_DIR` is the directory containing this `SKILL.md`. Do not copy the script into
the target repo unless the user asks for that.

Show the user the dry-run plan and get confirmation before running `--apply`, because it
rewrites the shared remote. If the user already said "delete them", apply directly but
report exactly what was skipped and why.

## How the script decides

A branch is eligible for deletion only when at least one of these is true:

1. **Ancestry** — the tip is contained in the base branch (`git merge-base --is-ancestor`).
   Covers merge commits and fast-forwards.
2. **Merged PR, same tip** — GitHub reports a merged PR whose `headRefOid` equals the
   branch tip. Covers squash and rebase merges.
3. **Merged PR, stale branch** — the branch tip is an ancestor of that PR's head. The
   local branch or remote branch is just older than what was merged; nothing unique is
   lost. Requires fetching `refs/pull/<n>/head`, which the script does on demand.

Everything else is reported as `skip`, never deleted. In particular, a branch whose PR
was merged but which has extra commits after the PR head is **not** safe: those commits
were never merged. The script prints the count so the user can decide.

Branches are also skipped when:

- they match the protected regex (`main`, `master`, `develop`, `dev`, `release`, `release/*`,
  `staging`, `homolog`, `production`, `beta`, etc.) — override with `--keep-regex '...'`;
- they are named with `--keep`;
- they are the current branch or checked out in another worktree;
- an **open** PR still uses that branch name;
- they have no merged PR and are not contained in the base branch.

## Flags

| Flag | Effect |
|------|--------|
| *(none)* | Dry-run, local + remote, base auto-detected |
| `--apply` | Actually delete |
| `--local` | Local branches only |
| `--remote` | Remote-tracking branches only (deletes on the remote) |
| `--base <branch>` | Base branch (default: remote HEAD, then `gh`, then `main`/`master`) |
| `--remote <name>` | Remote to inspect and delete from (default: `origin`) |
| `--keep <branch>` | Add one branch to the protected list (repeatable) |
| `--keep-regex <re>` | Replace the protected-branch regex |
| `-h`, `--help` | Usage |

The script is idempotent: a second run finds nothing to delete.

## What it needs

- `git`, inside a work tree.
- `gh` authenticated for squash-merge detection (`gh auth status`). Without it the script
  degrades to ancestry-only detection and says so — most squash-merged branches will be
  reported as `skip`, which is safe but incomplete. Remote-only mode also needs the
  network.

## Gotchas this skill encodes

- **Squash merges are invisible to git.** `git branch -d` fails with "not fully merged"
  for a branch that was squash-merged. Do not "fix" that with `-D` in a loop; verify
  against the merged PR first.
- **The PR head is not always the branch tip.** People push after opening the PR. Compare
  the tip to the PR head and refuse when the tip has commits the PR never had.
- **A local branch can be older than the merged PR.** That is fine (its commits are a
  subset of the PR head) — check ancestor-of-PR-head, not equality.
- **`git for-each-ref refs/remotes/<remote>` includes `<remote>/HEAD`.** Filter it out or
  `git push --delete HEAD` does something you do not want.
- **Long-lived branches have merged PRs too.** `develop`/`release` often show up as the
  head of PRs into `main`. They must be protected by name, not by merge status.
- **Worktrees block deletion.** `git branch -D` refuses a branch checked out elsewhere;
  surface the error instead of forcing.
- **Open PRs can reuse an old branch name.** Delete only after confirming no open PR
  points at it, or a reviewer's branch disappears mid-review.
- **Remote deletion is not local deletion.** `git push origin --delete` is the destructive
  step; run the dry-run first, and re-run `git fetch --prune` afterwards so tracking refs
  disappear.

## Manual fallback (no `gh`)

```bash
git fetch --prune origin
git branch --merged origin/main | grep -vE '^\*|main|develop|release'
# Inspect each candidate before deleting; squash merges will not appear here.
git branch -d <branch>
git push origin --delete <branch>
```

Only trust the ancestry list. Treat everything else as unmerged.
