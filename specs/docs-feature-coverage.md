# Documentation Coverage of the Shipped Feature Set

`ralph --help` describes every command and flag the script accepts. The README and the agent
guardrails (`CLAUDE.md`, `AGENTS.md`) do not. `auto` shipped with a complete `usage()` entry, as
`specs/auto-lifecycle.md` §9 required, but that spec prescribed no README or guardrail change, so
neither file tells a reader what `auto` is. Other passages have drifted from the script: a build
default that no longer exists, a flag that is missing, a stale description of review, and a sandbox
description that has fallen behind the mounts and environment variables `cmd_sandbox` forwards.

This spec closes those gaps. It changes documentation and one set of stale ShellCheck comments. It
changes no behaviour.

## 1. Model

`usage()` is the reference for flags and commands, and it is correct today. The README is the user's
guide and must name every command `usage()` lists, and every flag in the shared options block.
`CLAUDE.md` and `AGENTS.md` are the contract the agent reads, and their command table must list every
arm of the main dispatch.

The README stays proportionate, as `specs/review-phase.md` §12 established for review. `auto` gets
one short subsection, not an essay. It does not restate `specs/auto-lifecycle.md`; it states what a
user must know before running the command.

## 2. `auto` in the README

### 2.1 Commands table

Add one row to `## Commands`, after `review`, at the density of the `plan` row:

```
| `auto`            | Run the whole lifecycle unattended: archive, init, plan, build, review, build. Requires `-g`; refuses to run outside a container |
```

### 2.2 Options heading

`### Options (plan, build and review)` becomes `### Options (plan, build, review and auto)`. The
`-n` row states that `auto` rejects it, because each phase resolves its own count.

### 2.3 `### Unattended lifecycle (auto)`

A new subsection after `### Live backend output`. It states, in this order and in no more than about
20 lines:

- **The six phases** and their order: `archive`, `init`, `plan`, `build`, `review`, `build`. Each loop
  phase runs as a child `ralph` process with `-y`, and with the `-m`, `-b`, `--skip-push`,
  `--no-metrics` and `-v` flags passed through. `-g` reaches `plan` alone.
- **Guards.** A build phase is skipped when the plan holds no open item. The review phase is skipped
  when no item is shipped, when open items remain, or when no `Spec:` field cites a `specs/` path. A
  build or review phase is also skipped when `IMPLEMENTATION_PLAN.md` or `PROGRESS.md` is absent. A
  skipped phase is not a failure.
- **The container rule.** `auto` exits 1 when `DEVCONTAINER` is not `true`. `--force` overrides this
  for a runner that is already isolated.
- **The report.** Every run that starts the phase loop ends with a `Lifecycle summary` with one
  row per phase: `ran`, `skipped — <reason>`, `failed — exit <n>`, `not reached`, `interrupted`,
  or `skipped — resumed at phase N`. The `-n`, container and goal refusals and `--dry-run` print
  none.
- **Exit status.** 0 when phase 6 has run or been skipped. 1 when any phase, phase 6 included,
  fails or a precondition rejects the run. 130 on interrupt.
- **`--resume`.** A failure or interrupt writes `.ralph/auto-state`. `ralph auto --resume -g <goal>`
  re-enters at the recorded phase, never earlier than phase 3, so `archive` and `init` never re-run.
  A failure that needs a manual repair must be repaired before resuming.
- **`--dry-run`** prints the six phases and each child command line. It evaluates no guard and runs
  no phase. It still requires `-g` and, outside a container, `--force`.

### 2.4 Examples

Add two lines to `### Examples`:

```bash
ralph auto -g specs/checkout-flow.md                # plan, build, review and fix, unattended
ralph auto --resume -g specs/checkout-flow.md       # continue after a failed phase
```

### 2.5 Intro and Background

The opening paragraph says ralph "Runs plan and build phases in a loop". `## Background` says the
pattern "works in two phases". Both name `review` as a third phase and `auto` as the command that
runs all three in sequence. `## Background` keeps its account of the Ralph Wiggum pattern.

## 3. Review in the README

`specs/review-phase.md` §12 and `specs/spec-anchored-review.md` §11 are satisfied and stay in force.
One sentence is added under `### Starting a new goal`, beside the sentence that orders review before
`archive` and `clean`:

> `review` runs only against a fully shipped plan: it exits 1 while any `- [ ]` item remains, when no
> item is `- [x]`, or when no `Spec:` field cites a `specs/` path.

No severity table and no description of finding levels are added. Those stay in `CLAUDE.md` and
`AGENTS.md`.

## 4. README corrections

### 4.1 Build iteration default

The `build` row in `## Commands` says `(default: 50 iterations)`. No such default exists: when `-n`
is absent, `calculate_build_iterations` sets the cap to `ceil(open items × 1.2)`. The row reads
`(default: open items plus 20% headroom)`.

### 4.2 `-y`, `--yes`

The options table has no `-y` row. Add:

```
| `-y`, `--yes`        | Skip the `Continue anyway? [y/N]` prompt when running outside a sandbox. `auto` accepts and ignores it; it passes `-y` to its children and refuses outside a container regardless |
```

### 4.3 Permissions and safety

- The permission-flag sentence names pi: pi has no permission flag, because its tools run without
  prompting.
- `**Outside a container**` states that `plan`, `build` and `review` print a warning and, on a
  terminal, ask `Continue anyway? [y/N]` unless `-y` or `--dry-run` is given; a non-interactive caller proceeds
  without the prompt. `auto` refuses outright unless `--force` is given.

