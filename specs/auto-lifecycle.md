# Unattended Lifecycle (`auto`)

Ralph has four commands that a human strings together by hand. A full cycle is `ralph init`, then
`ralph plan`, then `ralph build`, then `ralph review`, then `ralph build` again to ship what review
filed, then `ralph archive` to close the cycle out. Each one is a separate invocation, and the
operator watches each finish to decide whether the next may start.

That decision is the chore. Once the prompts and rules are tuned, it carries no judgement: it reads
`IMPLEMENTATION_PLAN.md`, counts two kinds of checkbox, and starts the next command or does not.
This spec adds a fifth command, `auto`, that makes the decision itself and runs the cycle end to
end without an operator.

## 1. Model

**`auto` is a guarded sequence, not a pipeline.**

The phases cannot be chained with `&&`. Each mode carries hard preconditions that run unconditionally
beside `require_init_artifacts` and exit non-zero when they fail, and the ordinary outcomes of one
phase routinely violate the next phase's preconditions. Three cases, all reachable on a healthy
project:

- **The happy path fails at the second `build`.** A review that finds nothing files nothing, so the
  plan is left with no `- [ ]` item. `require_open_items` exits 1. The best available outcome —
  everything shipped, the audit clean — would be reported as a failed run and would take the cycle's
  exit code with it.
- **`review` refuses whenever `build` stopped short.** `require_review_preconditions` demands zero
  open items. `build` exits early after 2 consecutive noops, and `calculate_build_iterations` grants
  only `ceil(n × 1.2)` iterations. Both leave open items behind as a matter of course.
- **`plan` can produce nothing to build.** A plan pass that converges without writing an item leaves
  the plan empty, and `build` exits 1 against it.

So `auto` reads the plan between phases and decides what is legal next, using the same two counts the
preconditions gate on. A phase whose preconditions do not hold is **skipped**, not failed: the
condition that stops `ralph review` from running on its own is, inside a lifecycle, an ordinary fact
about where the work has got to.

### The guards and the hard stops must not drift

`auto` and the `require_*` functions ask the plan the same two questions for opposite purposes. The
hard stops turn a false answer into `exit 1`; `auto` turns it into a skipped phase. Two readings of
"can this mode run?" maintained separately will diverge, and the failure is silent in the worst
direction: `auto` starts a phase its own guard believed legal, and the child exits 1, which `auto`
reports as a lifecycle failure.

Both readings therefore share one predicate. `have_open_items` and `have_shipped_items` wrap the
existing `count_plan_items` calls, `require_open_items` and `require_review_preconditions` are
rewritten in terms of them, and `auto`'s guards call the same two functions. This is a refactor with
no behaviour change of its own.

### `auto` adds no agent behaviour

`auto` launches no backend, resolves no prompt, and reads no template. It runs existing commands and
counts checkboxes. Every rule about what an agent may write stays where it is, in `prompts/`, and
this spec does not touch it. A lifecycle that produces a bad plan is a planning defect, fixed in
`prompts/plan.md`; `auto` is only the thing that decided `plan` could run.

## 2. The sequence

Six phases, in order:

```
archive → init → plan → build → review → build
```

`archive` runs **first**, not last. The artifacts a run produces are the record of what it did, and
they are the first thing an operator reads when an unattended run finishes at 4am. Archiving at the
end moves `IMPLEMENTATION_PLAN.md` and `PROGRESS.md` into `.ralph/<timestamp>/` and leaves the tree
with no plan, so the evidence has to be dug out of a timestamped directory — and on an aborted run it
buries exactly the evidence that the abort made worth reading. Archiving at the front means a
lifecycle always ends with its own plan and progress in place, and each new `auto` run clears the
residue of the previous one and re-initialises.

The consequence is that a plain `ralph auto` is a **fresh lifecycle every time**. It does not resume
or extend the previous run's plan: that plan is moved to `.ralph/<timestamp>/` and `plan` re-derives
a new one from `specs/`. This is the intended semantics, and it is why `--resume` (section 5) is a
separate entry mode rather than the default behaviour.

