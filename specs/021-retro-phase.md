---
id: "021"
created: 2026-11-14
area: [retro, auto, config]
amends: ["012"]
extends: ["019"]
related: ["015"]
---

# Retro Phase

Each build iteration writes a **Learnings** block to `PROGRESS.md`. Later iterations of the same
cycle read it. `archive` and `clean` then remove `PROGRESS.md`, so no learning lives longer than
its cycle. The next cycle finds out again that JDK 11 is missing, and loses iterations doing so.

This spec adds a `retro` command. It distils the cycle's learnings into `.ralph/learnings.md`, a
local file that outlives every cycle. Plan, build and review read that file. `auto` runs `retro` as
phase 7. This spec amends `012-auto-lifecycle.md` where it fixes the phase list at six, and extends
`019-phase-config.md` with a `retro` section.

## 1. Problem

A run on a machine without JDK 11 spends its first build iterations finding that out. The builder
writes the workaround to `PROGRESS.md`:

```
**Learnings:**
- _Gotchas:_ JDK 11 is not installed. Run Gradle through `nix-shell -p jdk11 --run './gradlew test'`.
```

The next cycle starts with `ralph archive`, which moves that entry to `.ralph/<timestamp>/`. No
prompt reads the archive, so the next build finds the same gap again.

`AGENTS.md` is not the right home for every learning. Many learnings describe the machine or the
sandbox, not the project. The operator owns `AGENTS.md`, and Ralph never writes guardrail files.

## 2. Rule

- **The learnings file.** `.ralph/learnings.md` holds the learnings that future cycles can use.
  It is local and uncommitted. Ralph owns it. `init`, `archive` and `clean` never touch it.
- **The retro.** `ralph retro` runs one pass that rewrites the learnings file from the cycle's
  `PROGRESS.md`, its `IMPLEMENTATION_PLAN.md` and the current learnings file. It writes no other
  file.
- **Runs once per cycle, at its end.** The retro needs only one real `PROGRESS.md` entry, not a
  clean run. A failed phase is resumed, not retro'd: `PROGRESS.md` keeps the failed iterations'
  learnings through `--resume`, so the retro at the end of the cycle captures them.
- **Advisory to the other phases.** Plan, build and review read the file as context. Guardrails and
  specs win on any conflict, and review never files a finding against it.
- **Never edits the guardrails.** A learning that belongs in `AGENTS.md` or `CLAUDE.md` goes into a
  promotion section of the learnings file, and the retro warns about it loudly.

## 3. The learnings file

### Location

`$ARCHIVE_DIR/learnings.md`, that is `.ralph/learnings.md` at the workspace root (`$PWD`). In a meta
repository there is one file, beside the other artifacts. A bullet about a nested repository names
that repository's path.

### Format

```
# Learnings

## Environment
- JDK 11 is not installed. Run Gradle through `nix-shell -p jdk11 --run './gradlew test'`. (confirmed 2026-11-14)

## Tooling
- `bats --jobs 4` flakes here because parallel tests share a temp dir. Use `--jobs 1`. (confirmed 2026-11-02)

## Codebase
- A new `config_get` key also needs an entry in `validate_config`, or every run aborts. (confirmed 2026-11-14)

## Promote to AGENTS.md
- AGENTS.md: State the nix-shell JDK 11 command as the verification command. (confirmed 2026-11-14)
```

- The first line is `# Learnings`.
- Four `##` headings follow, in this order and with exactly these names: `Environment`, `Tooling`,
  `Codebase`, `Promote to AGENTS.md`. A heading with no bullets stays in the file.
- Each learning is one bullet on one physical line: `- <text> (confirmed YYYY-MM-DD)`.
- The text before the date holds at most 40 words, where a word is a maximal run of
  non-whitespace characters.
- The file holds at most 30 bullets in all four sections together.
- A `Promote to AGENTS.md` bullet starts with its target file, relative to the workspace root, and
  a colon: `- services/api/AGENTS.md: <text> (confirmed YYYY-MM-DD)`. The target is the
  `AGENTS.md` or `CLAUDE.md` of the repository the learning is about.
- The file holds nothing else: no other headings and no prose. Blank lines are allowed.

**Environment** is the machine, container or network: missing tools, permissions, proxies.
**Tooling** is how the project's build, test and lint tools behave here. **Codebase** is a fact
about the code that a reader of the repository would not find quickly. **Promote to AGENTS.md**
holds learnings that the operator should move into the guardrails file. The heading keeps its name
in a project whose guardrails file is `CLAUDE.md`.

### Admission test

