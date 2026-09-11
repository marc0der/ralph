# Adversarial Review Phase

Ralph has two phases. `plan` reads `specs/` and writes work items. `build` implements them one
at a time and commits. Nothing audits the result.

The build agent is the only witness to its own work. It ticks its own checkbox and writes its own
`PROGRESS.md` entry. When a shipped item satisfies its `Done when` in letter but never implemented
what the item names, or when the code it committed is defective, no phase in the loop can detect it.
The next `ralph plan` run re-derives the plan from `specs/` and treats every `- [x]` item as settled
history.

This spec adds a third phase, `review`, that attacks shipped work and files what it finds as new
plan items.

## 1. Model

**Review audits build fidelity.**

`plan` reads `specs/` and produces items. `review` reads *what was shipped against those items* and
produces items. Both write `IMPLEMENTATION_PLAN.md`, both converge when a pass changes nothing, and
both leave the implementing to `build`.

### Planning is trusted

Review never judges the plan. `plan` loops to convergence over `specs/`, so by the time `build`
starts, the plan is a settled artifact: it has already decided what the specs require, how to
decompose it, and in what order. Review's only question is whether `build` honoured it.

This is a boundary, not a simplification. A reviewer that may also fault the plan has no fixed
standard to measure against — it can always find the work wanting by proposing an item the planner
did not write, and the run that motivated this rule did exactly that. It audited a three-item plan,
confirmed all three items were implemented correctly, and then reported the *feature* as
unimplemented because the plan had never scoped the rest of it. That judgement may be right, but it
belongs to `plan`, which owns decomposition and can act on it. Filed as a review finding it is
unfalsifiable, and it makes the plan a moving target that no `build` run can ever satisfy.

The boundary also keeps the phases independently fixable. A bad plan is a planning defect, fixed by
another `ralph plan` run over the specs. A bad implementation of a good plan is a build defect, and
that is the only thing review reports.

The handoff needs no new mechanism. Findings become `- [ ]` items, `calculate_build_iterations`
already counts exactly those, and the cycle is:

```
ralph build && ralph review && ralph build
```

Review has no ledger and no verdict artifact. The plan is the record: a finding that has been filed
is visible in the file, so the reviewer does not re-file it, exactly as the planning agent does not
duplicate an item it can already see.

## 2. What review examines

Review anchors on `- [x]` items in `IMPLEMENTATION_PLAN.md`. For each one it makes two checks:

1. **Fidelity.** Did `build` implement what the item names, across its `Scope`, `Files`, `Steps` and
   `Done when`? See the falsification rule below — the reviewer must prove a specific failure, not
   merely observe that the suite is red.
2. **Code quality.** Did `build` write defective code — a bug, an unhandled error, an unhandled edge
   case — anywhere in the commits that shipped the item? An item can be followed to the letter and
   still ship something broken, and `build` is the only witness to that too. The unit is the commit,
   not the item's `Files`: `prompts/build.md` Phase 3 requires `build` to fix an unrelated red suite
   and explicitly overrides the item's `Scope` to do it, so code outside the `Scope` ships under the
   item and is audited with it.

Check 1 asks whether `build` followed the item. Check 2 asks whether the code it wrote works.
Nothing else is in range. `specs/` is not an input to a review pass at all, which states the
section 1 boundary as a rule about what to read rather than a rule about how to judge — an easier
instruction to follow, and an easier one to see broken in a transcript. Ralph does not enforce it:
no backend is launched with a path restriction, so the ban lives in the prompt like every other
rule here.

Evidence comes from the tree, the test suite, `git log` / `git diff`, and `PROGRESS.md`. `PROGRESS.md`
is read as a *claim* to be verified, never as proof. Section 4 states the one exception.

### Findings must be item-local

A finding must belong to one shipped item. It proves that `build` missed something the item names —
a symbol, file, flag, command or behaviour — or that the code the item wrote is defective.

**A failing test suite is not per-item evidence.** Most real `Done when` criteria include a
whole-suite conjunct: in this repository, 32 of 35 read `bats test/ passes and <small extra>`. That
conjunct is true or false for every shipped item simultaneously, so a red suite would otherwise
falsify all of them at once. A red suite produces **at most one finding for the whole run**, filed
once, naming the failing tests. It never produces one finding per item.

### The plan is the requirement