`build` appears twice. A phase is therefore addressed by **index**, never by name — a resume that
named `build` could not tell the two apart.

### What the second build is for

The second `build` exists to ship what `review` filed. It has a second use that follows from the
guards: when `build` at index 3 stopped short and `review` was skipped because open items remained,
the guard at index 5 finds those same items still open and runs. The stalled work gets a second pass
within the same lifecycle.

### One review round is a deliberate limit

A single `review` means the findings `review` files are built by the second `build` and then **ship
unaudited**. The lifecycle does not close over its own output.

The alternative was a fixpoint — build until the queue is empty, review, repeat until a review pass
files nothing — which is what ralph's convergence machinery already computes, and which would audit
review's own findings. It is rejected here for cost predictability: an unattended fixpoint has no
bound an operator can reason about before starting it, and a review/build pair that oscillates never
terminates. A fixed sequence costs at most four agent runs and the operator knows that in advance.
Section 12 keeps the fixpoint as a follow-up.

## 3. Phase guards

Before each phase, `auto` evaluates that phase's guard against the plan **as it stands on disk at
that moment** — never against a decision made earlier in the run. A guard that holds runs the phase.
A guard that fails skips it and records the reason.

| Phase | Runs when | Skip reason when it does not |
|-------|-----------|------------------------------|
| `archive` | always (except under `--resume`) | — |
| `init` | always (except under `--resume`) | — |
| `plan` | always | — |
| `build` | the plan holds at least one `- [ ]` item | `no open items in IMPLEMENTATION_PLAN.md` |
| `review` | the plan holds at least one `- [x]` item **and** no `- [ ]` item | `no shipped items to audit`, or `N open items remain` |
| `build` | as above | as above |

The `review` guard produces two distinct reasons because they mean opposite things to an operator: no
shipped items means the lifecycle produced nothing, and open items remaining means it produced
something and did not finish. Collapsing them into one message would hide which.

`build` and `review` also skip when `IMPLEMENTATION_PLAN.md` is absent, with that as the reason. The
file is absent only on a `--resume` into a workspace that has none, which section 5 rejects before
any phase runs; the guard covers the case where a phase removes the file mid-run.

`archive` and `init` are unguarded because both are already idempotent and self-describing.
`cmd_archive` reports `Nothing to archive.` on an empty tree, and `scaffold` skips any artifact that
already exists. Neither can fail on a state `auto` could put them in.

`plan` is unguarded because it is the phase that creates the state every later guard reads. Its own
precondition — `IMPLEMENTATION_PLAN.md` exists — is guaranteed by the `init` that precedes it.

## 4. Phases run as child processes

`auto` invokes each phase as a child process, `"$RALPH_SELF" <phase> <flags>`, rather than calling
`cmd_loop` in-process.

Every failure path in `cmd_loop` ends in `exit`: a non-zero backend, a jq parse failure, a rejected
push. Called in-process, the first of those would take the whole lifecycle down with it, with no
chance for `auto` to record where it stopped or to print what had run. A child turns the same failure
into an exit status the parent decides on.

It also keeps each phase's state to itself. `cmd_loop` sets a global `ARGS` from `getopt`, installs
an `EXIT` trap for its raw-stream temp file, and installs `SIGINT`/`SIGTERM` traps that exit 130.
Running six phases through that in one process would have each phase's traps and globals overwrite
the last one's.

`RALPH_SELF` is the absolute path of the running script, resolved once at startup before any command
can change directory, so it stays valid whichever directory a phase runs from and whether ralph was
invoked by path or found on `PATH`.

`archive` and `init` are invoked the same way, for uniform status capture, even though neither can
realistically fail.

## 5. Failure, interruption and `--resume`

### On failure

A phase that exits non-zero **aborts the lifecycle immediately**. `auto` does not retry, does not
skip ahead, and does not run the phases after it.

