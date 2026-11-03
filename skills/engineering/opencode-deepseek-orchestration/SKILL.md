---
name: opencode-deepseek-orchestration
description: >
  Coordinate OpenCode coding agents running DeepSeek v4.1 Flash
  (`opencode-go/deepseek-v4.1-flash`) as cheap parallel implementers while you act as
  architect, reviewer, and integrator. Use when the user asks you to "coordinate opencode
  agents", "use deepseek flash", "delegate to opencode", or to split a large feature into
  phases implemented by other models. Covers the invocation, briefs, parallel file
  ownership, review, and the bugs these agents reliably miss.
---

# OpenCode + DeepSeek v4.1 Flash orchestration

You are the coordinator. The agents type the code, and you own the design, the contracts,
the review, the integration, and the end-to-end proof. DeepSeek v4.1 Flash is fast and
cheap, and it follows a precise brief well. It does **not** catch cross-module or
financial edge cases by itself. Assume every report is optimistic until you check it.

## 1. Preflight (read-only, no confirmation needed)

```bash
which opencode && opencode --version                 # tested with v2.2.0
opencode models 2>/dev/null | grep -i deepseek       # confirm the exact model id
mkdir -p "$SCRATCH/ping" && cd "$SCRATCH/ping" && \
  PWD=$(pwd) opencode run -m opencode-go/deepseek-v4.1-flash "Reply only: OK"
```

- **Model id**: OpenCode Go exposes `opencode-go/deepseek-v4.1-flash`. There is no plain
  `v4-flash` on Go. If the user says "deepseek v4 flash do opencode go", this is the id.
  Other providers have look-alikes (`deepseek/deepseek-v4.1-flash`,
  `<provider>/deepseek-v4-flash`) that run on a different backend with different quality.
  Use the one the user named, and say so if you substitute.
- Ping in an empty scratch dir. The real run is pointed at the repo.

## 2. Invocation, and the `PWD` gotcha

```bash
cd "$REPO" && PWD="$REPO" opencode run --standalone -m opencode-go/deepseek-v4.1-flash \
  "$(cat "$BRIEFS/common.md" "$BRIEFS/t3.md")" > "$BRIEFS/t3.log" 2>&1
echo "exit $?"; tail -60 "$BRIEFS/t3.log"
```

- **OpenCode uses `$PWD`, not the process cwd, as the project root.** Always set `PWD`
  explicitly. If you `cd` from a wrapper that doesn't update `PWD`, the agent works in
  the wrong tree. In a sandbox setup that can mean it reads and edits files you meant to
  hide.
- **Always pass `--standalone`.** Without it, `opencode run` attaches to the shared
  background OpenCode service. If that service restarts its watchers (for example after
  you add or move a skill under `~/.agents/skills`), the client can hang forever: 0%
  CPU and an empty log. `--standalone` gives each run its own private server.
- **Detect stalls; don't trust "still running".** A healthy run writes its log within
  seconds. If the log size hasn't changed for ~5 minutes, kill that one PID (not every
  opencode process: the user may have their own sessions) and re-run it. The script
  does this automatically (`STALL_SECS`, default 300).
- Run each agent as a **background** shell job, logging to a file, so several run in
  parallel and you are notified when each exits. Don't poll. Do your own review of
  finished tasks while the others run.
- The final report is the tail of the log. A typical run takes 3–15 minutes.
- `scripts/run-agent.sh` wraps all of this: `run-agent.sh <repo> <briefs-dir> <task> [extra-brief...]`.
- Reports sometimes come back **in Chinese** even with a Portuguese or English brief. The
  content is usually fine, so translate it and don't re-run. Adding "Write the final
  report in <language>" to the common brief reduces this.

## 3. Plan before spawning anything

1. Write a **roadmap / contracts doc in the repo** (e.g. `docs/<feature>/ROADMAP.md`).
   It holds the closed decisions, the data contracts (token formats, bucket layout,
   worker API, entity fields, idempotency keys), and the phases as checkboxes with one
   owner and one directory each. Agents read it, you mark `[x]` only after you verify.
2. Do the **shared, conflict-prone edits yourself first**: enums and types used by
   several tasks, new `package.json` files, and **`pnpm install` / dependency adds**.
   Parallel agents running `pnpm install` race on the lockfile and corrupt it. Pin
   versions you have verified exist (an agent once proposed
   `@cloudflare/workers-types@^4.20260924.0`, which was never published).
