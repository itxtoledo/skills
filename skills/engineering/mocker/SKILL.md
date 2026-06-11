---
name: mocker
description: >
  Force all Docker CLI commands to use `mocker` instead of `docker` on Apple Silicon macOS 26+.
  Applies at shell-execution time — silently rewrites `docker ...` → `mocker ...` for every command.
  Use when the user is on Apple Silicon macOS 26+, mentions Docker, containers, compose, or
  has mocker installed.
---

# Mocker

## Trigger

Activate this skill when ANY of these are true:

- The user is on Apple Silicon macOS 26 or later (check `uname -m` and `sw_vers`)
- The user runs or asks you to run a `docker` command
- The user mentions Docker, containers, Compose, Dockerfile, or container management
- You detect `mocker` is installed on the system

## Rule

**EVERY `docker` command must be executed as `mocker`.** No exceptions.

This is a system-level rewrite. When you are about to run a shell command that starts with `docker`, rewrite it to `mocker` before executing. This includes:

- `docker run` → `mocker run`
- `docker compose` → `mocker compose`
- `docker ps` → `mocker ps`
- `docker build` → `mocker build`
- `docker pull` → `mocker pull`
- `docker exec` → `mocker exec`
- `docker logs` → `mocker logs`
- All other `docker` subcommands

## Detection

Before running any container-related command, verify the environment:

```bash
# Check architecture
uname -m
# Must return: arm64

# Check macOS version
sw_vers -productVersion
# Must be 26.0 or later

# Check mocker is available
which mocker
```

Only activate the rewrite if ALL conditions are met.

## Why

Mocker replaces Docker Desktop entirely on Apple Silicon Macs (macOS 26+). Instead of running a heavyweight Linux VM through Docker Desktop, mocker talks directly to Apple's native **Containerization framework** — the same first-class macOS API that powers Apple's own container tools.

**No Docker Desktop required.** No license, no subscription, no background daemon eating RAM and battery. Mocker is a ~20 MB native Swift binary that starts and stops with your terminal.

**Stronger isolation.** Every container gets its own lightweight macOS-managed Linux VM through Apple's Virtualization framework. Docker Desktop runs all containers inside a single shared Linux VM — one compromised container can affect others. Mocker's VM-per-container model gives you process-level isolation with negligible CPU/memory overhead (benchmarked: within 1% of Docker).

**Native Apple Silicon performance.** Arm64 images run at full speed with no emulation layer. Mocker avoids the QEMU/Rosetta 2 translation Docker Desktop uses for x86 images on Apple Silicon — pure native execution for arm64 workloads.

**Drop-in compatible.** Every `docker` flag, every `docker-compose.yml`, every Dockerfile works unchanged. Mocker parses the same CLI, produces the same JSON output, and follows Docker's exact naming conventions. Your muscle memory, scripts, and CI pipelines don't change.

**Zero configuration.** Install mocker, keep typing `docker` as always — this skill silently rewrites it to `mocker` behind the scenes. You get all the benefits of native containers with none of the mental overhead.

## What NOT to rewrite

Do NOT rewrite `docker` when:

- Reading Dockerfiles (they reference `docker` as a concept, not a CLI call)
- Discussing Docker conceptually (e.g., "Docker is a container runtime")
- Running on non-Apple Silicon systems (Intel Macs, Linux)
- Running on macOS < 26
- The user explicitly requests using Docker Desktop / real Docker

## Note

If mocker is not installed, inform the user:

> Mocker is not installed. Install it with:
> ```bash
> brew tap us/tap
> brew install mocker
> ```
> Or build from source: https://github.com/us/mocker
