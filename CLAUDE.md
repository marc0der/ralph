# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is Ralph?

Ralph is an autonomous AI coding agent loop runner. It runs iterative plan/build cycles using a configurable backend (Claude Code, OpenAI Codex, etc.) in headless mode, with shared artifacts (`IMPLEMENTATION_PLAN.md`, `PROGRESS.md`) as handoffs between iterations. All execution happens inside isolated devcontainers.

## Commands

```bash
# Run all tests
bats test/

# Run a single test file
bats test/sandbox.bats

# Run a specific test by name
bats test/sandbox.bats -f "sandbox fails when config is missing"

# Lint
shellcheck ralph install.sh
```

CI runs both ShellCheck and BATS on every push/PR to main.

## Architecture

Ralph is a single Bash script (`ralph`) with these commands:

| Command | Purpose |
|---------|---------|
| `plan` | Run planning loop (default: 3 iterations) — reads specs/source, produces `IMPLEMENTATION_PLAN.md` |
| `build` | Run build loop (default: 50 iterations) — picks next task, implements, tests, commits, pushes |
| `sandbox` | Enter/manage devcontainer (`sandbox`, `sandbox clean`, `sandbox --rebuild`) |
| `init` | Initialize workspace artifacts and directories |
| `archive` | Move artifacts to `.ralph/<timestamp>/` |
| `clean` | Delete artifacts |

### Core loop flow (`cmd_loop`)

1. Validate CLI dependencies (selected backend's CLI binary, git)
2. Resolve backend via `-b` flag (default: `claude`), which loads the backend's command builder, default model, and jq filter
3. Resolve prompt template: project-local `PROMPT_<mode>.md` → installed default (`~/.config/ralph/prompts/`)
4. Substitute `{{GOAL}}` and `{{BACKEND_HINTS}}` into prompt via bash parameter expansion
5. Pipe prompt to the backend command in a loop (e.g., `claude -p` or `codex exec`)
6. Parse JSON output with jq using backend-specific flags and filters, push changes after each iteration

### Sandbox

Uses the `devcontainer` CLI to manage container lifecycle. Key details:
- Base image: Node.js 20 with Claude Code, gh, git, zsh, jq, ripgrep, SDKMAN
- Mounts: workspace, `~/.claude`, `~/.gitconfig`, `~/.ssh`, Docker socket, SSH agent, ralph binary
- Shell history persists via Docker volumes keyed by a hash of the workspace path
- Runs as `node` user with passwordless sudo

### Installation layout

`install.sh` places files at:
- `~/.local/bin/ralph` — CLI binary
- `~/.config/ralph/prompts/` — default plan/build prompt templates
- `~/.config/ralph/templates/` — artifact templates (PROGRESS.md)
- `~/.config/ralph/container/` — devcontainer config + Dockerfile

Override with `RALPH_BIN_DIR` and `RALPH_CONFIG_DIR`.

## Testing conventions

- Tests use **BATS** v1.5.0+ (Bash Automated Testing System)
- Each test gets a fresh temp directory with `git init` and a mock `RALPH_CONFIG_DIR` (see `test/test_helper.bash`)
- Use `skip` with a message when a test can't run on the current platform (e.g., missing `devcontainer` CLI, NixOS PATH isolation issues)
- The `path_without` helper in `sandbox.bats` builds a PATH excluding a specific command — but beware that on NixOS/Ubuntu, coreutils share a directory, so stripping one command may break others

## Shell scripting conventions

- All code lives in the single `ralph` script — no external shell libraries
- Functions are named `cmd_<command>` for top-level commands
- Backend definitions use `backend_<name>` functions that set well-known variables (`BACKEND_CLI`, `BACKEND_DEFAULT_MODEL`, etc.) and define a `build_backend_cmd` inner function — adding a new backend only requires a new function and a `SUPPORTED_BACKENDS` entry
- Use `command -v` to check for CLI dependencies
- Validate early, fail with clear error messages to stderr
- Cross-platform: support both Linux (`md5sum`) and macOS (`md5`) where needed