Every finding traces to a shipped item. The item states the work, so the item — not `specs/`, not a
convention document, not the reviewer's own judgement — decides whether `build` fell short.

This also disposes of the documentation-wording problem the spec-anchored rule could not solve.
Section 12 of this spec *prescribes* the content of `CLAUDE.md`, `AGENTS.md` and `README.md`. While
findings anchored on spec clauses, a stale sentence in one of those files was a legitimate deviation
from a legitimate clause, so review duly filed items to correct documentation wording and broke no
rule doing it. The behaviour-only restriction on anchors was an attempt to close that off. With the
plan as the only requirement the question resolves on its own, and section 3 states the rule: a
document is in range exactly when a shipped item named it and told `build` what to write.

**Review never reads, creates or edits anything under `specs/`.** An observation that belongs to no
shipped item is reported in the pass's final assistant message — which the loop's summary filter
prints and the retained `iter-NNN.stream.jsonl` keeps — and written to no file. Not reading `specs/`
serves section 1: a reviewer cannot second-guess a decision it never read. Not writing `specs/`
additionally stops it manufacturing its own standard, and would otherwise defeat convergence,
because `plan_state_hash` fingerprints `specs/` as well as the plan.

### Coverage

Every pass audits **every** `- [x]` item. Coverage is not sampled, capped or deferred to a later
pass.

**One context audits the whole plan.** The prompt forbids dispatching one subagent per item or per
slice of items. Parallel reading of source and tests stays available, as it is in `prompts/plan.md`
and `prompts/build.md`; it is the *judgement* that must not be split.

A sliced audit cannot rank. Section 3's budget requires the pass to order every finding against
every other finding and file only the worst, and a subagent holding 3 of 33 items scores its slice
against nothing. It returns everything it noticed, and the parent is instructed to aggregate rather
than to triage — so the slices sum instead of competing. The run that motivated this rule filed one
finding per shipped item: 16 findings against 16 items, all at the lower severity, none of them a
defect.

Coverage and ranking pull against each other only if the audit is memory-bound. It is not: the
budget caps *output*, not how much the pass reads, and the pass may read the plan and the tree in
whatever order and with whatever parallel reads it needs.

Each pass must state its coverage — the number of items audited against the number in the plan. It
is the only signal that a sweep fell short, so it is required on every backend.

## 3. Severity

Findings carry one of two levels. The level must be decidable from the item and the tree, so that
two passes over the same state agree.

| Level | Definition |
|-------|------------|
| **Critical** | `build` did not implement what the item names. A symbol, file, flag or behaviour the item names is absent, or behaves against the item. |
| **Major** | `build` implemented the item, but the code is defective: a bug, an unhandled error, or an unhandled edge case. |

The two levels are the two checks in section 2. `Critical` is check 1 failing and `Major` is check 2
failing, so every finding carries the level of the check that produced it and no separate judgement
is needed.

Both levels carry the same burden of proof: name a behaviour, and show the tree does not have it.
`Major` is not a weaker standard of evidence — it names a different target, the code `build` wrote
rather than the item's own claim.

**Where both levels fit, the finding is `Critical`.** Any part of what the item names being absent
is check 1 failing, so a named behaviour that works on one code path and not another is `Critical`.
Without this tie-break the two definitions overlap across the whole partial-implementation band —
old `Major` covered it explicitly — and two passes could label the same finding differently, change
the plan, and defeat the convergence exit.

Two classes the old rules banned outright are readmitted, both as check 1 and therefore both
`Critical`. A **test** is in range when the item called for one: the `Steps` or `Done when` name a
test and no test asserts the behaviour the item names. A **document** is in range when the item
named it and stated what to write. In each case the item asked for a specific deliverable and the
deliverable is absent, which is an unmet step like any other.

The line that matters is *the item asked for it*. The deleted `or no test proves it` clause was
satisfiable against nearly every shipped item because absent coverage is always arguable; "no test
asserts the behaviour this item names" is a fact about the tree, and a test that does assert it
closes the item however weak the reviewer finds it. The same line governs documents: prescribed
wording is auditable, stale wording at large is not.

Three classes remain unfileable at any level: a test the item never called for, wording in a
document no shipped item named, and a naming, style or convention preference. A fourth is added by
section 1: an item the reviewer would have planned differently.

There is no third level. A convention violation is not a review finding — `CLAUDE.md` and `AGENTS.md`
record conventions rather than work, and the plan is the only requirement review measures against.

