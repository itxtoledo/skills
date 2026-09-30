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

## Structure

Skills are organized into bucket folders under `skills/`:

- `engineering/` — daily code work
- `productivity/` — daily non-code workflow tools
- `misc/` — kept around but rarely used

Each skill lives in its own directory with a `SKILL.md` file.