### 4.4 Sandbox

- The pre-installed tool list in `## Sandbox` names the pi CLI.
- `### What gets mounted` matches `cmd_sandbox` and `container/devcontainer.json`:
  - `~/.gitconfig` mounts read-only at `/home/node/.gitconfig.host`, and the container's global git
    config includes it.
  - `~/.claude/settings.json` mounts read-only over the read-write `~/.claude` mount.
  - When `gpgconf` finds a host agent socket, ralph forwards it to `/home/node/.gnupg/S.gpg-agent`,
    preferring the agent's extra socket, and mounts `pubring.kbx` beside it, so the build loop can
    sign commits with no private key in the container. This mount is optional, like the SSH agent.
  - The `Mode` column reads read/write for `~/.ssh`, `~/.config/gh`, the `ralph` binary and the
    ralph config dir. `cmd_sandbox` mounts them with `--mount`, and the devcontainer CLI accepts no
    `readonly` key there.
  - The table gains a `pubring.kbx` row and a `/commandhistory` row for the shell history volume.
- The forwarded environment variables are the full set `cmd_sandbox` passes: `OPENAI_API_KEY`,
  `OPENROUTER_API_KEY`, `GEMINI_API_KEY`, `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`,
  `ANTHROPIC_API_KEY`, `GH_TOKEN` and `GITHUB_TOKEN`. `ANTHROPIC_API_KEY` is forwarded when it is set,
  even to an empty value; the rest only when non-empty.

## 5. `CLAUDE.md` and `AGENTS.md`

Both files take the same edits, so an agent reading either one gets the same description.

### 5.1 Command table

The table under `## Architecture` lists every arm of the main dispatch:

- Add `auto`: runs `archive`, `init`, `plan`, `build`, `review`, `build` as child processes of
  `RALPH_SELF`; requires `-g`; rejects `-n`; skips a phase whose guard fails, using the same
  predicates as `require_open_items` and `require_review_preconditions`; refuses to run outside a
  container without `--force`; records a failure in `.ralph/auto-state` for `--resume`.
- Add `metrics`: summarises a run's `metrics.jsonl`, the latest run by default.
- Add `version`: prints the version.
- The `build` row replaces `default: 50 iterations` with the calculated default from §4.1.
- The `review` row replaces `audits - [x] items against the plan items that produced them` with the
  spec-anchored wording: it audits the cycle's cited specs against the tree and the cycle's commits,
  and files findings as new `- [ ]` items. That phrase is the build-fidelity rule
  `specs/spec-anchored-review.md` retired.

### 5.2 `auto` architecture paragraph

A short paragraph after the build and review precondition paragraph states the property the guards
depend on: `auto`'s phase guards call `have_open_items`, `have_shipped_items` and
`have_cited_specs`, the same predicates the hard stops use, so a guard and its hard stop cannot
drift, and `auto` never starts a child that exits 1 on a gate. A change to either hard stop changes
the guard with it. The artifact-presence check is duplicated inline in `cmd_auto` and must be kept
in step with `require_init_artifacts` by hand.

### 5.3 Sandbox section

- `Mounts:` lists `~/.codex`, `~/.copilot`, `~/.pi`, `~/.config/gh`, the ralph config dir, the
  read-only `~/.claude/settings.json` overlay, the optional GPG agent socket with `pubring.kbx`
  beside it, and the shell history volume, beside the entries it has.
- The line states that ralph forwards API keys and a GitHub token, deriving `GH_TOKEN` from
  `gh auth token` when neither token is set.
- Both `Base image:` lines name the Codex CLI, the Copilot CLI, pi and the Docker CLI, which
  `container/Dockerfile` installs. `AGENTS.md`'s also names Bun and uv, as `CLAUDE.md`'s already
  does.

## 6. Stale ShellCheck comments

`ralph` carries `# shellcheck disable=SC2034  # Consumed by cmd_auto in a later change.` above
`AUTO_STATE_FILE`, `RALPH_PHASES` and `RESUME_FLOOR`. `cmd_auto` now reads all three, so the three
directives are removed. `shellcheck ralph` stays clean without them. If ShellCheck still reports
SC2034 for one of them, that directive stays, with its reason rewritten to state the real cause.

## 7. Out of scope

- Any change to `usage()`. It is correct and is the reference for this spec.
- Any change to behaviour, flags, exit codes or the prompts.
- Restating `specs/auto-lifecycle.md` in the README or the guardrails beyond §2 and §5.
- A severity table or a description of finding levels in the README.
- A generated or tested cross-check between `usage()` and the README.
- The `Re-run: … auto --resume` hint `cmd_auto` prints on failure omits `-g`, which the goal check
  requires. It is wrong and is left to a follow-up.

## 8. Testing

No test changes. The work is documentation plus the removal of three ShellCheck directives.

- `bats test/` passes unchanged. `test/auto.bats` pins the `auto` entries in `--help`, and that
  output does not change.
- `shellcheck ralph install.sh` and `shellcheck test/*.bats test/test_helper.bash` are clean.
- `grep -n 'default: 50' README.md CLAUDE.md AGENTS.md` returns nothing.
- `grep -n 'against the plan items that produced them' CLAUDE.md AGENTS.md` returns nothing.
- `grep -c '^| `auto`' README.md CLAUDE.md AGENTS.md` reports 1 for each file.