**Severity is written in the title**, as its first word followed by a colon:

```
- [ ] **Critical: pass the permission flag to the backend**
```

Position alone cannot carry severity, because a later pass cannot read position back as severity —
review's findings sit in the same list as plan's items with nothing to distinguish them. Encoding the
level in the title keeps it greppable and readable across passes, needs no seventh field, and costs
one word of the ten-word title budget. Without it, each pass re-derives severity, re-sorts the list,
changes the file hash, and the convergence exit never fires.

Critical findings sit above Major findings. Section 7 guarantees the plan holds no other open items
when a review run starts, so findings are only ever ranked against each other.

### Finding budget

`IMPLEMENTATION_PLAN.md` holds **at most 5 open findings** at one time. A pass counts the `- [ ]`
items before it writes, and files at most the difference. A pass that finds the plan already at 5
files nothing.

**The cap is an invariant on the plan, not a counter per pass.** Stated per pass it would bound
nothing: the loop runs up to 6 passes, so 5 each would permit 30 items and merely spread the
inflation across the run. Stated as a standing limit it self-enforces and needs no new state, since
the plan file is the counter. Section 7 guarantees a run starts at zero open items, so the standing
cap and a per-run cap are the same number.

The budget is what makes a pass an audit. Ranking is only meaningful when something is dropped: a
pass that files everything it noticed has exercised no judgement, and it buries the defect that
mattered under the ones that did not. Dropped findings are not lost — a dropped finding may be named
in the final message, never in the plan, and a later run rediscovers it once `build` has drained the
queue.

## 4. Editing rules

Review takes the seven editing rules in `prompts/plan.md` in full:

1. Refine any open item freely, inside the same schema and limits.
2. Insert a new item at its correct position. Position is priority.
3. Reorder open items when a dependency requires it.
4. Never move an item marked `[x]` or `[~]`.
5. Place new and reordered items below closed items when priority allows.
6. Never delete an item. Mark it `[~]` and write its replacement.
7. Resolve every item marked `[~]`. Read its `PROGRESS.md` entry.

Review adds three rules of its own:

- **Never alter a `- [x]` marker.** A shipped item that fails its claim produces a new Critical item
  naming the defect. Un-ticking is forbidden: the `[x]` records that the work was committed, and
  erasing it hides that a defect escaped. It would also let an item oscillate between `[ ]` and
  `[x]` across review and build runs, which never converges.
- **Record every supersession.** When review marks an item `[~]`, it appends a `PROGRESS.md` entry
  stating why. Rule 7 tells the next `plan` run to resolve a `[~]` item by reading its `PROGRESS.md`
  entry; a supersession with no entry leaves that run nothing to read, and it will resurrect the item
  as open — reintroducing the duplicate the supersession removed.
- **Resolve blocked findings instead of re-filing them.** When `build` cannot implement a finding it
  marks the item `[~]` and records the contradiction in `PROGRESS.md`, as `prompts/build.md` Phase 2
  requires. Review reads that entry and appends a *different* replacement item that routes around
  the blocker. It never re-files the original verbatim, and it never stays silent because a `[~]`
  item for the same defect already exists. **This is the one place review treats a `PROGRESS.md`
  entry as information to act on rather than a claim to verify** — build's record of why an item was
  blocked is the only account of it that exists.

Findings are written as ordinary plan items: six fields, at most 150 words, 14 lines and 8 steps,
Simplified Technical English. The `Spec:` field names the audited item — `IMPLEMENTATION_PLAN.md`
plus the item's quoted title — which keeps the six-field schema closed while saying truthfully what
the finding traces to.

Inheriting the audited item's own `Spec:` value was the alternative and is rejected. It would hand
the finding a spec citation review never read, and `prompts/build.md` Phase 2 instructs `build` to
mark an item `[~]` when the spec contradicts it: a `Major` code-quality finding carrying a clause
that says nothing about the defect invites exactly that supersession. It would also break the
meaning the field carries for every other reader, since `prompts/plan.md` and
`templates/IMPLEMENTATION_PLAN.md` define `Spec` as the requirement the item serves.

The title is quoted rather than a position. Review inserts and reorders open items, so an index goes
stale as soon as an item lands above it, and the plan's own rule forbids citing line numbers for the
same reason. A shipped item's title is stable: review never moves or alters a `- [x]` item.

