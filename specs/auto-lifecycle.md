# Unattended Lifecycle (`auto`)

Ralph has four commands that a human strings together by hand. A full cycle is `ralph archive` to
close out the last one, then `ralph init`, `ralph plan`, `ralph build`, `ralph review`, and
`ralph build` again to ship what review filed. Each is a separate invocation, and the operator
watches each finish to decide whether the next may start.

That decision is the chore. Once the prompts and rules are tuned it carries no judgement: it reads
`IMPLEMENTATION_PLAN.md`, counts two kinds of checkbox, and starts the next command or does not.
This spec adds a fifth command, `auto`, that makes the decision itself and runs the sequence end to
end.

`auto` is a **manual, watched command**. It is not a scheduler and nothing in this spec is designed
for cron. Its product is the report it prints when it stops; its exit status is a coarse signal and
nothing more.

## 1. Model

**`auto` is a guarded sequence, not a pipeline.**

The phases cannot be chained with `&&`. Each mode carries hard preconditions that run unconditionally
beside `require_init_artifacts` and exit non-zero when they fail, and the ordinary outcomes of one
phase routinely violate the next phase's preconditions. Three cases, all reachable on a healthy
project:

- **The second `build` refuses after a clean review.** A review that finds nothing files nothing, so
  the plan is left with no `- [ ]` item and `require_open_items` exits 1 (`ralph:631-636`). The best
  available outcome — everything shipped, the audit clean — would be reported as a failed run.
- **`review` refuses whenever `build` stopped short.** `require_review_preconditions` demands zero
  open items (`ralph:650-654`). `build` exits early after 2 consecutive noops (`ralph:1567-1572`),
  and `calculate_build_iterations` grants only `ceil(n × 1.2)` iterations (`ralph:665`). Both leave
  open items behind as a matter of course.
- **`plan` can produce nothing to build.** A plan pass that converges without writing an item leaves
  the plan empty, and `build` exits 1 against it.

So `auto` reads the plan between phases and decides what is legal next, using the same counts the
preconditions gate on. A phase whose preconditions do not hold is **skipped**, not failed: the
condition that stops `ralph review` running on its own is, inside a lifecycle, an ordinary fact about
where the work has got to.

**A skipped phase is not an error and never aborts the lifecycle.** This is the whole point of the
command. A `review` skipped for having nothing to audit is a lifecycle that had nothing to audit.

### The guards and the hard stops must not drift

`auto` and the `require_*` functions ask the plan the same questions for opposite purposes. The hard
stops turn a false answer into `exit 1`; `auto` turns it into a skipped phase. Two readings of "can
this mode run?" maintained separately will diverge, and the failure is silent in the worst direction:
`auto` starts a phase its own guard believed legal, the child exits 1, and `auto` reports a lifecycle
failure for a condition it was built to absorb.

Both readings therefore share one predicate. `have_open_items` and `have_shipped_items` wrap the
existing `count_plan_items` calls, `require_open_items` and `require_review_preconditions` are
rewritten in terms of them, and `auto`'s guards call the same two functions. This is a refactor with
no behaviour change of its own.

The shared predicates cover the item counts. They do **not** cover artifact presence, which
`require_init_artifacts` checks separately for every mode (`ralph:586-606`), so §3's guard table must
restate that condition itself — including `PROGRESS.md`, which both `build` and `review` require.

### What `auto` does and does not add

`auto` launches no backend, resolves no prompt template, and reads no prompt file. It runs existing
commands and counts checkboxes. Every rule about what an agent may write stays in `prompts/`.

It does change one **input** the agents are written against, and §2 states the consequence: archiving
at the front means each lifecycle's `plan` phase reads a fresh `PROGRESS.md`.

## 2. The sequence

Six phases, in order, numbered 1 to 6 everywhere this spec and the command refer to them:

```
1 archive → 2 init → 3 plan → 4 build → 5 review → 6 build
```

`archive` runs **first**, not last. The artifacts a run produces are the record of what it did, and
they are the first thing an operator reads when it stops. Archiving at the end moves
`IMPLEMENTATION_PLAN.md` and `PROGRESS.md` into `.ralph/<timestamp>/` and leaves the tree with no
plan, so the evidence has to be dug out of a timestamped directory — and on an aborted run it buries
exactly the evidence the abort made worth reading. Archiving at the front means a lifecycle always
ends with its own plan and progress in place, and each new run clears the previous one's residue.