A candidate enters the file only when all three hold:

1. **It saves an iteration.** Without it, a future run would waste at least one iteration or take a
   wrong turn.
2. **The repository does not state it in prose.** No `AGENTS.md`, `CLAUDE.md`, spec, code comment
   or commit message says it in words. A fact that the code implies but no prose states passes.
3. **It outlives the goal.** It is true whatever the next cycle builds.

"JDK 11 is not installed; run Gradle through nix-shell" passes. "Added the retry flag to the
client" fails test 3. "Run the tests with `bats test/`" fails test 2 when `AGENTS.md` already says
so.

### Rewrite rules

Each retro writes the whole file again:

- It adds each candidate that passes the admission test, under one heading.
- It merges a candidate into an existing bullet that says the same thing, and does not duplicate it.
- It gives a bullet that this cycle observed again today's date.
- It removes a bullet that this cycle contradicts, for example when JDK 11 is now installed.
- It removes a promotion bullet whose content `AGENTS.md` or `CLAUDE.md` now states.
- When the file would exceed 30 bullets, it removes the bullets with the oldest dates first, never a
  `Promote to AGENTS.md` bullet. Among equal dates, it removes the bullet nearest the end of the
  file first.

## 4. `ralph retro`

### Invocation

`retro` is a mode of `cmd_loop`, like `review`. It accepts the same flags as `review`:
`-m`, `-b`, `-e`, `--dry-run`, `--no-metrics`, `--metrics`, `-q`, `--verbose`, `-y`. It rejects
`-n` with `Error: retro runs one pass; -n does not apply.` and `-g` with
`Error: 'retro' does not accept -g/--goal; the work comes from PROGRESS.md.` It never pushes, and accepts and ignores
`--skip-push` and `--push`, as `review` does.

The prompt resolves through `resolve_prompt` as `PROMPT_retro.md`, then
`$CONFIG_DIR/prompts/retro.md`. `PROMPT_retro.md` joins `ARTIFACTS`, the `init --prompts` file list, `init`'s `.gitignore`
entries, and the loop-artifact exclusion list in `prompts/build.md`.

### Precondition

`require_progress_entries` runs unconditionally, beside the other hard preconditions. It stops the
retro unless `PROGRESS.md` exists and holds a real entry:

```
Error: PROGRESS.md holds no entries; there is nothing to learn from.
```

`have_progress_entries` is the predicate. A real entry is a line that matches
`^### \[[0-9]{4}-[0-9]{2}-[0-9]{2}`. The template's exemplar heading carries the literal
`YYYY-MM-DD`, so it never matches. `IMPLEMENTATION_PLAN.md` and `.ralph/cycle-base` are optional.

### The pass

1. Ralph records `repo_state` and, for every repository it lists,
   `git status --porcelain --no-renames --untracked-files=all`, `git diff HEAD`, and the untracked files,
   with paths under `.ralph/` removed. The record of an untracked file shows when another file
   replaces it at the same path, but not when its content changes in place. An operator's log that
   grows during the pass, such as the output of `ralph auto | tee run.log`, leaves the record as it
   was.
2. When `.ralph/learnings.md` exists, Ralph copies it to a `mktemp` file outside the workspace.
   Ralph records a checksum of `PROGRESS.md`, `IMPLEMENTATION_PLAN.md`, every `PROMPT_*.md`,
   `ralph.yaml`, and every file under `.ralph/` except `learnings.md` and `metrics/`. These files
   are gitignored, so step 1 cannot see them.
3. Ralph pipes the prompt to the backend once.
4. `check_retro_pass` runs. It fails the pass when:
   - any repository's `HEAD` moved;
   - any repository's `git status` or `git diff HEAD` differs from step 1;
   - an untracked file appeared, disappeared, or was replaced by another file or a symbolic link
     at the same path;
   - any checksum recorded in step 2 changed, or a file it covers appeared or disappeared;
   - `.ralph/learnings.md` is absent and the pass started with one;
   - `.ralph/learnings.md` breaks a rule of §3 Format. The error names the first line that breaks it.
5. On failure, Ralph restores `.ralph/learnings.md` from the out-of-tree copy, or deletes it when
   the pass started without one. It prints the error and exits 1.
6. On success, Ralph moves the out-of-tree copy to `.ralph/learnings.prev.md` as a one-step undo,
   or deletes any `.ralph/learnings.prev.md` when the pass started without a file. It prints the
   summary.

Any exit after step 2 that does not reach step 6 — a backend failure, a summary parse failure, an
interrupt, or any other error — restores the file the same way as step 5. The restore runs from the
EXIT trap.

