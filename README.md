# Skills

[![skills.sh](https://skills.sh/b/itxtoledo/skills)](https://skills.sh/itxtoledo/skills)

My personal AI agent skills collection.

## Quickstart

```bash
# Install all skills
npx skills add itxtoledo/skills

# Install only the mocker skill
npx skills add itxtoledo/skills --skill mocker
```

Pick your agent when prompted (Claude Code, Codex, Cursor, Crush, etc.).

## Reference

### Engineering

Skills I use daily for code work.

- **[mocker](./skills/engineering/mocker/SKILL.md)** — Forces every `docker` command to use `mocker` instead on Apple Silicon macOS 26+. Drop-in replacement for Docker CLI using Apple's native Containerization framework.
- **[apple-app-store-submission](./skills/engineering/apple-app-store-submission/SKILL.md)** — Takes an iOS app from compliance config through a signed build, App Store Connect, and TestFlight to submission. Includes the signing route that works on a team with no registered device, and the console steps that silently discard your input.
- **[opencode-deepseek-orchestration](./skills/engineering/opencode-deepseek-orchestration/SKILL.md)** — Coordinates OpenCode agents on DeepSeek v4.1 Flash (`opencode-go/deepseek-v4.1-flash`) as parallel implementers: the `PWD` invocation gotcha, briefs with exclusive file ownership, index checkpoints, and a review checklist of the bugs these agents reliably miss.
- **[git-merged-branch-cleanup](./skills/engineering/git-merged-branch-cleanup/SKILL.md)** — Deletes merged local and remote branches, including squash-merged ones that `git branch --merged` cannot see. Verifies each branch against its merged PR head, protects long-lived branches, refuses anything with unmerged commits, and ships a dry-run-by-default script.

## Structure

Skills are organized into bucket folders under `skills/`:

- `engineering/` — daily code work
- `productivity/` — daily non-code workflow tools
- `misc/` — kept around but rarely used

Each skill lives in its own directory with a `SKILL.md` file.