A plain `ralph auto` is therefore a **fresh lifecycle**. It does not extend the previous run's plan:
that plan moves to `.ralph/<timestamp>/` and `plan` re-derives a new one from `specs/`. This is why
`--resume` (§5) is a separate entry mode rather than the default.

`build` appears twice, so a phase is addressed by its **number**, never by name — a resume that named
`build` could not tell the two apart.

### The archived progress log is accepted loss

`cmd_archive` moves `PROGRESS.md` (`ralph:270-297`) and `cmd_init` scaffolds a fresh template in its
place (`ralph:312-316`), so every lifecycle's `plan` phase reads an empty progress log.

That log is the declared cross-run channel. `templates/PROGRESS.md:3` calls it an append-only log
that must never be edited or removed; `prompts/plan.md:20` tells the planner to read it "for
outcomes, blockers, and the reasons items were marked `[~]`"; `prompts/build.md:20` reads it for
"learnings and gotchas from earlier iterations"; and `prompts/build.md:42` tells `build` to record a
contradiction "with enough detail for the next planning run to resolve it".

Under `auto` that last promise is false, and the cost is real but small: a lifecycle that hits a
genuine blocker records why, and a lifecycle run some weeks later re-plans the same work and hits the
same wall, costing one iteration per recurrence. This is accepted rather than fixed, because `auto`
is a manual command whose operator can read `.ralph/<timestamp>/PROGRESS.md` and because the
alternatives all cost more than the defect: leaving `PROGRESS.md` unarchived needs a scope flag on
`cmd_archive`, and seeding the fresh log from the old one grows it without bound.

Note that the plan is archived too, so no `[~]` item survives either. `prompts/plan.md:99`'s
instruction to resolve a `[~]` item from its `PROGRESS.md` entry therefore never fires across two
`auto` runs — the fresh plan has no `[~]` items to resolve. The loss is the blocker knowledge alone.
§13 records the follow-up.

### What the second build is for

The second `build` exists to ship what `review` filed. It has a second use that follows from the
guards: when `build` at phase 4 stopped short and `review` was skipped because open items remained,
the guard at phase 6 finds those items still open and runs. The stalled work gets a second pass.

### One review round is a deliberate limit

A single `review` means the findings it files are built by phase 6 and then **ship unaudited**. The
lifecycle does not close over its own output.

The alternative was a fixpoint — build until the queue is empty, review, repeat until a review pass
files nothing — which is what ralph's convergence machinery already computes. It is rejected here for
cost predictability: a fixed sequence costs at most four agent runs and the operator knows that
before starting. §13 keeps the fixpoint as a follow-up.

## 3. Phase guards

Before each phase, `auto` evaluates that phase's guard against the plan **as it stands on disk at
that moment** — never against a decision made earlier in the run.

| # | Phase | Runs when | Skip reason when it does not |
|---|-------|-----------|------------------------------|
| 1 | `archive` | always (not under `--resume`) | — |
| 2 | `init` | always (not under `--resume`) | — |
| 3 | `plan` | always | — |
| 4 | `build` | both artifacts present **and** the plan holds at least one `- [ ]` item | `IMPLEMENTATION_PLAN.md is missing`, `PROGRESS.md is missing`, or `no open items in IMPLEMENTATION_PLAN.md` |
| 5 | `review` | both artifacts present **and** at least one `- [x]` item **and** no `- [ ]` item | as above, or `no shipped items to audit`, or `N open items remain` |
| 6 | `build` | as phase 4 | as phase 4 |

The guards restate `require_init_artifacts` exactly: both `build` and `review` require
`IMPLEMENTATION_PLAN.md` **and** `PROGRESS.md` (`ralph:592-593`, pinned by `test/review.bats:39-47`).
Naming only the plan would be drift of the kind §1 exists to prevent, and `PROGRESS.md` is the more
likely of the two to be lost mid-run, since it is the file `build` writes to.