A run-wide red-suite finding is the one finding that belongs to no single item. It writes
`IMPLEMENTATION_PLAN.md` and the words `whole plan` in place of a title.

The plan records work to do, never evidence — the reviewer states the fix, not the argument for it.

## 5. Iterations and convergence

Review loops like plan, not like build.

- Default cap: 6 passes, the existing `PLAN_DEFAULT_CAP`.
- **Pass 1** sees a plan of `- [x]` items and no open items, guaranteed by the precondition in
  section 7. It audits them all and files findings as `- [ ]` items.
- **Pass 2 and later** see the shipped items plus the open findings from earlier passes — which are
  review's own output and nothing else. Each pass re-audits every `- [x]` item and reconciles those
  open findings: refining them so they state work that is still needed, merging overlaps, and
  superseding any that later evidence made obsolete.
- A pass already at the section 3 budget files nothing, so it leaves the plan unchanged and the
  convergence exit fires on it. This is the intended end of a saturated run: the queue is full, and
  `build` must drain it before another audit adds to it.
- Convergence: a pass that leaves the plan unchanged has found nothing new and has nothing left to
  refine. The loop exits early.
- `-n` caps a review run but never disables the convergence exit, matching plan mode.

Convergence is measured with the existing `plan_state_hash`. It fingerprints
`IMPLEMENTATION_PLAN.md` plus `specs/`; review neither reads nor writes `specs/`, so in practice it
fingerprints the plan. The `specs/` term is inert for review rather than wrong, and it is left in
place because plan mode needs it and both modes share the one function.

### The exit line must state what was audited

A clean review produces no commit, no file change, and a metrics line of zeros — the same observable
state as a backend that read the prompt and did nothing at all. That is the most likely outcome on a
healthy project, and it must not be indistinguishable from silent failure.

Review's early-exit message therefore reports scope, counted by ralph itself rather than claimed by
the agent:

```
Review converged — pass 2 found nothing new. Audited 33 shipped items.
```

The count comes from ralph's own `grep -c '^- \[x\]'` over `plan_items_body`. This asserts scope, not effort: it does not prove the agent swept
everything, which is what the per-pass coverage statement in section 2 is for.

## 6. Commits and writes

Review commits nothing and pushes nothing. `IMPLEMENTATION_PLAN.md` and `PROGRESS.md` are both
gitignored, so its output is local and there is nothing to commit. HEAD cannot move during a review
run, so HEAD-based noop detection does not apply, exactly as in plan mode.

Review writes two files: `IMPLEMENTATION_PLAN.md` always, and `PROGRESS.md` only to record a
supersession (section 4). It writes nothing else.

## 7. Preconditions

The phases are a chain. `build` hard-stops when `plan` has not run, and `review` hard-stops until
`build` has actually finished. Review requires:

- **Both artifacts present** — `IMPLEMENTATION_PLAN.md` and `PROGRESS.md`, matching build's
  `require_init_artifacts` entry. Review reads `PROGRESS.md` and writes supersession entries to it,
  so the requirement is real, not symmetry.
- **At least one `- [x]` item.** With none, there is no shipped work to audit. Ralph exits non-zero
  with a message naming the cause.
- **No `- [ ]` items.** Review audits finished work, so it refuses to start while any item is still
  open, and points at `ralph build`. This makes pass 1's "no open items" state true by construction,
  which is what lets section 3 rank findings against each other alone and never against planning
  work review did not derive.

Items marked `[~]` do not block a review run.

Both counts read `^- \[x\]` and `^- \[ \]` from `plan_items_body`, so the exemplar entry under
`## Entry Format` is never counted.

**The checks are unconditional.** They run beside `require_init_artifacts`, not inside the iteration
resolution, so `-n` cannot bypass them.

**Build gets the same treatment.** `calculate_build_iterations` is called only inside
`if ! $hard_override`, so `ralph build -n 5` currently runs against a plan with no open items instead
of stopping. Both hard stops move out of that guard and run unconditionally: build exits non-zero
when the plan holds no `- [ ]` item, and review exits non-zero on its own three conditions, whether
or not `-n` is given.