Retrying a failed phase was considered and rejected. It absorbs a transient API error, which is the
common overnight failure, but it costs a full extra agent run whenever the cause is real — an expired
credential, a bad model name, a missing backend CLI — and those fail identically every time. An
unattended run that doubles its spend on a broken configuration is worse than one that stops and says
so.

`auto` then writes `.ralph/auto-state` naming the phase it died on, prints the phase table, and exits
with **the child's own exit code**, unchanged. A backend that exited 42 makes `auto` exit 42. The
code is diagnostic and passing it through is the only way an operator sees it without reading the
scrollback.

### The state file

`.ralph/auto-state` is plain `key=value` lines, parsed by field and never sourced:

```
phase_index=3
phase=build
failed_exit=42
failed_at=2026-09-14T02:17:09Z
```

`phase_index` is what `--resume` reads. The rest is for the operator.

The file records no flags. A resume uses the flags given on its own command line, so an operator who
diagnoses the failure as a bad model can resume with a different `-m` without editing state. Replaying
the original flags would make that impossible, and would silently reapply a `-b` that was the cause.

`auto` removes the state file at the start of every non-resume run, and on any run that reaches the
last phase — including one that skipped phases, which is a completed lifecycle. The file survives only
an abort or an interrupt.

### `--resume`

`ralph auto --resume` re-enters the lifecycle at the recorded phase. It **never runs `archive` or
`init`**: `archive` would move the artifacts of the very run being resumed into
`.ralph/<timestamp>/`, which is precisely the work a resume exists to preserve. The resume entry
point is therefore floored at index 2, `plan`, whatever the state file says.

`--resume` fails before any phase runs when there is no state file (`no interrupted lifecycle to
resume`), or when `IMPLEMENTATION_PLAN.md` or `PROGRESS.md` is missing — a resume into a workspace
with no artifacts has nothing to continue, and the skip guards must not quietly turn it into a
lifecycle that does nothing and reports success.

`--resume` is incompatible with nothing else; every other flag applies to it normally.

### On interruption

`auto` traps `SIGINT` and `SIGTERM`. Ctrl-C reaches the whole foreground process group, so the child
`cmd_loop` receives it too and exits 130 under its own existing trap. `auto` treats both routes the
same way: write the state file for the phase in flight, print the phase table, exit 130. An
interrupted lifecycle is resumable exactly like a failed one.

## 6. Reporting

### The phase table

Every `auto` run ends by printing what each phase did, whatever the outcome:

```
Lifecycle summary
  1. archive   ran
  2. init      ran
  3. plan      ran
  4. build     ran
  5. review    skipped — 3 open items remain
  6. build     ran
```

A guarded sequence reaches the end whether or not it did the work, so the table is the only place the
shape of the run is recorded. It prints on abort and on interrupt too, with the reached phase marked
`failed` and the phases after it marked `not reached`.

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | Every phase ran. |
| 3 | The lifecycle reached the end, and at least one phase was skipped. |
| *child's code* | A phase failed; the code is that phase's own. |
| 130 | Interrupted. |

A skipped phase needs its own code because an unattended caller cannot otherwise tell a complete
lifecycle from a `build` that stalled and took `review` and the second `build` down with it. Both
reach the last phase and both would exit 0.

The code is **3, not 2**. `cmd_loop` propagates jq's exit status on a summary parse failure, and jq
exits 2 — so a lifecycle that failed in jq and a lifecycle that completed with skips would be
indistinguishable to CI, which is the one reader the code exists for.

Skipping is not an error and does not abort. A `review` skipped for having nothing to audit is a
lifecycle that had nothing to audit, which is a legitimate outcome, not a fault.

## 7. `auto` refuses to run outside a container

`auto` exits non-zero when `DEVCONTAINER` is not `true`, unless `--force` is given.

