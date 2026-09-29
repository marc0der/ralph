# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is Ralph?

Ralph is an autonomous AI coding agent loop runner. It runs iterative plan/build cycles using a configurable backend (Claude Code, OpenAI Codex, GitHub Copilot CLI, or pi) in headless mode, with shared artifacts (`IMPLEMENTATION_PLAN.md`, `PROGRESS.md`) as handoffs between iterations. All execution happens inside isolated devcontainers.

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
shellcheck test/*.bats test/test_helper.bash
```

CI runs both ShellCheck and BATS on every push/PR to main. Run both locally after every build iteration, before committing — green BATS with a dirty ShellCheck is not done.

## Architecture

Ralph is a single Bash script (`ralph`) with these commands:

| Command | Purpose |
|---------|---------|
| `plan` | Run planning loop (max 6 iterations, exits on convergence) — requires a goal (`-g`), reads specs/source, produces `IMPLEMENTATION_PLAN.md` |
| `build` | Run build loop (default: open items plus 20% headroom) — picks next task, implements, tests, commits, pushes |
| `review` | Run one review pass — reviews the cycle's work against its cited specs, the written rules and the review catalogue, files findings as new `- [ ]` items |
| `sandbox` | Enter/manage devcontainer (`sandbox`, `sandbox clean`, `sandbox --rebuild`) |
| `init` | Initialize workspace artifacts and directories |
| `archive` | Move artifacts to `.ralph/<timestamp>/` |
| `clean` | Delete artifacts |
| `auto` | Run `archive`, `init`, `plan`, `build`, `review`, `build` as child processes — requires `-g`, rejects `-n`, skips a phase whose guard fails, refuses to run outside a container without `--force`, records a failure or interrupt in `.ralph/auto-state` for `--resume` |
| `metrics` | Summarise a run's `metrics.jsonl`, the latest run by default |
| `version` | Print the version |

### Core loop flow (`cmd_loop`)

1. Validate CLI dependencies (selected backend's CLI binary, git)
2. Resolve backend via `-b` flag (default: `claude`), which loads the backend's command builder, default model, and jq filter
3. Resolve prompt template: project-local `PROMPT_<mode>.md` → installed default (`~/.config/ralph/prompts/`)
4. Substitute `{{GOAL}}` and then `{{WORKSPACE}}` into the prompt via bash parameter expansion. `{{GOAL}}` expands first, so a goal may itself carry `{{WORKSPACE}}`, and it reaches `plan` alone — `plan` and `auto` require `-g`, and `build` and `review` refuse it. `{{WORKSPACE}}` expands to `$PWD`, the workspace root, which anchors `IMPLEMENTATION_PLAN.md` and `PROGRESS.md` in every prompt
5. Pipe the prompt to the backend command in a loop (e.g., `claude -p` or `codex exec`), writing the raw backend stream to a file — `iter-NNN.stream.jsonl` in the run's directory under `.ralph/metrics/` when metrics are enabled, a per-run temp file otherwise
6. Parse that stream file with the summary jq filter using backend-specific flags, push the workspace after each iteration, skipping when it has no `origin` or no commit. Under `--verbose` the stream is also teed through a per-backend live filter, which renders each tool call and assistant message to stderr as it arrives
7. Detect an early exit. Build mode watches every git repository beneath the workspace, not just the workspace's own `HEAD`, and stops after 2 consecutive iterations in which none of them moved, unless `-n` was passed. `repo_state` builds that listing before and after each pass. Before its first iteration, build writes that listing to `.ralph/cycle-base` via `write_cycle_base` when the file is absent, so a second build keeps the first build's base. Plan mode never commits, so it fingerprints `IMPLEMENTATION_PLAN.md` plus `specs/` via `plan_state_hash` and stops on the first pass that changes neither; `-n` caps such a run but never disables the check. Review runs exactly one pass and rejects `-n`. `mode_converges_on_plan` still names review, because the metrics `noop` flag reads the plan fingerprint for modes that never commit, but the early exit never fires. After the pass, review prints `Review filed N findings. Reviewed S specs and F changed files.`, counting the open items, `cited_specs` and `cycle_changed_files`, whether or not the plan changed, so a clean review stays distinguishable from a backend that did nothing

Build and review each carry a hard precondition that runs unconditionally beside `require_init_artifacts`, before `hard_override` decides the iteration count. `require_open_items` stops a build whose plan holds no `- [ ]` item. `require_review_preconditions` stops a review unless both artifacts exist, at least one item is `- [x]`, no item is `- [ ]`, and `.ralph/cycle-base` exists — review audits a fully shipped plan, so pending work goes through `build` first, and it bounds the cycle's work by the base, so a cycle with no base leaves it no range to read.

`auto`'s phase guards call `have_open_items` and `have_shipped_items`, the same predicates `require_open_items` and `require_review_preconditions` use, so `auto` never starts a child that exits 1 on a gate, and a change to either hard stop changes its guard with it. The artifact-presence check and the cycle-base check are the exceptions: `cmd_auto` duplicates them inline, skipping review with `skipped — no cycle base`, so keep them in step with `require_init_artifacts` and `require_review_preconditions` by hand.

### The implementation plan contract

`specs/` states *what* to build; `IMPLEMENTATION_PLAN.md` states *how*. All three prompts enforce a closed six-field item schema (title, `Spec`, `Scope`, `Files`, `Steps`, `Done when`), a cap of 150 words / 14 lines / 8 steps per item, and Simplified Technical English. The plan file holds exactly three headings and never carries outcomes, evidence or status — those belong in `PROGRESS.md`. `plan` also closes the file with one optional verification item: when the goal or the guardrails file names a full-verification command, the plan keeps one final open item that runs it over the accumulated work, cites `AGENTS.md verification gate` in place of a `specs/` file, and is the one item whose `Done when` is a whole-suite run. When neither names such a command, `plan` writes no verification item.

Items are mutable during the plan phase and immutable during the build phase, where the only legal edits are ticking a checkbox, marking an item `- [~]`, and appending a new item. Markers are `- [ ]`, `- [x]`, and `- [~]` (superseded or blocked). `calculate_build_iterations` counts only `^- \[ \]`, so `[~]` items neither size the build loop nor count as shipped work. When changing these rules, keep `prompts/plan.md`, `prompts/build.md`, `prompts/review.md` and `templates/IMPLEMENTATION_PLAN.md` in agreement — the prompts win on any disagreement.

Review is the cycle's gatekeeper: one pass that decides what must be fixed before the cycle's work counts as done. Repetition belongs to cycles, never to passes within one review — `auto` runs one cycle, so it reviews once. A **cycle** ends when its artifacts are archived or cleaned, and `.ralph/cycle-base` is one of them. The base holds one `<repo> <sha>` line per repository in `repo_state` format, with `-` for a repository that has no commits. The **cycle's work** is every change between the base and `HEAD` in every repository the base lists, plus every tracked file of a repository absent from the base or recorded as `-`. Review reads the base and never writes it.

A finding measures the tree against one of three standards of equal weight. **Spec clauses** come from the **anchor set**, the distinct `specs/` paths in a `Spec:` field of `IMPLEMENTATION_PLAN.md`, which `cited_specs` derives from `plan_items_body`, so the exemplar under `## Entry Format` never enters it. Review reads each spec in the set whole and no spec outside it, because `specs/` is a chronological record, and a pass that read the whole corpus would file drift against correct code. A clause is in range whether or not an item decomposed it, and its range is the whole tree. An empty anchor set is legitimate: that cycle has no spec standard, and the other two still apply. **Written rules** live in a rules directory whose location the project's `AGENTS.md` or `CLAUDE.md` states — Ralph fixes no path, and in a meta repository the directory resolves per repository. A project that names none, this one included, produces no rule finding. **Code quality** findings name one kind from the closed **review catalogue** in `prompts/review.md` — Bug, Unverified assumption, Weak test, Untested behaviour, Vacuous assertion, Cross-item duplication, Misleading text, Stale docs, Needless comment — and pass that kind's test of proof. Mechanical checks belong to the project's linters, and review never re-checks them. `prompts/build.md` carries the catalogue word for word, because a reviewer that knows a rule and a builder that does not replenishes violations as fast as review drains them.

Rules and code quality range over defects the cycle's work causes, wherever they show: a finding must trace to a change between the base and `HEAD`, and a defect that predates the base and no change touches is out of range. Review runs the full verification command, and a red suite produces one finding for the whole cycle. Every finding is falsifiable: it names its standard and proves the tree fails it. A preference, a decomposition the reviewer would have planned differently, and a finding that fails its test are unfileable. A defect in the cycle's work is a finding even when the code does exactly what its item said.

Severity measures consequence, whatever the standard, and is the first word of the title. `Critical` means the code produces wrong behaviour or fails a cited clause under a reachable condition, however latent, and proves itself by argument when it cannot reproduce. `Major` means a safety net is missing, so the next change is likely to break something unnoticed. `Minor` means the code misleads or burdens its reader. The `Spec` field names the standard: `specs/file.md` plus an item or section, the rule file plus the rule name, `review catalogue` plus the kind name, or `AGENTS.md verification gate` / `CLAUDE.md verification gate` for a red suite. Only the first form enters the anchor set.

Review files every finding that passes its test, with no cap. Several instances of one `Major` or `Minor` kind merge into one item; every `Critical` is its own item. Findings are appended below the last item, `Critical` first, and review never edits, reorders, ticks, un-ticks or supersedes an item, nor creates or edits anything under `specs/`. The pass examines the cycle's work through four **lenses** — spec fidelity, correctness, tests, and text and structure — which a backend with subagents runs in parallel. Each lens returns candidates with their proof; the main context verifies, merges duplicates across lenses, groups, ranks and writes. Review appends one `PROGRESS.md` entry carrying the coverage line `Reviewed N of M specs and X of Y changed files.`, the out-of-range defects, and the questions it could not settle.

### Sandbox

Uses the `devcontainer` CLI to manage container lifecycle. Key details:
- Base image: Node.js 20 with Claude Code, Codex CLI, Copilot CLI, pi, Docker CLI, gh, git, zsh, jq, ripgrep, Bun, uv, SDKMAN
- Mounts: workspace, `~/.claude` (with `settings.json` read-only), `~/.codex`, `~/.copilot`, `~/.pi`, `~/.gitconfig`, `~/.ssh`, `~/.config/gh`, Docker socket, SSH agent, optional GPG agent socket with `pubring.kbx`, ralph binary, ralph config dir
- Forwards API keys and a GitHub token, deriving `GH_TOKEN` from `gh auth token` when neither token is set
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

## Workflow conventions

- Follow the [Conventional Commits](https://www.conventionalcommits.org/) standard: `<type>(<scope>): <subject>`, imperative subject of at most 50 characters, optional body of at most 3 bulleted lines.
- Produce fine-grained atomic commits. When the working tree contains separable concerns, split them into separate commits in dependency order.
- `prompts/build.md` states the same rules for the agent inside the sandbox; keep the two in agreement.

## Shell scripting conventions

- All code lives in the single `ralph` script — no external shell libraries
- Functions are named `cmd_<command>` for top-level commands
- Backend definitions use `backend_<name>` functions that set well-known variables (`BACKEND_CLI`, `BACKEND_DEFAULT_MODEL`, `BACKEND_JQ_LIVE`, etc.) and define a `build_backend_cmd` inner function — adding a new backend only requires a new function and a `SUPPORTED_BACKENDS` entry
- Use `command -v` to check for CLI dependencies
- Validate early, fail with clear error messages to stderr
- Cross-platform: support both Linux (`md5sum`) and macOS (`md5`) where needed