The `review` guard reports its item-count failures as two distinct reasons because they mean opposite
things: no shipped items means the lifecycle produced nothing, and open items remaining means it
produced something and did not finish.

`archive` and `init` are unguarded. Both are idempotent and self-describing: `cmd_archive` reports
`Nothing to archive.` on an empty tree (`ralph:280-283`) and `scaffold` skips any artifact that
already exists (`ralph:369-378`).

`plan` is unguarded because it is the phase that creates the state every later guard reads. Its own
precondition is checked by the assertion below instead.

### Phase 2 asserts what it was supposed to scaffold

`cmd_init` does **not** guarantee the artifacts exist. When a template is missing from
`$CONFIG_DIR/templates` it prints a warning and exits 0, leaving the file absent
(`ralph:312-322`) — so `plan`, whose precondition is that file, would hard-stop and abort the whole
lifecycle with a message telling the operator to run the `init` that just ran.

`RALPH_CONFIG_DIR` is a documented override and `templates/IMPLEMENTATION_PLAN.md` is a later
addition than `templates/PROGRESS.md`, so an installation whose binary was updated and whose config
directory was not has exactly this state.

After phase 2, `auto` therefore checks that `IMPLEMENTATION_PLAN.md` and `PROGRESS.md` both exist and
**fails the lifecycle at phase 2** if either does not, naming the missing file and
`$CONFIG_DIR/templates`. A broken installation is a failure of `init`, not a skip of `plan`.

## 4. Phases run as child processes

`auto` invokes each phase as a child process, `"$RALPH_SELF" <phase> <flags>`, rather than calling
`cmd_loop` in-process.

Every failure path in `cmd_loop` ends in `exit`: a non-zero backend (`ralph:1418`), a jq failure
(`ralph:1460`), a rejected push (`ralph:1544`). Called in-process the first of those would take the
lifecycle down with it, with no chance to record where it stopped or print what had run. A child
turns the same failure into an exit status the parent decides on.

It also keeps each phase's state to itself. `cmd_loop` sets a global `ARGS` from `getopt`
(`ralph:921`), installs an `EXIT` trap for its raw-stream temp file (`ralph:1127-1130`), and installs
`SIGINT`/`SIGTERM` traps that exit 130 (`ralph:1133`). Six phases through that in one process would
have each phase's traps and globals overwrite the last one's.

`RALPH_SELF` is the absolute path of the running script, resolved once at startup before any command
can change directory. This holds when ralph is invoked by absolute path, by relative path, through a
symlink, or found on `PATH` — in the last case the kernel receives the resolved path as the script
argument, so a bare name never reaches `$0`.

`archive` and `init` are invoked the same way, for uniform status capture.

## 5. Failure, interruption and `--resume`

### On failure

A phase that exits non-zero **aborts the lifecycle immediately**. `auto` does not retry, does not
skip ahead, and does not run the phases after it.

Retrying was considered and rejected. It absorbs a transient API error, but it costs a full extra
agent run whenever the cause is real — an expired credential, a bad model name, a missing backend
CLI — and those fail identically every time.

`auto` then writes the state file, prints the report, and exits 1. The child's own exit status is
reported in both places (§6) but is not `auto`'s exit status; §6 explains why.

### The state file

`.ralph/auto-state` is plain `key=value` lines, parsed by field and never sourced:

```
phase=4
phase_name=build
child_exit=42
failed_at=2026-09-14T02:17:09Z
```

`phase` is the 1-based number from §2, the same number the report prints. The two surfaces used
different bases in an earlier draft, which gave an operator reading `phase=3` against a report whose
row 3 said `plan` no way to tell which one `--resume` would act on.

**`auto` creates `.ralph/` before writing.** The directory is created today only by `cmd_loop`'s
metrics path (`ralph:1009-1019`), and neither `cmd_archive` on an empty tree nor `cmd_init` creates
it — verified: it is absent after `archive`, after `init`, and after a dry-run `plan`. So on an
abort that happens before or without metrics — `ralph auto --no-metrics` where `plan` dies on a
missing backend CLI — the redirect would fail under `set -euo pipefail`, abort `auto` with the shell's
own status, and print no report at all. A `mkdir -p "$ARCHIVE_DIR"` precedes the first write.