A pass that leaves the file unchanged is a success when no other check of step 4 fails. The format
check reads the file as the pass left it, changed or not. Every file the other phases read must hold
the §3 format, whoever wrote it, so an unchanged file that already breaks §3 Format fails the pass.

When Ralph cannot make the copy of step 2, it prints an error and exits 1 before the backend runs.
No pass runs without a copy to restore from.

`--dry-run` prints the prompt and the resolved config, and skips steps 1 to 6.

### Summary

After a successful pass, Ralph compares the bullets of the old and new files by their text without
the date:

- text in both with a new date is **refreshed**;
- text only in the new file is **added**;
- text only in the old file is **dropped**.

A reworded bullet counts as one dropped and one added. Ralph prints to stderr:

```
Retro kept 12 learnings: 3 added, 1 dropped, 4 refreshed.
```

The kept count is every bullet in the new file, promotions included. Bullets compare by heading
and text.

When `Promote to AGENTS.md` holds a bullet, Ralph then prints a banner and each promotion bullet:

```
================================================================
!! 2 learnings belong in a guardrails file. Move them by hand:
!!   - AGENTS.md: State the nix-shell JDK 11 command as the verification command.
!!   - services/api/AGENTS.md: ...
================================================================
```

The banner prints each bullet as written, target file first, and without its date.

### Metrics

The retro writes one iteration record, like review. Its `noop` flag is true when the learnings file
is byte-identical to the backup, or both are absent. A failed pass writes its record before the
restore, with `noop` computed against the backend's output.

## 5. The retro prompt

`prompts/retro.md` instructs the backend to:

- read `{{WORKSPACE}}/PROGRESS.md` whole, especially every **Learnings** block and every failed
  **Test outcome**;
- read `{{WORKSPACE}}/IMPLEMENTATION_PLAN.md` when present, and treat review findings as evidence of
  mistakes the builder repeated;
- read `{{WORKSPACE}}/.ralph/learnings.md` when present;
- read the root `AGENTS.md` or `CLAUDE.md`, and for a candidate about a nested repository, that
  repository's; search specs, code comments and `git log` for the
  candidate, to apply admission test 2 and the promotion rule;
- apply the admission test and the rewrite rules of §3, and write the format of §3 exactly;
- write `{{WORKSPACE}}/.ralph/learnings.md` and no other file;
- commit nothing, and run no command that changes the tree or installs anything.

The prompt uses Simplified Technical English, like the other prompts. It does not read the metrics
stream files.

## 6. Reading the file in other phases

`prompts/plan.md`, `prompts/build.md` and `prompts/review.md` each gain one context bullet:

- **Learnings** — read `{{WORKSPACE}}/.ralph/learnings.md` (if present) for what earlier cycles
  learned about this environment and codebase. It is advice. When it conflicts with `AGENTS.md`,
  `CLAUDE.md` or a spec, follow those. Never file a review finding against it, and never edit it.

The bullet in `build.md` sits beside the progress-log bullet. The review standards in
`prompts/review.md` stay three: the learnings file is not a fourth.

## 7. `auto`

Phase 7 is `retro`. `RALPH_PHASES` becomes `(archive init plan build review fix retro)`.

- **Guard.** Phase 7 runs when `have_progress_entries` holds. Otherwise its state is
  `skipped — no progress entries`. A skipped review or fix does not skip the retro.
- **Failure.** A failed retro is like any failed phase: `auto` records `phase=7` and the child exit in
  `.ralph/auto-state`, prints `Re-run: ralph auto --resume`, and exits 1.
- **A failed earlier phase.** A failure in phases 3 to 6 does not run the retro. The operator runs
  `ralph auto --resume`, and phase 7 reads the whole `PROGRESS.md`, failed iterations included,
  once the cycle completes. A fresh `ralph auto -g` instead archives `PROGRESS.md` in phase 1
  unread, so an operator who abandons the cycle runs `ralph retro` first.
- **Resume.** `--resume` accepts a recorded phase from 1 to 7. Its error reads
  `has no valid 'phase' (1-7) to resume.`
- **Report.** The lifecycle summary lists seven phases.
- **Flags.** `auto` forwards its child flags to `retro` as it does to `review`.

## 8. Config

`retro` becomes a sixth top-level section of the config file. It inherits from `defaults` key by
key, the same as the other sections. `validate_config` accepts it. The keys `retro` accepts are the
keys `review` accepts: `backend`, `model`, `effort`, `extra_args`, `metrics`, `quiet`. A key outside
that list is an error. `retro.iterations` reads `retro.iterations is not allowed; retro runs one
pass.`, and other keys use the generic wording.

