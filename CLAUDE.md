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
| `build` | Run build loop (default: 50 iterations) — picks next task, implements, tests, commits, pushes |
| `review` | Run review loop (max 6 iterations, exits on convergence) — audits `- [x]` items against the plan items that produced them, files findings as new `- [ ]` items |
| `sandbox` | Enter/manage devcontainer (`sandbox`, `sandbox clean`, `sandbox --rebuild`) |
| `init` | Initialize workspace artifacts and directories |
| `archive` | Move artifacts to `.ralph/<timestamp>/` |
| `clean` | Delete artifacts |

### Core loop flow (`cmd_loop`)

1. Validate CLI dependencies (selected backend's CLI binary, git)
2. Resolve backend via `-b` flag (default: `claude`), which loads the backend's command builder, default model, and jq filter
3. Resolve prompt template: project-local `PROMPT_<mode>.md` → installed default (`~/.config/ralph/prompts/`)
4. Substitute `{{GOAL}}` and then `{{WORKSPACE}}` into the prompt via bash parameter expansion. `{{GOAL}}` expands first, so a goal may itself carry `{{WORKSPACE}}`, and it reaches `plan` alone — `plan` and `auto` require `-g`, and `build` and `review` refuse it. `{{WORKSPACE}}` expands to `$PWD`, the workspace root, which anchors `IMPLEMENTATION_PLAN.md` and `PROGRESS.md` in every prompt
5. Pipe the prompt to the backend command in a loop (e.g., `claude -p` or `codex exec`), writing the raw backend stream to a file — `iter-NNN.stream.jsonl` in the run's directory under `.ralph/metrics/` when metrics are enabled, a per-run temp file otherwise
6. Parse that stream file with the summary jq filter using backend-specific flags, push the workspace after each iteration, skipping when it has no `origin` or no commit. Under `--verbose` the stream is also teed through a per-backend live filter, which renders each tool call and assistant message to stderr as it arrives
7. Detect an early exit. Build mode watches every git repository beneath the workspace, not just the workspace's own `HEAD`, and stops after 2 consecutive iterations in which none of them moved, unless `-n` was passed. `repo_state` builds that listing before and after each pass. Plan and review mode never commit, so `mode_converges_on_plan` routes both through the same check: they fingerprint `IMPLEMENTATION_PLAN.md` plus `specs/` via `plan_state_hash` and stop on the first pass that changes neither; `-n` caps such a run but never disables the check. `convergence_message` derives the exit line from the mode, so a converged review also reports how many specs it audited

Build and review each carry a hard precondition that runs unconditionally beside `require_init_artifacts`, before `hard_override` decides the iteration count. `require_open_items` stops a build whose plan holds no `- [ ]` item. `require_review_preconditions` stops a review unless both artifacts exist, at least one item is `- [x]`, no item is `- [ ]`, and at least one `Spec:` field cites a `specs/` path — review audits a fully shipped plan, so pending work goes through `build` first, and it audits the specs that plan cited, so a plan citing none leaves it nothing to read.

### The implementation plan contract

`specs/` states *what* to build; `IMPLEMENTATION_PLAN.md` states *how*. All three prompts enforce a closed six-field item schema (title, `Spec`, `Scope`, `Files`, `Steps`, `Done when`), a cap of 150 words / 14 lines / 8 steps per item, and Simplified Technical English. The plan file holds exactly three headings and never carries outcomes, evidence or status — those belong in `PROGRESS.md`. `plan` also closes the file with one optional verification item: when the goal or the guardrails file names a full-verification command, the plan keeps one final open item that runs it over the accumulated work, cites `AGENTS.md verification gate` in place of a `specs/` file, and is the one item whose `Done when` is a whole-suite run. When neither names such a command, `plan` writes no verification item.

Items are mutable during the plan phase and immutable during the build phase, where the only legal edits are ticking a checkbox, marking an item `- [~]`, and appending a new item. Markers are `- [ ]`, `- [x]`, and `- [~]` (superseded or blocked). `calculate_build_iterations` counts only `^- \[ \]`, so `[~]` items neither size the build loop nor count as shipped work. When changing these rules, keep `prompts/plan.md`, `prompts/build.md`, `prompts/review.md` and `templates/IMPLEMENTATION_PLAN.md` in agreement — the prompts win on any disagreement.

Review audits spec fidelity. The **anchor set** is the set of distinct `specs/` paths that appear in a `Spec:` field of `IMPLEMENTATION_PLAN.md`, and `cited_specs` derives it from `plan_items_body`, so the exemplar under `## Entry Format` never enters it. It names the specifications this cycle worked from, which is why review reads the plan at all: `specs/` is a chronological record rather than a statement of current requirements, and a pass that read the whole corpus would file drift against correct code. Each spec in the set is audited whole, so a clause `plan` read and never decomposed into an item is in range — that clause is the drift review exists to catch. A `Spec:` field citing `AGENTS.md verification gate`, `CLAUDE.md verification gate` or a rule file names no specification and adds nothing to the set. A spec `plan` read and produced no item from is invisible to review, and that gap is accepted.

A finding carries one of three levels, written as the first word of its title. `Critical` means the tree does not satisfy a clause of a spec in the anchor set; it cites `specs/file.md` plus an item number or a section name, and its range is the whole tree, because it does not matter which item was supposed to deliver the clause or whether any item did. `Major` means the code this cycle committed is defective — a bug, an unhandled error, an unhandled edge case, or a quality problem; a null dereference breaches no specification, so it cites `IMPLEMENTATION_PLAN.md` plus the quoted title of the item whose commits shipped it. `Minor` means that code violates a written rule, and it cites the rule file plus the rule name. The range of `Major` and `Minor` is the cycle's commits, never the whole tree and never an item's `Files`, because `prompts/build.md` lets `build` fix an unrelated red suite outside the `Scope`, and because an unbounded defect sweep re-audits code no cycle touched on every pass forever. A failing suite produces one `Major` for the whole run, citing `IMPLEMENTATION_PLAN.md` with the words `whole plan` in place of a title. Where two levels fit the higher one wins, and every level carries the same burden of proof: name a behaviour or a rule, and show the tree does not have it.

A `Minor` must name the written rule it violates. Rules live in a rules directory whose location the project's `AGENTS.md` or `CLAUDE.md` states — Ralph fixes no path, and in a meta repository the directory resolves per repository, from the guardrails of the repository that owns the path in hand. All three prompts follow that pointer, not review alone: a reviewer that knows the rules and a builder that does not replenishes violations exactly as fast as review drains them. A project that names no rules directory, this one included, produces no `Minor` finding at all. A preference with no written source is unfileable at every level, as are wording no cited clause prescribes, a clause the spec itself marks out of scope, and an item the reviewer would have planned differently.

Review's authority over the plan is additive. It appends items, and it never re-decomposes, re-scopes or re-orders an item `plan` wrote, and never alters a `- [x]` marker: a shipped item whose code fails a cited clause becomes a new `Critical` item, because un-ticking hides that a defect escaped and lets an item oscillate between `[ ]` and `[x]` across review and build runs. Every supersession review makes is recorded in `PROGRESS.md`, because the next plan run resolves a `[~]` item by reading that entry and will otherwise resurrect the item as open. Review reads no spec outside the anchor set and creates or edits nothing under `specs/`, since writing there would manufacture its own standard and defeat convergence — `plan_state_hash` fingerprints `specs/` too. `IMPLEMENTATION_PLAN.md` holds **at most 10 open findings** at one time. The cap is a standing limit on the file, not a per-pass quota, so a pass counts the open items before it writes and files at most the difference, ranking `Critical` above `Major` above `Minor`, dropping the rest into its final message, and converging on a queue already full. One context audits the whole anchor set: the judgement is never split across subagents, because a subagent holding one spec cannot rank its findings against the rest, and slices sum instead of competing. The fourth precondition guards all of this — a plan whose items all cite the verification gate passes the other three gates and still gives review no specification to read.

### Sandbox

Uses the `devcontainer` CLI to manage container lifecycle. Key details:
- Base image: Node.js 20 with Claude Code, gh, git, zsh, jq, ripgrep, Bun, uv, SDKMAN
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
