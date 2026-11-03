# Brief templates

Concatenate them in this order: `common.md` → optional `phaseN-common.md` → `tN.md`.

## common.md

```markdown
You are an implementation agent in the repo at <ABS_REPO_PATH> (branch <BRANCH>).
Other agents are working IN PARALLEL in other directories of the same checkout.

Before coding, READ: <AGENTS.md / CLAUDE.md> (architecture rules) and
<docs/feature/ROADMAP.md> (decisions and contracts). Follow them exactly. If a contract
looks wrong, do NOT change it. Note it in the final report.

Hard rules:
- Edit ONLY the files/directories listed as yours. Touch nothing else (not the
  roadmap, not <shared types package>).
- Do NOT run git commit, stash, checkout, reset, or anything else that changes git state.
- Do NOT install or add dependencies. They are already installed, and parallel
  installs corrupt the lockfile. If one is missing, stop and say so.
- Do not change the database beyond what your task asks for. Containers: <docker|mocker>.
- Validate only your scope (the commands listed). Do not run build/test on the whole repo.
- Do not stop before your scope's tests pass. If something truly blocks you, stop
  and explain.

Write the final report in <LANGUAGE>, short: files created/changed, validation
commands with the result of each, deviations from the contract, open questions.
```

## phaseN-common.md (when a phase builds on earlier ones)

```markdown
Phase N context: <what already exists, which files to read for patterns, which tests
to imitate (in-memory fakes; DB tests follow <existing example>)>.

Wiring: you do NOT edit <env.ts / app composition files>. Export factories that receive
explicit config/deps (never read env inside the module). In the final report, list
exactly: new env vars (name, type, default) and the suggested wiring snippet.
```

## tN.md

```markdown
# Task TN: <title> (directory: <path/> only)

<What already exists / is pre-installed. What NOT to do.>

Implement <phase X> of <ROADMAP.md> (read sections "<...>").

Architecture:
- <pure core module>: <function signature> over interfaces <A {..}>, <B {..}>.
- Implementations: <adapter 1>, <adapter 2>. <entry> picks one based on <config>.

Behavior:
- <routes / states / error codes / response codes, one bullet each>

Tests (<runner>, deterministic, fakes):
- <one bullet per behavior that must be proven, including concurrency/idempotency>

Validation: `<pkg typecheck>`, `<pkg lint>`, `<pkg test>`.
```

## tN-fix.md (after review)

```markdown
# Task TN-fix: <bug> (files: <exact paths>)

Bug: <concrete failing scenario: inputs → wrong result → consequence>.
Expected: <behavior>. Constraint: <what must not change>.
Add the regression test "<name>" that fails before the fix and passes after.
Validation: <scoped commands>.
```
