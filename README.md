# ralph

Autonomous [Claude Code](https://claude.ai/code) loop runner. Runs plan and build phases in a loop, feeding structured prompts to Claude in headless mode.

## Background

Ralph implements the [Ralph Wiggum pattern](https://github.com/ghuntley/how-to-ralph-wiggum) — a technique for running AI coding agents in autonomous loops where each iteration picks up where the last left off. The name comes from Ralph Wiggum's famous line *"I'm helping!"*, which captures the spirit of an agent that cheerfully works through a task list one item at a time, without needing hand-holding between steps.

The pattern works in two phases: **plan** (analyse the codebase against specifications and produce a prioritised implementation plan) and **build** (pick the next item, implement it, run tests, commit, repeat). A shared `IMPLEMENTATION_PLAN.md` acts as the handoff between iterations, giving each fresh Claude session the context it needs to continue. An append-only `PROGRESS.md` log captures what each iteration did, what it learned, and what broke — providing a breadcrumb trail for both the human and future iterations.

## Install

```bash
git clone git@github.com:marc0der/ralph.git
cd ralph
./install.sh
```

This places `ralph` in `~/.local/bin/`, default prompts in `~/.config/ralph/prompts/`, and workspace templates in `~/.config/ralph/templates/`.

## Commands

| Command   | Description                                                                  |
|-----------|------------------------------------------------------------------------------|
| `plan`    | Analyse specs and source, create/update `IMPLEMENTATION_PLAN.md` (default: 3 iterations) |
| `build`   | Pick the next item, implement, test, commit, push (default: 50 iterations)   |
| `init`    | Initialise workspace (`PROGRESS.md`, `IMPLEMENTATION_PLAN.md`, `specs/`). Pass `--prompts` to also copy prompt templates for local customisation |
| `archive` | Move `IMPLEMENTATION_PLAN.md` and `PROGRESS.md` to `.ralph/<timestamp>/`    |
| `clean`   | Delete `IMPLEMENTATION_PLAN.md` and `PROGRESS.md`                           |
| `version` | Print version                                                                |

### Options (plan and build)

| Flag                 | Description                              |
|----------------------|------------------------------------------|
| `-n`, `--iterations` | Max iterations                           |
| `-g`, `--goal`       | Goal injected into the prompt template   |
| `-m`, `--model`      | Claude model (default: `opus`)           |
| `-h`, `--help`       | Show help                                |

### Examples

```bash
ralph plan                                          # analyse and plan
ralph plan -g "Migrate to hexagonal architecture"   # plan with a goal
ralph build                                         # implement next item
ralph build -n 10 -m sonnet                         # 10 iterations with sonnet
ralph archive                                       # archive before starting fresh
ralph init                                          # initialise workspace
ralph init --prompts                                # also copy prompts for customisation
```

## Prompt resolution

Ralph looks for prompts in this order:

1. **Project-local** — `PROMPT_plan.md` / `PROMPT_build.md` in the working directory
2. **Installed defaults** — `~/.config/ralph/prompts/plan.md` / `build.md`

Run `ralph init --prompts` to copy the defaults into your project for customisation.

## Project artifacts

Ralph iterations create and maintain these files in your project:

| File                     | Purpose                                                       |
|--------------------------|---------------------------------------------------------------|
| `CLAUDE.md`              | Operational guardrails — build commands, conventions, project rules. Read by every iteration to orient the agent. You maintain this file; ralph does not create or modify it |
| `IMPLEMENTATION_PLAN.md` | Prioritised task list — shared state between iterations       |
| `PROGRESS.md`            | Append-only log of what each iteration did, learned, and broke|
| `specs/`                 | Feature specifications driving the work                       |

**Note:** `CLAUDE.md` is your project's own configuration file for Claude Code — ralph reads it but never creates or modifies it. See the [Claude Code documentation](https://docs.anthropic.com/en/docs/claude-code) for details on how to set it up.

`PROMPT_plan.md` and `PROMPT_build.md` are optional project-local prompt overrides (see [Prompt resolution](#prompt-resolution)).

### Starting a new goal

When switching to a new goal, clear out stale artifacts first:

```bash
ralph archive                                    # move to .ralph/<timestamp>/
ralph plan -g "New goal"
```

Or if you don't need the history:

```bash
ralph clean                                      # delete artifacts
ralph plan -g "New goal"
```

Archived artifacts are stored under `.ralph/` in your project directory, organised by timestamp.

## Permissions and safety

Ralph runs `claude -p` (non-interactive pipe mode), which cannot prompt for tool approval. This means `--dangerously-skip-permissions` is always enabled.

**Inside a devcontainer** (`$DEVCONTAINER=true`), this is the intended setup — the container's network firewall and ephemeral environment provide isolation, so unrestricted tool access is safe.

**Outside a container**, ralph will print a prominent warning on each run. If you're concerned about unrestricted tool access, use the provided devcontainer configuration for safer execution.

## Configuration

| Variable           | Default              | Description                     |
|--------------------|----------------------|---------------------------------|
| `RALPH_BIN_DIR`    | `~/.local/bin`       | Where to install the CLI        |
| `RALPH_CONFIG_DIR` | `~/.config/ralph`    | Where to store default prompts  |

### Model selection

Ralph defaults to `opus` (`-m opus`). You can switch models per run:

```bash
ralph build -m sonnet          # faster and cheaper
ralph plan -m opus             # better for complex reasoning
```

Use **opus** for planning, architecture decisions, and tasks requiring deep reasoning. Use **sonnet** for straightforward implementation, simple fixes, and faster iteration cycles.

## Troubleshooting

**`claude` CLI not installed**
Ralph requires the Claude Code CLI. Install it from https://docs.anthropic.com/en/docs/claude-code — ralph will exit with a clear error if it can't find `claude` in your PATH.

**`ralph` not in PATH after install**
The installer places `ralph` in `~/.local/bin` by default. Ensure this directory is in your PATH:
```bash
export PATH="$HOME/.local/bin:$PATH"
```

**Push rejected / diverged branch**
If `git push` fails due to diverged history, pull and resolve conflicts manually, then re-run `ralph build` to continue.

**Resuming after a failed iteration**
Just re-run `ralph build`. It picks up from the current state of `IMPLEMENTATION_PLAN.md` — no special recovery step is needed.