The file records no flags. A resume uses the flags on its own command line, so an operator who
diagnoses the failure as a bad model can resume with a different `-m`. Replaying the original flags
would make that impossible and would silently reapply a `-b` that was the cause.

`auto` removes the state file at the start of every non-resume run, and on any run that reaches phase
6 — including one that skipped phases, which is a completed lifecycle. The file survives only an
abort or an interrupt.

### `--resume`

`ralph auto --resume` re-enters at the phase recorded in the state file and runs to the end. It does
this **unconditionally** — it does not inspect why the phase failed, and it never refuses.

It never runs `archive` or `init`. `archive` would move the artifacts of the very run being resumed
into `.ralph/<timestamp>/`, which is precisely what a resume exists to preserve, and `init` would
scaffold over them. The entry point is floored at phase 3, `plan`, whatever the state file says.

`--resume` fails before any phase runs when there is no state file (`no interrupted lifecycle to
resume`), when `phase` is missing or is not a number in 1-6, or when `IMPLEMENTATION_PLAN.md` or
`PROGRESS.md` is absent — a resume into a workspace with no artifacts has nothing to continue, and
the §3 guards must not quietly turn it into a lifecycle that does nothing and reports success.

**Known hazard: a resume can walk past a repair instruction.** `cmd_loop` stops a review that
un-ticked a shipped item and tells the operator to fix the file by hand (`ralph:1519-1526`, "Restore
IMPLEMENTATION_PLAN.md before re-running"). A resume after that failure finds the un-ticked item as
an *open* item, so the phase-5 guard skips review with "N open items remain" and phase 6 builds it —
re-implementing and re-committing work that already shipped. `auto` does not detect this: resume is
unconditional by design, because an operator who has to classify failures to know whether resume is
safe has lost the benefit of the command.

The mitigation is a notice, not a refusal. Every `--resume` prints the recorded phase and the child's
exit status, and states that a failure which asked for a manual repair must be repaired before
resuming. §13 records the stronger fix.

### On interruption

`auto` traps `SIGINT` and `SIGTERM`, writes the state file for the phase in flight, prints the
report, and exits 130.

Ctrl-C — the realistic interrupt for a manual foreground command — works correctly this way. It
reaches the whole foreground process group, so the child receives it too and exits 130 under its own
trap (`ralph:1133`), and `auto`'s trap then runs and records the phase that was actually running.

**A signal delivered to `auto` alone does not.** Bash does not run a trap while waiting on a
foreground child; it defers it until the child completes. So `kill <pid>` on a running lifecycle does
not stop the phase — the phase finishes, possibly hours later, and `auto` then records a state file
for a phase that *succeeded* and exits 130, after which a resume re-runs completed work. This is
accepted: `auto` is a manual foreground command and Ctrl-C is its interrupt. §13 records the fix
(run each phase with `&` and `wait`, and forward the signal to the child).

## 6. Reporting

**The report is the product of the command.** `auto` exists to remove the babysitting, so what it
prints when it stops is what the operator reads instead of having watched. The exit status is a
coarse signal and carries no detail.

Every run ends with a report naming, for each of the six phases, whether it ran, was skipped and why,
failed and with what child exit status, was not reached, or was passed over by a `--resume`:

```
Lifecycle summary
  1 archive   ran
  2 init      ran
  3 plan      ran
  4 build     ran
  5 review    skipped — 3 open items remain
  6 build     ran
```

Six row states: `ran`, `skipped — <reason>`, `failed — exit <n>`, `not reached` (after an abort),
`skipped — resumed at phase N` (before a resume entry point), and `interrupted`. The resume state is
distinct from the others because reusing `not reached` — which marks phases *after* a failure — would
make the report ambiguous about where the run stopped.

The report also names where the artifacts are (`IMPLEMENTATION_PLAN.md` and `PROGRESS.md` in the
tree, the previous cycle under `.ralph/<timestamp>/`) and, on an abort, the single command to re-run
by hand.

### Exit status

| Code | Meaning |
|------|---------|
| 0 | The lifecycle reached phase 6, whatever it skipped. |
| 1 | A phase failed, or a precondition rejected the run before any phase started. |
| 130 | Interrupted. |

A completed lifecycle exits **0 even when phases were skipped**, because skipping is how the sequence
absorbs the preconditions §1 describes. An earlier draft gave skips their own code and so made
`ralph auto` exit non-zero on its best outcome — everything shipped, the audit clean, phase 6 skipped
for having nothing to do — which is the exact defect §1 opens by describing.

`auto` does not propagate the child's exit status. Its own codes are a closed set no child can mint:
`cmd_loop` exits with the backend's own status (`ralph:1418`), which is unbounded, and with jq's
(`ralph:1460`), which is 5 on a parse failure and 3 on a compile failure — so a propagated code is
ambiguous with anything `auto` might reserve. The child's status is diagnostic, and the report and the
state file are where it belongs.

## 7. `auto` refuses to run outside a container

`auto` exits 1 when `DEVCONTAINER` is not `true`, unless `--force` is given.

`plan`, `build` and `review` warn about running outside a container and then prompt `Continue anyway?
[y/N]` when attached to a terminal (`ralph:1040-1066`). `auto` must pass `-y` to its children so it
never blocks mid-lifecycle, and that prompt is the one safety check `-y` removes. A long unsupervised
agent loop running with the backend's permission flag on the host — where the tree, `~/.ssh` and the
rest of `$HOME` are reachable — is the case that prompt exists for.

`--force` keeps the escape hatch for a runner that is already isolated but sets no `DEVCONTAINER`.

**`auto` prints its own one-line notice under `--force`, not the loop modes' banner.** That banner is
backend-dependent text built inline in `cmd_loop` from `BACKEND_PERMISSION_FLAG` and
`BACKEND_PERMISSION_WARNING` (`ralph:1044-1048`), which only `resolve_backend` sets. Reproducing it
would make `cmd_auto` resolve a backend — which §1 says it does not do — and would either duplicate
the conditional or require factoring it out of `cmd_loop`, which §9 says is unmodified. It would also
print four times per run, once from `auto` and once from each loop child. The children still print
the real banner, so nothing is lost.

## 8. CLI

```
ralph auto [options]
```

| Flag | Behaviour |
|------|-----------|
| `-g, --goal TEXT` | Passed to `plan`, `build` and `review`. All three prompts substitute `{{GOAL}}` (`prompts/*.md:9`). |
| `-m, --model MODEL` | Passed through. One model for the lifecycle. |
| `-b, --backend NAME` | Passed through. One backend for the lifecycle. |
| `--skip-push` | Passed through. Inert for `plan` and `review`, as it already is (`ralph:1532`). |
| `--dry-run` | See below. |
| `--no-metrics` | Passed through. |
| `-v, --verbose` | Passed through. |
| `--resume` | §5. |
| `--force` | §7. |
| `-y, --yes` | Accepted and inert: `auto` always passes `-y` down. Present so the flag does not error. |
| `-h, --help` | Usage. |

**`-n` is not accepted.** It means something different in every mode — 6 for plan and review, derived
from the item count for build — and in build mode it additionally disables the noop exit
(`ralph:1564`), which is what lets a lifecycle stop early. Each phase keeps its own iteration
resolution. Passing `-n` is an error naming that reason.

There is no per-phase model or backend flag. Running review on a second opinion stays a separate
`ralph review -b codex` invocation.

### `--dry-run`

`ralph auto --dry-run` prints the six phases in order and, for each loop phase, the exact child
command line it would receive. It **evaluates no guards and invokes no phase**, and it says so.

Two reasons, both of which sank the alternative of running the sequence with `--dry-run` passed down:

- **It would abort on a clean checkout.** `archive` and `init` have no `--dry-run` of their own, so a
  dry run must not invoke them — a dry run that moved the plan is the one destructive thing about it.
  But then nothing scaffolds the artifacts, and `require_init_artifacts` runs at `ralph:953`, ahead of
  `cmd_loop`'s own dry-run branch at `ralph:1174`. Verified: `ralph plan --dry-run` in a fresh
  workspace exits 1 with `missing workspace artifacts required for 'plan'`. So the lifecycle would die
  at phase 3 in exactly the case an operator dry-runs.
- **Its table could never show a complete run.** With nothing changing the plan, the phase-4 guard
  (`open ≥ 1`) and the phase-5 guard (`open == 0`) are mutually exclusive, so at least one of them is
  always skipped and the shape an operator wants to preview is unreachable by construction.

Simulating the state each phase would leave behind is also rejected: it is a guess about agent
behaviour rendered as a table of fact.

What remains is honest and still useful — it catches a flag that `auto` fails to forward, and it
shows the resolved model, backend and goal for each phase.

## 9. Script changes

- **Constants.** `RALPH_SELF`, `AUTO_STATE_FILE`, the phase list, the resume floor.
- **Predicates.** `have_open_items` and `have_shipped_items` beside `count_plan_items`;
  `require_open_items` and `require_review_preconditions` rewritten to call them. No behaviour change.
- **`cmd_auto`.** Flag parsing, the container check, `mkdir -p` of `.ralph`, state-file read and
  write, the phase loop, the guards, the phase-2 assertion, the report, the traps.
- **Dispatch.** An `auto)` arm, `shift`ed like `init` and `metrics` rather than passed `"$@"` whole
  like the loop modes.
- **`usage()`.** A synopsis line, a Modes entry, an `auto` options block, and one or two examples.

`cmd_loop`, `cmd_archive` and `cmd_init` are not modified. §7 exists in its current form to keep that
true for `cmd_loop`.

## 10. Metrics

Each loop phase creates its own metrics run directory, so one lifecycle leaves up to four under
`.ralph/metrics/`, and `ralph metrics` with no argument reads only the newest by mtime
(`ralph:848`) — the second `build`. Whole-lifecycle cost is the sum of four directories the operator
finds by hand. Directory names carry `$$` (`ralph:1013`), so concurrent children cannot collide.

This spec does not fix it. Run-level grouping changes the metrics layout and `cmd_metrics` and
touches every existing metrics test; it is worth doing on its own terms. Each phase prints its own
metrics path as it already does, so the directories are named in the run's output. `archive` and
`init` produce no metrics.

## 11. Testing

`test/auto.bats` is a new file. Two new helpers go in `test/test_helper.bash`:

- **A shipped-item seeder**, beside the existing `seed_open_item` (`test_helper.bash:80-82`).
- **A phase-aware, committing mock backend.** The existing `create_streaming_backend`
  (`test_helper.bash:54-73`) reads stdin to `/dev/null`, echoes three fixed events and exits: it
  cannot tick a checkbox, append a finding, or move `HEAD`, which build's noop exit reads
  (`ralph:1567-1572`). A lifecycle test needs all three. The mock distinguishes the phases by reading
  the prompt on stdin — the helper's config dir already gives each mode a distinct prompt body
  (`test_helper.bash:28-30`) — and then appends items for `plan`, ticks one item and commits for
  `build`, and appends a finding or does nothing for `review`.

Flag forwarding is asserted through **child behaviour, not dry-run output**. Three of the flags are
unobservable under `--dry-run`: `--no-metrics` because `ralph:1009` already disables metrics for any
dry run, `-v` because every verbose branch sits inside the `else` of `if $dry_run` (`ralph:1174`), and
`--skip-push` because the dry-run push line prints ahead of the `elif ! $skip_push` test
(`ralph:1533-1535`). Verified: `ralph build --dry-run` output is byte-identical with and without each
of them, so a dry-run assertion would pass against an `auto` that dropped the flag. Instead:
`--no-metrics` is asserted by the absence of `.ralph/metrics/`, `-v` by the `[verbose]` markers on
stderr, and `--skip-push` by a phase completing in a repo with no remote, where a real push would
abort it. `-g`, `-m` and `-b` remain assertable from the dry-run command line.

Cases:

- `ralph auto` is accepted; `--help` lists the mode and its options.
- `auto` exits 1 outside a container, and the message names `--force`.
- `--force` proceeds outside a container and prints one notice, not the backend banner.
- `DEVCONTAINER=true` proceeds without `--force`.
- `-n` is rejected, and the message says each phase resolves its own iterations.
- Phase 4 is skipped when the plan holds no `- [ ]` item, with that reason in the report.
- Phase 5 is skipped when the plan holds no `- [x]` item, with that reason.
- Phase 5 is skipped when open items remain, and the reason names the count.
- Phases 4 and 5 are skipped when `PROGRESS.md` is absent, naming that file — not only the plan.
- Phase 6 runs when `review` filed findings, and is skipped when it did not.
- A lifecycle whose review files nothing — phase 6 skipped — exits **0**.
- A lifecycle where every phase ran exits 0.
- A failing phase aborts: later phases do not run and are reported `not reached`.
- A failing phase makes `auto` exit 1 whatever the child's code was, using `MOCK_EXIT`
  (`test_helper.bash:70`) with a value of 3 and of 5, and the child's code appears in the report.
- Phase 2 fails the lifecycle when the config dir has no `IMPLEMENTATION_PLAN.md` template, naming
  the file and the templates directory.
- A failing phase writes `.ralph/auto-state` with the 1-based phase number and the child's exit code,
  in a workspace where `.ralph/` did not previously exist and with `--no-metrics`.
- A completed lifecycle removes `.ralph/auto-state`, including one that skipped phases.
- `--resume` with no state file exits 1 saying there is nothing to resume.
- `--resume` with a missing or out-of-range `phase` exits 1.
- `--resume` with missing artifacts exits 1 and names them.
- `--resume` never archives: a plan present before the resume is still present after it.
- `--resume` re-enters at the recorded phase, and reports earlier phases as resumed-past.
- `--resume` from a state file naming phase 1 or 2 still enters at phase 3.
- `--resume` prints the recorded phase, the child's exit status, and the manual-repair notice.
- `--dry-run` names all six phases and the child command line for each loop phase.
- `--dry-run` invokes nothing: no archive, no artifacts created in an uninitialised workspace, no
  metrics directory, and it succeeds where a real run would have needed `init`.
- `--dry-run` states that guards are evaluated at run time.
- `-g`, `-m`, `-b` reach the children, asserted from the dry-run command line.
- `-v`, `--skip-push`, `--no-metrics` reach the children, asserted by behaviour as described above.
- `-y` is accepted and changes nothing.
- The report prints on success, on skip, on abort and on a resume.
- The existing `review.bats` and build hard-stop cases still pass unchanged, proving the predicate
  refactor changed no behaviour.

## 12. Out of scope

- A fixpoint lifecycle, and any `--max-cycles` flag.
- Retrying a failed phase; backoff; transient-error classification.
- Scheduling. `auto` is a manual foreground command.
- Run-level metrics grouping across a lifecycle's phases.
- Per-phase model, backend or iteration flags.
- A `--from` / `--until` flag for an arbitrary slice. `--resume` covers the motivating case.
- Carrying `PROGRESS.md` across lifecycles (§2).
- Detecting whether a failed phase asked for a manual repair (§5).
- Any change to `cmd_loop`, `cmd_archive`, `cmd_init`, the prompts, or what an agent may write.
- Auditing what phase 6 shipped.

## 13. Follow-ups

**Close the lifecycle over its own output.** §2 accepts that review's findings are built and never
audited — the one place the lifecycle is not self-checking, and the same gap
`specs/review-phase.md` opened the review phase to close, one level up. The fix is the fixpoint:
repeat `build` until the queue is empty, then `review`, stopping when a pass files nothing. Both
halves exist — `review` converges on `plan_state_hash`, and §3's guards are the loop conditions. What
is missing is a cost bound an operator can reason about beforehand, and the right unit is agent runs
rather than cycles, since a cycle's cost is dominated by however many iterations `build` takes.

**Carry the blocker record forward.** §2 accepts that each lifecycle starts from a blank
`PROGRESS.md`, which makes `prompts/build.md:42`'s promise to "the next planning run" false under
`auto`. A scope option on `cmd_archive` — archive the plan, keep the log — is the small version.

**Refuse to resume past a repair instruction.** §5 accepts that a resume after the un-tick stop can
re-commit shipped work. Recording a reason class in the state file, or having `--resume` re-verify
that the shipped count has not regressed, closes it without making the operator classify failures.

**Forward signals to the running phase.** §5 accepts that a signal sent to `auto` alone is deferred
until the phase finishes. Running each phase with `&` and `wait`, and forwarding the signal to the
child PID, makes `kill` behave like Ctrl-C.