This changes existing build behaviour and has a wide test blast radius. `ralph init` scaffolds a plan
whose only column-zero entry is the exemplar inside `## Entry Format`, which `plan_items_body`
strips, so an initialised workspace holds zero open items. Ninety-eight `ralph build … -n …`
invocations across `test/backend.bats`, `test/confirm.bats`, `test/dry_run.bats`,
`test/metrics.bats`, `test/pipeline.bats` and `test/validation.bats` currently pass only because `-n`
skips the check. Each affected test must seed a real `- [ ]` item first. Add one helper to
`test/test_helper.bash` for this and call it from the affected tests, rather than repeating the
fixture inline ninety-eight times.

### The anchor is local and destructible

Review's anchor set lives only in `IMPLEMENTATION_PLAN.md`, which is gitignored and untracked.
`ralph archive` moves it to `.ralph/<timestamp>/` and `ralph clean` deletes it, so closing out a
cycle before reviewing makes that cycle's shipped items unreviewable. A fresh clone has the shipped
code but never had the plan.

Two consequences for this spec:

- The no-shipped-items error must name `.ralph/<timestamp>/` as the likely location of an archived
  plan, instead of only advising `ralph build` — which is wrong advice when the work is already
  shipped and pushed.
- The README states the ordering: review before `archive` or `clean`.

Reviewing an archived plan in place is out of scope (section 14).

## 8. CLI

`ralph review` is a third mode beside `plan` and `build`, invoked on its own. Ralph does not chain
modes today and this spec does not add chaining.

The flag surface is identical to plan and build: `-n`, `-g`, `-m`, `-b`, `--skip-push` (accepted and
inert, as in plan), `--dry-run`, `--no-metrics`, `-v`, `-y`, `-h`. Backend and model defaults are the
backend's own; there is no per-mode model. Running the reviewer on a second opinion uses the existing
flags, for example `ralph review -b codex`, and the README recommends it.

Every one of these `usage()` strings changes, not only the mode list:

- The synopsis line `ralph <plan|build> [options]` becomes `ralph <plan|build|review> [options]`.
- The Modes list gains: `review — Audit shipped items against the plan, file findings as new plan
  items`.
- The `-n` description ("plan default: 6, build: calculated from the plan") names review's default
  of 6 and states that review behaves as plan does.
- The `--skip-push` description ("plan never pushes") covers review too.
- The Examples block gains the `build → review → build` chain.

## 9. Script changes

`cmd_loop` is already mode-parameterised. Review is a third case at each mode-specific site:

- **Dispatch** — `plan|build)` becomes `plan|build|review)`.
- **`require_init_artifacts`** — a `review)` arm requiring both artifacts.
- **Iteration default** — a `review)` arm using the plan cap. Neither phase's hard stop lives here:
  both run unconditionally beside `require_init_artifacts` (see section 7), so the `hard_override`
  guard governs only which number `max_iterations` takes.
- **State snapshot, convergence, and the metrics noop flag** — three sites currently test
  `[[ "$mode" == "plan" ]]`. Each must accept review. Use one predicate rather than repeating a
  `plan|review` test three times, so a fourth non-committing mode cannot be added to two sites and
  missed in the third.
- **The convergence message** — a fourth site. `ralph:1462` hardcodes "Plan converged — pass N
  changed nothing", which would announce the wrong phase for a review run. The wording becomes
  mode-derived, and review's carries the audit counts from section 5.
- **Push** — the push block already tests `[[ "$mode" == "build" ]]` and needs no change.

`resolve_prompt` is already generic and needs no change: it resolves `PROMPT_review.md` in the
project, then `$CONFIG_DIR/prompts/review.md`.

`PROMPT_review.md` is added to `ARTIFACTS` for documentation only. It changes no behaviour:
`cmd_clean` and `cmd_archive` both skip every `PROMPT_*.md` entry, so the file is preserved either
way. Section 13 therefore has no test for it — a test would pass against an unmodified script and
could never catch a regression.

## 10. Prompt and installation

- `prompts/review.md` — the review agent prompt, carrying the rules in sections 2 to 7 and
  substituting `{{GOAL}}` like the other two.
- `install.sh` copies it to `$CONFIG_DIR/prompts/review.md`.
- `ralph init -p` scaffolds `PROMPT_review.md` alongside the other two.
- `ralph init` adds `PROMPT_review.md` to the target project's `.gitignore` entries.
- This repository's own `.gitignore` gains `PROMPT_review.md`.

## 11. Metrics