`plan`, `build` and `review` warn about running outside a container and then prompt `Continue anyway?
[y/N]` when attached to a terminal. `auto` is unattended by definition, so it must pass `-y` to its
children, and that prompt is the one safety check `-y` removes. An hours-long unsupervised agent loop
running with the backend's permission flag on the host — where the ralph tree, `~/.ssh` and the rest
of `$HOME` are all reachable — is the exact case that prompt exists for.

`--force` keeps the escape hatch for a CI runner that is already an isolated container but sets no
`DEVCONTAINER` variable. It prints the same warning banner the other modes print and proceeds.

The children still receive `-y`, so `auto` never blocks on a prompt whichever way it started.

## 8. CLI

```
ralph auto [options]
```

`auto` takes the flag surface of the loop modes, minus `-n`, plus three of its own.

| Flag | Behaviour |
|------|-----------|
| `-g, --goal TEXT` | Passed to `plan`, `build` and `review`. All three prompts substitute `{{GOAL}}`. |
| `-m, --model MODEL` | Passed through. One model for the whole lifecycle. |
| `-b, --backend NAME` | Passed through. One backend for the whole lifecycle. |
| `--skip-push` | Passed through. Inert for `plan` and `review`, as it already is. |
| `--dry-run` | See below. |
| `--no-metrics` | Passed through. |
| `-v, --verbose` | Passed through. |
| `--resume` | Section 5. |
| `--force` | Section 7. |
| `-y, --yes` | Accepted and inert: `auto` always passes `-y` down. Present so the flag does not error. |
| `-h, --help` | Usage. |

**`-n` is not accepted.** It means something different in every mode — 6 for plan and review, derived
from the item count for build — and an `auto`-level `-n` would have to pick one meaning and impose it
on phases where it is wrong. In build mode it additionally disables the noop exit, which is the thing
that lets a lifecycle stop early. Each phase keeps its own iteration resolution.

There is no per-phase model or backend flag. Running review on a second opinion stays a separate
`ralph review -b codex` invocation, as it is today.

### `--dry-run`

`--dry-run` passes through to `plan`, `build` and `review`, which print their resolved prompts as
they already do. `archive` and `init` have no `--dry-run` of their own, so `auto` must **not** invoke
them — it prints what they would do and moves on. A dry run that actually archived the plan would be
the one destructive thing about it.

The phase table from a dry run is an **approximation and says so**. Guards are evaluated against the
tree as it stands, and under `--dry-run` nothing changes it: `archive` does not move the plan, `init`
does not scaffold a fresh one, and `plan` writes no items. So the guards see the current plan at every
index, where a real run would see the plan each phase left behind.

## 9. Script changes

- **Constants.** `RALPH_SELF`, `AUTO_STATE_FILE`, the `AUTO_PHASES` array, the resume floor, and the
  skipped-lifecycle exit code.
- **Predicates.** `have_open_items` and `have_shipped_items` beside `count_plan_items`;
  `require_open_items` and `require_review_preconditions` rewritten to call them. No behaviour change.
- **`cmd_auto`.** Flag parsing, the container check, state-file handling, the phase loop, the guards,
  the table, the traps.
- **Dispatch.** An `auto)` arm. `cmd_auto` takes its own arguments, so it is `shift`ed like `init` and
  `metrics`, not passed `"$@"` whole like the loop modes.
- **`usage()`.** A synopsis line, a Modes entry, an `auto` options block, and one or two examples.

`cmd_loop` is not modified. `cmd_archive` and `cmd_init` are not modified.

## 10. Metrics

Each loop phase creates its own metrics run directory, so one `auto` run leaves up to four of them
under `.ralph/metrics/`, and `ralph metrics` with no argument reads only the most recent — the second
`build`. The whole-lifecycle cost is the sum of four directories an operator has to find by hand.

This spec does not fix it. A run-level grouping is a change to the metrics layout and to
`cmd_metrics`, it touches every existing metrics test, and it is worth doing on its own terms rather
than as a rider. Section 12 records it as a follow-up. `auto` prints the metrics path of each phase as
that phase's child already does, so the directories are at least named in the run's own output.

