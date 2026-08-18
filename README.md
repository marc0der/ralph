<p align="center">
  <img src="assets/ralph-loop-logo.png" alt="Ralph Loop mascot" width="600">
</p>

# ralph

Autonomous AI coding agent loop runner. Runs plan and build phases in a loop, feeding structured prompts to an AI coding agent in headless mode. Supports multiple backends — currently [Claude Code](https://claude.ai/code), [OpenAI Codex](https://openai.com/index/codex/), [GitHub Copilot CLI](https://github.com/features/copilot), and [pi](https://www.npmjs.com/package/@earendil-works/pi-coding-agent).

## Background

Ralph implements the [Ralph Wiggum pattern](https://github.com/ghuntley/how-to-ralph-wiggum) — a technique for running AI coding agents in autonomous loops where each iteration picks up where the last left off. The name comes from Ralph Wiggum's famous line *"I'm helping!"*, which captures the spirit of an agent that cheerfully works through a task list one item at a time, without needing hand-holding between steps.

The pattern works in two phases: **plan** (analyse the codebase against specifications and produce a prioritised implementation plan) and **build** (pick the next item, implement it, run tests, commit, repeat). A shared `IMPLEMENTATION_PLAN.md` acts as the handoff between iterations, giving each fresh Claude session the context it needs to continue. The plan is split for context economy: `IMPLEMENTATION_PLAN.md` is an index of one-line entries, each linking to a task file under `plan/` that holds the detail, so an iteration reads the whole queue but only the one task it is about to implement. An append-only `PROGRESS.md` log captures what each iteration did, what it learned, and what broke — providing a breadcrumb trail for both the human and future iterations.

## Install

```bash
git clone git@github.com:marc0der/ralph.git
cd ralph
./install.sh
```

This places `ralph` in `~/.local/bin/`, default prompts in `~/.config/ralph/prompts/`, workspace templates in `~/.config/ralph/templates/`, and the devcontainer config in `~/.config/ralph/container/`.

## Commands

| Command           | Description                                                                  |
|-------------------|------------------------------------------------------------------------------|
| `sandbox`         | Enter a devcontainer shell for the current project                           |
| `sandbox clean`   | Remove the devcontainer for the current project                              |
| `sandbox --rebuild` | Rebuild the container image from scratch                                   |
| `sandbox --no-inhibit-sleep` | Don't hold the host awake for the sandbox session                    |
| `plan`            | Analyse specs and source, create/update `IMPLEMENTATION_PLAN.md` and the task files under `plan/` (default: 3 iterations) |
| `build`           | Pick the next item, implement, test, commit, push (default: 50 iterations)   |
| `review`          | Review the branch diff against specs and guardrails, write `REVIEW.md` — changes nothing else (default: 1 iteration) |
| `init`            | Initialise workspace (`PROGRESS.md`, `IMPLEMENTATION_PLAN.md`, `specs/`, `plan/`). Pass `--prompts` to also copy prompt templates for local customisation |
| `archive`         | Move `IMPLEMENTATION_PLAN.md`, `PROGRESS.md` and `plan/` task files to `.ralph/<timestamp>/` |
| `clean`           | Delete `IMPLEMENTATION_PLAN.md`, `PROGRESS.md` and `plan/` task files       |
| `metrics`         | Summarise a run's loop metrics: per-iteration table plus totals (latest run, or pass a `metrics.jsonl` path) |
| `version`         | Print version                                                                |

### Options (plan, build and review)

| Flag                 | Description                                              |
|----------------------|----------------------------------------------------------|
| `-n`, `--iterations` | Max iterations                                           |
| `-g`, `--goal`       | Goal injected into the prompt template                   |
| `-m`, `--model`      | Model to use (default depends on backend)                |
| `-b`, `--backend`    | Backend to use: `claude`, `codex`, `copilot`, `pi` (default: `claude`) |
| `--skip-push`        | Don't push after each build iteration (plan and review never push) |
| `--dry-run`          | Print what would be executed without running              |
| `--no-metrics`       | Don't record per-iteration metrics under `.ralph/metrics/` |
| `-h`, `--help`       | Show help                                                |

### Review

`ralph review` runs a single read-only verification pass over the current branch: it diffs against the merge base with the default branch, maps every substantive change back to a spec or plan item, flags over-engineering (speculative abstraction, single-caller indirection, pattern duplication), and checks test integrity (weakened, deleted, or missing tests) and guardrail conformance. The output is `REVIEW.md` — verdict, traceability table, severity-ordered findings, and questions for the author — and nothing else: no source edits, no commits, no pushes. Use `-g` to narrow the focus or name a different diff base, and `-n` to run more than one pass. `REVIEW.md` is local-only (gitignored by `ralph init`), like the other loop artifacts.

### Loop metrics

Every real (non-dry-run) `plan` or `build` run records one JSON line per iteration to `.ralph/metrics/<branch>-<timestamp>-<pid>/metrics.jsonl`, alongside the raw backend event stream (`iter-NNN.stream.jsonl`) for deeper analysis. Captured per iteration: wall-clock and API duration, turn count, cost (USD), token usage (input, output, cache read/write), git activity (commits, files changed, insertions/deletions), `IMPLEMENTATION_PLAN.md` items completed, a tool-call histogram, and a noop flag. The loop prints a one-line summary after each iteration, and `ralph metrics` prints the per-iteration table and run totals. Result-event fields are populated for the `claude` backend; other backends record timing and git activity with the rest as nulls. `.ralph/` is gitignored by `ralph init`, so metrics never touch the working tree the loop commits from.

### Examples

```bash
ralph sandbox                                       # enter devcontainer
ralph sandbox --rebuild                             # rebuild and enter
ralph sandbox --no-inhibit-sleep                    # enter without holding the host awake
ralph sandbox clean                                 # remove the container
ralph plan                                          # analyse and plan
ralph plan -g "Migrate to hexagonal architecture"   # plan with a goal
ralph build                                         # implement next item
ralph build -n 10 -m sonnet                         # 10 iterations with sonnet
ralph build -b codex                                # build using codex backend
ralph plan -b codex -g "design the auth module"     # plan with codex
ralph build --dry-run -b codex                      # dry-run with codex
ralph build -b copilot -n 10                        # 10 iterations with copilot
ralph build -b pi -n 10                             # 10 iterations with pi
ralph review                                        # review the branch, write REVIEW.md
ralph review -g "Focus on FT-001 rule coverage"     # review with a focus
ralph archive                                       # archive before starting fresh
ralph init                                          # initialise workspace
ralph init --prompts                                # also copy prompts for customisation
```

## Sandbox

The sandbox runs your project inside a devcontainer — an isolated environment with Claude Code, Codex CLI, GitHub Copilot CLI, Node.js 20, Bun, uv, SDKMAN, Docker CLI, and development tools pre-installed. The active backend runs as a non-root user with its backend-specific permission-bypass flag enabled.

### Prerequisites

- **Docker** (rootful) — rootless Docker is not supported
- **devcontainer CLI** — install with `npm install -g @devcontainers/cli`

### Usage

```bash
cd your-project
ralph sandbox              # start or reuse container, drop into zsh
ralph sandbox --rebuild    # rebuild image from scratch (after ralph updates)
ralph sandbox clean        # remove the container for this project
```

Each project gets its own container, automatically reused between sessions. Shell history persists across container recreations via a Docker volume.

A devcontainer is suspended along with its host, which stalls a long unattended `ralph build` run mid-iteration if the laptop sleeps. `ralph sandbox` holds the host awake for the duration of the session using the platform's sleep inhibitor — `caffeinate` on macOS, `systemd-inhibit` on Linux — releasing it on exit or Ctrl-C. If neither is available, ralph prints a warning and continues. Pass `--no-inhibit-sleep` to opt out.

### What gets mounted

| Source                    | Target                          | Mode      |
|---------------------------|---------------------------------|-----------|
| `~/.claude`               | `/home/node/.claude`            | read/write |
| `~/.codex`                | `/home/node/.codex`             | read/write |
| `~/.copilot`              | `/home/node/.copilot`           | read/write |
| `~/.pi`                   | `/home/node/.pi`                | read/write |
| `~/.gitconfig`            | `/home/node/.gitconfig`         | readonly  |
| `~/.ssh`                  | `/home/node/.ssh`               | readonly  |
| `~/.config/gh`            | `/home/node/.config/gh`         | readonly  |
| Docker socket             | `/var/run/docker.sock`          | read/write |
| SSH agent socket           | `/tmp/ssh-agent.sock`           | read/write |
| `ralph` binary            | `/usr/local/bin/ralph`          | readonly  |
| ralph config dir           | `/home/node/.config/ralph`      | readonly  |

Optional mounts (`~/.ssh`, `~/.config/gh`, `~/.codex`, `~/.copilot`, `~/.pi`, SSH agent) are skipped if the source doesn't exist on the host. `OPENAI_API_KEY`, `GEMINI_API_KEY`, `GH_TOKEN`, and `GITHUB_TOKEN` are forwarded into the container when set on the host. When neither `GH_TOKEN` nor `GITHUB_TOKEN` is set, ralph derives the token from `gh auth token` so keyring-stored `gh auth login` sessions propagate into the container (modern `gh` keeps the token in the OS keyring, which the `~/.config/gh` mount alone cannot carry). If `gh` is installed but logged out, ralph prints a warning and starts the sandbox without GitHub CLI authentication.

### SDKMAN

SDKMAN is installed but no JDK is pre-installed. If your project uses a `.sdkmanrc`, install the declared JDK inside the sandbox:

```bash
sdk env install
```

## Prompt resolution

Ralph looks for prompts in this order:

1. **Project-local** — `PROMPT_plan.md` / `PROMPT_build.md` / `PROMPT_review.md` in the working directory
2. **Installed defaults** — `~/.config/ralph/prompts/plan.md` / `build.md` / `review.md`

The default prompts reference Anthropic model names (Sonnet, Opus) for subagent selection. If you're using a non-Claude backend, run `ralph init --prompts` to copy the defaults into your project and edit them to suit your backend.

## Project artifacts

Ralph iterations create and maintain these files in your project:

| File                     | Purpose                                                       |
|--------------------------|---------------------------------------------------------------|
| `CLAUDE.md`              | Operational guardrails for the Claude backend — build commands, conventions, project rules. Read by every iteration to orient the agent. You maintain this file; ralph does not create or modify it |
| `AGENTS.md`              | Operational guardrails for the Codex backend — equivalent of `CLAUDE.md` for codex projects |
| `IMPLEMENTATION_PLAN.md` | Prioritised index of work items, one line each — shared state between iterations |
| `plan/`                  | One `NNN-slug.md` task file per plan item, holding its scope, files and verification criteria |
| `PROGRESS.md`            | Append-only log of what each iteration did, learned, and broke|
| `REVIEW.md`              | Output of `ralph review` — verdict, traceability, findings    |
| `specs/`                 | Feature specifications driving the work                       |

**Note:** `CLAUDE.md` and `AGENTS.md` are your project's own configuration files for Claude Code and Codex respectively — ralph reads them but never creates or modifies them. The prompt templates reference both files so each backend gets relevant project-specific guidance.

`PROMPT_plan.md`, `PROMPT_build.md` and `PROMPT_review.md` are optional project-local prompt overrides (see [Prompt resolution](#prompt-resolution)).

### Plan layout

Every build iteration re-reads the plan in full, so the plan is deliberately split in two: a small index that is always read, and per-task detail that is only read when it is about to be worked on.

`IMPLEMENTATION_PLAN.md` holds one line per item, in priority order:

```markdown
- [x] **Add PATCH endpoint** — accept partial updates on `/items/{id}`. → [001-patch-endpoint.md](plan/001-patch-endpoint.md)
- [ ] **Wire up token refresh** — refresh expiring sessions without a re-login. → [002-token-refresh.md](plan/002-token-refresh.md)
```

Each entry links to `plan/NNN-slug.md`, which carries the scope, the files involved, the "done when" criteria, and — once the item ships — the build agent's completion notes:

```markdown
# 002. Wire up token refresh

**Status:** Not started

## Scope
...

## Done when
...
```

Numbers are allocated in order and never reused. Completed items and their task files are never deleted — the plan is an append-only ledger of what shipped.

Completion notes live in the task file, capped at about three lines, with the fuller narrative going to `PROGRESS.md`. What they never go in is the index — that's the file every iteration re-reads in full, so it stays one line per item however much history accumulates behind it.

**Note:** `ralph init` adds `plan/` to `.gitignore`, since task files are loop-local state. If your project already has a tracked `plan/` directory, rename one of them before running ralph — `clean` and `archive` only ever touch files matching the `NNN-slug.md` pattern, but the gitignore entry would still hide your own new files from git.

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

## Commit conventions

The build phase commits via the `/commit` skill bundled with ralph and scaffolded by `ralph init` into `.claude/skills/commit/SKILL.md`. The skill enforces an opinionated style:

- **[Conventional Commits](https://www.conventionalcommits.org/)** — `<type>(<scope>): <short imperative subject>`
- **Atomic** — separable concerns become separate commits, even within a single build iteration
- **Selective staging** — only the paths belonging to the current commit are staged; never `git add -A`
- **Optional short body** — up to 3 bulleted lines summarising what was implemented, only when the subject isn't self-explanatory
- Loop-local artifacts (`IMPLEMENTATION_PLAN.md`, `plan/`, `PROGRESS.md`, `PROMPT_*.md`, `.ralph/`) are never staged

The scaffolded skill lives in your project's `.claude/skills/` and is not gitignored by `ralph init` — commit it to share with your team, or edit it locally if you want different conventions.

## Permissions and safety

Ralph runs backends in non-interactive pipe mode, which cannot prompt for tool approval. Each backend has its own permission-bypass flag (`--dangerously-skip-permissions` for Claude, `--dangerously-bypass-approvals-and-sandbox` for Codex, `--yolo` for Copilot), and ralph applies the appropriate one automatically.

**Inside the sandbox** (`$DEVCONTAINER=true`), this is the intended setup — the container's isolation provides a safety boundary, so unrestricted tool access is acceptable.

**Outside a container**, ralph will print a prominent warning on each run. Use `ralph sandbox` to run inside a devcontainer for safer execution.

## Configuration

| Variable           | Default              | Description                     |
|--------------------|----------------------|---------------------------------|
| `RALPH_BIN_DIR`    | `~/.local/bin`       | Where to install the CLI        |
| `RALPH_CONFIG_DIR` | `~/.config/ralph`    | Where to store prompts and container config |

### Model selection

The default model depends on the selected backend:

- `claude` backend: `opus`
- `codex` backend: `gpt-5.2-codex`
- `copilot` backend: `claude-sonnet-4.6`
- `pi` backend: `anthropic/claude-opus-4-8`

The `-m` flag overrides the default for whichever backend is active:

```bash
ralph build -m sonnet          # faster and cheaper (claude backend)
ralph plan -m opus             # better for complex reasoning (claude backend)
ralph build -b codex           # uses gpt-5.2-codex by default
ralph build -b codex -m o3     # override codex model
ralph build -b copilot         # uses claude-sonnet-4.6 by default
```

## Development

Enter the Nix shell to get development dependencies (bats, shellcheck):

```bash
nix-shell
```

Run tests and lint:

```bash
bats test/
shellcheck ralph install.sh
shellcheck test/*.bats test/test_helper.bash
```

## Troubleshooting

**`claude` CLI not installed**
Ralph requires the Claude Code CLI for the `claude` backend. Install it from https://docs.anthropic.com/en/docs/claude-code — ralph will exit with a clear error if it can't find `claude` in your PATH.

**`codex` CLI not installed**
Ralph requires the Codex CLI for the `codex` backend. Install it with `npm install -g @openai/codex` — ralph will exit with a clear error if it can't find `codex` in your PATH.

**`copilot` CLI not installed**
Ralph requires the GitHub Copilot CLI for the `copilot` backend. Install it with `npm install -g @github/copilot` — ralph will exit with a clear error if it can't find `copilot` in your PATH.

**`pi` CLI not installed**
Ralph requires the pi CLI for the `pi` backend. Install it with `npm install -g @earendil-works/pi-coding-agent` — ralph will exit with a clear error if it can't find `pi` in your PATH.

**`ralph` not in PATH after install**
The installer places `ralph` in `~/.local/bin` by default. Ensure this directory is in your PATH:
```bash
export PATH="$HOME/.local/bin:$PATH"
```

**Push rejected / diverged branch**
If `git push` fails due to diverged history, pull and resolve conflicts manually, then re-run `ralph build` to continue.

**Resuming after a failed iteration**
Just re-run `ralph build`. It picks up from the current state of `IMPLEMENTATION_PLAN.md` and the task files under `plan/` — no special recovery step is needed.

**Sandbox container is stale or broken**
Remove it and start fresh:
```bash
ralph sandbox clean
ralph sandbox
```

**Sandbox image needs updating**
After updating ralph, rebuild the container image:
```bash
ralph sandbox --rebuild
```

**`devcontainer` CLI not installed**
Install it with npm:
```bash
npm install -g @devcontainers/cli
```

**`sandbox` fails with `invalid mount config for type "bind": ... operation not supported`**

Ralph bind-mounts `$SSH_AUTH_SOCK` into the container so git operations can reuse your host's ssh-agent. This fails when the socket lives at a path the Docker runtime's VM cannot bind-mount — either because the path is outside the VM's shared filesystem, or because the socket is a kernel-managed endpoint (e.g. a launchd-created socket on macOS) that doesn't survive the virtfs passthrough.

The symptom is a `docker run` error naming the SSH agent path, for example:

```
invalid mount config for type "bind": stat /private/tmp/com.apple.launchd.XXXXXX/Listeners: operation not supported
```

When this happens, depends on your setup:

- **macOS + Colima** — affected. Colima runs Docker inside a Lima VM that only mounts `$HOME` by default, and macOS's default `$SSH_AUTH_SOCK` points at a launchd socket under `/private/tmp/com.apple.launchd.*` which is neither mounted nor bind-mountable.
- **macOS + Docker Desktop** — not typically affected. Docker Desktop intercepts `$SSH_AUTH_SOCK` and provides a magic `/run/host-services/ssh-auth.sock` passthrough.
- **macOS + Rancher Desktop / OrbStack / other Lima-based runtimes** — likely affected for the same reason as Colima.
- **Linux** — not affected. Docker runs natively on the host filesystem.

Workaround: run ralph with an empty `SSH_AUTH_SOCK` so the mount is skipped. Git inside the container will fall back to the read-only `~/.ssh` bind mount (fine for key-based auth without a passphrase):

```bash
SSH_AUTH_SOCK="" ralph sandbox
```