3. Split into tasks with **exclusive directories**. Tasks that share a file must run in
   sequence. A "wiring" task (env, DI container, router) goes last, or you do it yourself.
4. Run at most ~3 agents at once. More than that and review becomes the bottleneck.

## 4. The brief

Every run gets `common.md` (the same for all tasks) + an optional phase-common file +
the task file. Template: `references/brief-template.md`. These parts are non-negotiable:

- **Read first**: the project's agent rules (AGENTS.md / CLAUDE.md) and the roadmap.
- **Ownership**: "Edit ONLY these paths". List everything else that is off limits
  explicitly, including the roadmap and shared types.
- **Contracts are read-only**: "If a contract looks wrong, do NOT change it. Report it."
  The agents' deviation lists were often where the real bugs showed up.
- **No git state changes**: no commit, stash, checkout, or reset. **No dependency installs**
  when you pre-installed them.
- **Scoped validation**: the exact typecheck/lint/test commands for its package. Not
  the whole repo, because parallel agents would see each other's half-done work.
- **Don't stop until those pass**, but stop and explain if truly blocked.
- **No wiring**: "Export factories with explicit deps. Do not read env inside the module.
  In the report, list the new env vars (name, type, default) and the exact wiring
  snippet." Then you, or one later task, do the wiring once.
- **Final report**: files changed, commands run with their results, contract
  deviations, open questions.

Be concrete about what you want, because the model takes the brief literally: name the
interfaces, the error codes, the response codes, and the tests you expect ("two
concurrent leases never return the same job", "running sync twice doesn't double count").

## 5. Checkpoint, review, integrate

- **Checkpoint with the index, not commits**: `git add -A` after each verified task.
  Then `git diff` (unstaged) shows exactly what the next agent changed. Commit only
  if the user asks.
- For each finished task:
  1. Read the report, especially the **deviations**. Then diff the actual files, because
     reports can overstate.
  2. Check that nothing outside the owned paths changed (`git status`). Agents sometimes
     touch one extra file "because it was the only place". Accept it consciously or
     revert it.
  3. Re-run the scoped validation yourself.
  4. Review the logic against the checklist below, because this is where the misses are.
  5. Small fixes: do them yourself. A larger fix gets a new `tN-fix.md` brief with the
     bug, the expected behavior, and **the regression test to add**.
- At the end, run the **full repo** validation (build, typecheck, lint, test) and a
  **real end-to-end run**. Unit tests passed for every task here, and the E2E still
  found two production bugs.

## 6. Review checklist: what DeepSeek Flash reliably misses

These bugs all made it past tests the agents wrote themselves:

- **Idempotency treated as failure.** A retried charge hit the ledger's
  `DUPLICATE_ENTRY` and was handled as an error, so the account stayed BLOCKED forever.
  A duplicate idempotency key means *already done*, so map it to success.
- **Counters reset at period boundaries.** Resetting usage at renewal loses the unbilled
  usage and races with concurrent increments. Store usage per day/period and derive the
  totals.
- **Missing a branch in a state machine.** The cancel path skipped the final settlement
  that renewal did. Check every terminal transition for the side effects of the normal
  path.
- **Orphaned intermediate states.** Step A commits (`QUEUED`) and then step B
  (`enqueue`) fails, so the row has no job and nothing ever retries it. Ask "what if the
  second write fails?" and add a reaper or requeue sweep.
- **Browser/runtime nuance.** Picking native HLS because `canPlayType` says yes (recent
  Chrome does) lost manual quality switching. A response that sometimes sends CORS
  headers but never `Vary: Origin` poisoned the browser cache for later CORS requests.
  Only a real browser shows these.
- **Spurious generated diffs.** ORM migration generators can emit unrelated
  renames/drops. Agents delete them by hand without saying so. Diff the migration SQL.
- **Unverified versions and APIs.** Check that every new dependency version exists.
- **DI dropped in wiring.** A logger or clock was not passed to a singleton, so it
  silently used the defaults.

## 7. Report to the user

Say what the agents did and what you fixed after review, as separate items. Give the
real validation output, the E2E results, the open decisions, and what is still running.
Never present an agent's self-report as verified.