`archive` and `init` produce no metrics.

## 11. Testing

All tests use `--dry-run` or the mock backends already in `test/test_helper.bash`. No real backend CLI
is required. `test/auto.bats` is a new file; the shipped-item seeding that several cases need is a
helper in `test_helper.bash` beside `seed_open_item`, not repeated inline.

- `ralph auto` is accepted, and `--help` lists the mode with its own options.
- `auto` exits non-zero outside a container, and the message names `--force`.
- `--force` proceeds outside a container and prints the warning banner.
- `DEVCONTAINER=true` proceeds without `--force`.
- `-n` is rejected with a message saying each phase resolves its own iterations.
- The phases run in order, and a dry run names all six.
- `build` is skipped when the plan holds no `- [ ]` item, with that reason in the table.
- `review` is skipped when the plan holds no `- [x]` item, with that reason.
- `review` is skipped when open items remain, and the reason names the count.
- The second `build` runs when `review` filed findings, and is skipped when it did not.
- A lifecycle where every phase ran exits 0.
- A lifecycle that reached the end with a skipped phase exits 3.
- A failing phase aborts the lifecycle: later phases do not run, and they are marked `not reached`.
- A failing phase propagates the child's own exit code, using the mock backend's `MOCK_EXIT`.
- A failing phase writes `.ralph/auto-state` naming the phase and its index.
- A completed lifecycle removes `.ralph/auto-state`, including one that skipped phases.
- `--resume` with no state file exits non-zero with a message saying there is nothing to resume.
- `--resume` with missing artifacts exits non-zero and names them.
- `--resume` never runs `archive`: a plan present before the resume is still present after it.
- `--resume` re-enters at the recorded phase.
- `--resume` from a state file naming index 0 or 1 still enters at `plan`.
- `--dry-run` does not archive: the plan is untouched after the run.
- `--dry-run` does not create artifacts in an uninitialised workspace.
- The dry-run table is labelled as an approximation.
- `-g`, `-m`, `-b`, `-v`, `--skip-push` and `--no-metrics` reach the child phases, asserted through
  the dry-run command line.
- `-y` is accepted and changes nothing.
- The phase table prints on success, on skip, and on abort.
- `have_open_items` and `have_shipped_items` agree with the `require_*` functions: the existing
  `review.bats` and build hard-stop cases still pass unchanged.

## 12. Out of scope

- A fixpoint lifecycle: looping build/review until a review pass files nothing, and any
  `--max-cycles` flag. Section 2 records why, and the follow-up below.
- Retrying a failed phase, and any backoff or transient-error classification.
- Run-level metrics grouping across the phases of one lifecycle.
- Per-phase model, backend or iteration flags.
- A `--from` / `--until` flag to run part of the sequence. `--resume` covers the case that motivated
  this spec; running an arbitrary slice is what the individual commands already do.
- Scheduling: `auto` is a foreground command. Running it nightly is cron's job.
- Any change to `cmd_loop`, to the prompts, or to what an agent may write.
- Auditing what the second `build` shipped.

## 13. Follow-up: close the lifecycle over its own output

Section 2 accepts that `review`'s findings are built and never audited. That is the one place the
lifecycle is not self-checking, and it is the same gap `specs/review-phase.md` opened the review phase
to close — one level up.

The fix is the fixpoint: repeat `build` until the queue is empty, then `review`, and stop when a
review pass files nothing or a cycle cap is reached. Both halves already exist. `review` converges on
`plan_state_hash` and reports it, and the guards in section 3 are exactly the loop conditions. What is
missing is an operator-facing bound on cost that a fixed sequence gives for free, and that is the
problem to solve before adding it — a cycle cap expressed in agent runs rather than in cycles would
be a better unit, since a cycle's cost is dominated by however many iterations `build` takes.

Until then, the second `build` is the lifecycle's last word, and a cautious operator runs
`ralph review` by hand afterwards.