Metrics need no schema change. Review records `mode: "review"`, uses the plan-state fingerprint for
its `noop` flag, and reports `plan_items_completed: 0` on every iteration, since review never ticks a
checkbox. `ralph metrics` summarises a review run without modification.

## 12. Documentation

**README — keep it proportionate.** Review is a third mode, not a headline feature. It gets the same
weight as `plan` and `build` and no more. No new top-level section, no severity table, no essay on
adversarial independence. The complete set of edits:

- One row in the `## Commands` table, matching the density of the `plan` row.
- `### Options (plan and build)` becomes `### Options (plan, build and review)`. The `-n` row notes
  that review behaves as plan does; the `--skip-push` row notes that review never pushes either.
- One or two lines in the `### Examples` block, including the `build → review → build` chain.
- `### Loop metrics` and `## Prompt resolution` name review alongside plan and build, one word or one
  list entry each.
- The `## Project artifacts` note on optional prompt overrides gains `PROMPT_review.md`.
- One sentence, where `archive` and `clean` are described, stating that review must run first.

**CLAUDE.md and AGENTS.md** carry the full detail instead, since they are the contract the agent
reads: the command table gains `review`; the loop-flow and plan-contract sections state that review
is a non-committing mode that converges on `plan_state_hash`, that it requires a fully shipped plan,
that it may refine and supersede open items but must record a supersession in `PROGRESS.md`, and that
`- [x]` markers are immutable to it.

## 13. Testing

All tests use `--dry-run` or mock backends. No real backend CLI is required.

- `ralph review` is accepted, and `--help` lists the mode.
- `usage()` shows the updated synopsis line, and its `-n` and `--skip-push` descriptions name review.
- Review resolves `PROMPT_review.md` over the installed `review.md`, and errors clearly when neither
  exists.
- Review requires both artifacts and names the missing one.
- Review exits non-zero when the plan holds no `- [x]` items, and the message names `.ralph/`.
- Review exits non-zero when any `- [ ]` item remains, and points at `ralph build`.
- Review still exits non-zero on both conditions when `-n` is passed, proving the gates are not
  inside the iteration-resolution branch.
- A plan whose only `- [x]` line is the exemplar under `## Entry Format` does not satisfy the
  shipped-items precondition.
- A plan with no `## Items` heading still counts correctly, covering `plan_items_body`'s whole-file
  fallback.
- `ralph build -n 5` exits non-zero on a plan with no `- [ ]` items, closing the same hole in build.
- Every existing test that runs build with `-n` seeds an open item and still passes.
- Review defaults to 6 iterations, and `-n` overrides the cap.
- Review converges and exits early when a pass leaves `IMPLEMENTATION_PLAN.md` unchanged.
- The convergence message names review, not plan, and carries the audited-items count.
- The convergence exit still applies when `-n` is passed.
- Review never pushes, and `--skip-push` is accepted without error.
- Review records metrics with `mode: "review"` and `plan_items_completed: 0`.
- `ralph init -p` scaffolds `PROMPT_review.md`; `ralph init` adds it to `.gitignore`.
- Existing plan and build tests continue to pass.

## 14. Out of scope

- Chaining modes: no `--then-review` flag and no `ralph cycle` command.
- A review ledger, verdict artifact or `REVIEW.md`.
- Reviewing an archived plan in place, or a plan path argument for `ralph review`.
- Per-mode default models, or enforcing a different backend for review.
- Findings that belong to no shipped item, and any severity tier resting on `CLAUDE.md` or `AGENTS.md`.
- Review judging the plan, rather than `build`'s implementation of it.
- Review reading or editing `specs/`, source files, or any `- [x]` marker.
- Commits, pushes and pull request comments.

## 15. Follow-up: harden `Done when`

Section 2 has to neutralise whole-suite `Done when` criteria because the existing plan is full of
them — 32 of 35 in this repository read `bats test/ passes and <small extra>`. That is a weakness in
the *planning* phase, not in review: a criterion that only restates "the suite is green" proves
nothing about the item it belongs to, and it is exactly what makes shipped work hard to audit.

`prompts/plan.md`'s "Verification criteria" section should require a `Done when` that names the
item's own behaviour — a specific symbol, file, flag, output or error path the agent can check — and
should forbid a bare suite run as the whole criterion. Tightening it is a separate change from this
spec, but review's value stays limited until it happens: the sharper the criteria, the more of
section 2's check 1 becomes decidable.