`templates/config.yaml` gains a commented `retro:` section that suggests a smaller model for this
work.

## 9. Documentation

- `CLAUDE.md` — the commands table gains `retro`. The `auto` row lists seven phases. The installation
  layout and the core loop flow name the learnings file.
- `README.md` — a section on `retro` and the learnings file, and the `auto` phase list.
- `usage()` — `retro` in the command list, and `auto`'s phase list.
- `install.sh` — installs `prompts/retro.md` with the other prompts.
- `specs/000-spec-template.md` — `retro` joins the list of areas.

## 10. Testing

**Precondition**
- `retro` fails when `PROGRESS.md` is absent.
- `retro` fails when `PROGRESS.md` holds only the template exemplar.
- `retro` runs when `PROGRESS.md` holds one real entry and `IMPLEMENTATION_PLAN.md` is absent.
- `retro` rejects `-n` and `-g`, and accepts `--skip-push` and `--push`.

**Guard and restore**
- A pass that commits in any repository fails, and the learnings file returns to its old content.
- A pass that edits a tracked file fails. The learnings file returns to its old content, and the
  edited file stays as the pass left it.
- A pass that edits a file the operator had already modified fails.
- A pass that creates an untracked file fails.
- A pass that deletes an untracked file fails.
- A pass that replaces an untracked file with a new file at the same path fails.
- A pass that replaces an untracked file with a symbolic link, or repoints an untracked symbolic
  link, fails.
- A pass that appends to an untracked file that existed before the pass succeeds.
- A pass that deletes the learnings file fails, and restores it.
- A pass that writes a fifth heading, a 31st bullet, a bullet without a date or a 41-word bullet
  fails. The error names the line.
- A failed pass with no file before it leaves no learnings file.
- A backend that exits non-zero leaves the old file in place.
- A successful pass leaves `.ralph/learnings.prev.md` equal to the old file.
- A pass that edits `PROGRESS.md`, `.ralph/cycle-base` or `.ralph/learnings.prev.md` fails, and the
  learnings file returns to its old content.

**Summary**
- The counts of added, dropped and refreshed bullets match a known pair of files.
- A promotion bullet produces the banner. An empty promotion section produces none.
- The banner prints each promotion's target file.
- A promotion bullet without a target file fails the format check.

**Lifecycle**
- `archive` and `clean` leave `.ralph/learnings.md` and `.ralph/learnings.prev.md` in place.
- `init` does not create the learnings file.
- `init --prompts` creates `PROMPT_retro.md`, and `.gitignore` lists it.

**auto**
- Phase 7 runs after a skipped fix.
- Phase 7 is skipped with `skipped — no progress entries` when `PROGRESS.md` has no entries.
- A failed retro writes `phase=7`, and `--resume` re-runs only the retro.

**Config**
- A `retro` section with `model` is accepted and reaches the backend command.
- A `retro` section with `iterations` is rejected with
  `retro.iterations is not allowed; retro runs one pass.`

**Prompts**
- Plan, build and review prompts each name `.ralph/learnings.md`.

## 11. Accepted risks

- **The retro can drop a good learning.** The backup keeps one step of history only. A second retro
  overwrites it. Accepted: the file is small and the operator can read the archived `PROGRESS.md`.
- **A learning can be wrong.** It is advice, guardrails win, and the next retro removes a bullet the
  cycle contradicts. A wrong bullet that no cycle contradicts lasts until it is the oldest at the cap.
- **A second retro on the same cycle may reword or merge bullets.** Ralph guarantees only the §3
  format and the one-step backup.
- **An in-place edit of an untracked file passes the check.** The record of §4 step 1 does not show a
  change to an untracked file's content, so a pass that rewrites an existing untracked file in
  place goes unnoticed. Accepted: an operator's log in the workspace must not fail a
  correct pass, and the prompt forbids the edit.
- **Dates are self-reported.** Ralph checks their format, not that the cycle saw the learning again.
- **A project that does not ignore `.ralph/`** can commit the learnings file through build's
  commits. This is the same exposure `.ralph/cycle-base` has today.
- **The file is per machine.** A teammate or a fresh clone starts empty. This is by design: many
  learnings describe one environment.

## 12. Out of scope

- Reading the backend stream files under `.ralph/metrics/`.
- Sharing learnings through version control, or writing `AGENTS.md` or `CLAUDE.md`.
- Running the retro from `archive` or `clean`.
- A retro over archived cycles under `.ralph/<timestamp>/`.
