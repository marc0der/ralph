# Adversarial Review Phase

Ralph has two phases. `plan` reads `specs/` and writes work items. `build` implements them one
at a time and commits. Nothing audits the result.

The build agent is the only witness to its own work. It ticks its own checkbox and writes its own
`PROGRESS.md` entry. When a shipped item satisfies its `Done when` in letter but misses the spec it
cites, or when the plan item itself drifted from that spec during planning, no phase in the loop can
detect it. The next `ralph plan` run re-derives the plan from `specs/` and treats every `- [x]` item
as settled history.

This spec adds a third phase, `review`, that attacks shipped work and files what it finds as new
plan items.

## 1. Model

**Review is a planning pass over shipped work.**

`plan` reads `specs/` and produces items. `review` reads *what was shipped* and produces items. Both
write only `IMPLEMENTATION_PLAN.md`, both converge when a pass changes nothing, and both leave the
implementing to `build`.

The handoff needs no new mechanism. Findings become `- [ ]` items, `calculate_build_iterations`
already counts exactly those, and the cycle is:

```
ralph build && ralph review && ralph build
```

Review has no separate ledger, no verdict artifact and no new state. The plan is the record: a
finding that has been filed is visible in the file, so the reviewer does not re-file it, exactly as
the planning agent does not duplicate an item it can already see.

## 2. What review examines

Review anchors on `- [x]` items in `IMPLEMENTATION_PLAN.md`. For each one it makes two checks:

1. **Code against the item.** Is the item's `Done when` criterion actually true of the tree? The
   criterion is written to be checkable non-interactively, so the reviewer must check it rather than
   trust the checkbox.
2. **Item against its spec.** Does the item, as written and as implemented, satisfy the requirement
   in the file named by its `Spec:` field? This catches drift introduced during planning, which
   `build` structurally cannot see: build executes the item's `Steps` as written and never questions
   whether the item served its spec.

Evidence comes from the tree, the test suite, `git log` / `git diff`, and `PROGRESS.md`. `PROGRESS.md`
is read as a *claim* to be verified, never as proof.

### Findings must be anchored

Every finding traces to a written document:

- a requirement in the spec named by a shipped item's `Spec:` field, or
- a documented project convention in `CLAUDE.md` or `AGENTS.md`.

If nothing written specifies the behaviour, it is not a defect. It is a feature request, and it
belongs in `specs/` followed by `ralph plan`. The reviewer never files findings from taste alone.

## 3. Severity

Findings are ordered by a closed three-level scale. The scale must be decidable from the item, its
spec and the tree, so that two passes over the same state produce the same order. Unstable ordering
rewrites the file on every pass and would prevent the convergence exit from ever firing.

| Level | Definition |
|-------|------------|
| **Critical** | The item's `Done when` is false, or the implementation contradicts the spec named in its `Spec:` field. |
| **Major** | `Done when` holds, but the spec requirement it serves is only partly met, or no test proves it. |
| **Minor** | The spec is met, but the implementation violates a documented convention in `CLAUDE.md` or `AGENTS.md`. |

Severity sets insertion position. Critical findings go above Major, Major above Minor. Position is
priority, so the next `build` run picks up the most severe finding first.

## 4. Editing rules

Review inherits the editing rules in `prompts/plan.md` verbatim:

- Refine any open item freely, inside the same schema and limits.
- Insert a new item at its correct position. Position is priority.
- Reorder open items when a dependency requires it.
- Never move an item marked `[x]` or `[~]`.
- Never delete an item. Mark it `[~]` and write its replacement.

Review may refine **any** open item, not only the ones it filed. The six-field schema is closed, so
there is nowhere to record authorship, and an open item that the review's evidence proves wrong
deserves refining whoever wrote it.

Review adds one prohibition that plan does not need:

- **Never alter a `- [x]` or `- [~]` marker.** A shipped item that fails its `Done when` produces a
  new Critical item naming the defect and the spec clause it violates. Un-ticking is forbidden: the
  `[x]` records that the work was committed, `PROGRESS.md` records the claim, and erasing either
  hides that a defect escaped. It would also let an item oscillate between `[ ]` and `[x]` across
  review and build runs, which never converges.

Findings are written as ordinary plan items: six fields, at most 150 words, 14 lines and 8 steps,
Simplified Technical English, `Spec:` pointing at the spec the finding is anchored on. The plan
records work to do, never evidence — the reviewer states the fix, not the argument for it.

## 5. Iterations and convergence

Review loops like plan, not like build.

- Default cap: 6 passes, the existing `PLAN_DEFAULT_CAP`.
- **Pass 1** sees a plan of `- [x]` items. It sweeps them and files findings as `- [ ]` items.
- **Pass 2 and later** see both shipped items and the open findings from earlier passes. Each pass
  re-sweeps the `- [x]` items *and* reconciles the open items — refining them so they state work that
  is still needed, merging overlaps, superseding any that later evidence made obsolete.
- Convergence: a pass that leaves the plan unchanged has found nothing new and nothing left to
  refine. The loop exits early and reports convergence.
- `-n` caps a review run but never disables the convergence exit, matching plan mode.

Convergence is measured with the existing `plan_state_hash`, which fingerprints
`IMPLEMENTATION_PLAN.md` plus `specs/`. Review never edits `specs/`, so in practice it fingerprints
the plan.

## 6. Commits

Review commits nothing and pushes nothing. `IMPLEMENTATION_PLAN.md` is gitignored, so its only
output is a local artifact and there is nothing to commit. HEAD cannot move during a review run, so
HEAD-based noop detection does not apply, exactly as in plan mode.

## 7. Preconditions

Review requires `IMPLEMENTATION_PLAN.md` and `PROGRESS.md`, matching build's `require_init_artifacts`
entry.

When the plan holds no `- [x]` items there is nothing to review. Ralph exits 1 before resolving the
backend, with a message naming the cause and pointing at `ralph build`, mirroring
`calculate_build_iterations`' existing error for a plan with no open items. The count reads
`^- \[x\]` from `plan_items_body`, so the example entry under `## Entry Format` is never counted.

Open `- [ ]` items are not a precondition failure. Review examines shipped items and reconciles open
ones; a build run that hit its iteration cap leaves open items behind, and that is a legitimate state
to review in.

## 8. CLI

`ralph review` is a third mode beside `plan` and `build`, invoked on its own. Ralph does not chain
modes today and this spec does not add chaining.

The flag surface is identical to plan and build: `-n`, `-g`, `-m`, `-b`, `--skip-push` (accepted and
inert, as in plan), `--dry-run`, `--no-metrics`, `-v`, `-y`, `-h`. The backend and model defaults are
the backend's own; there is no per-mode model. Running the reviewer on a second opinion is done with
the existing flags, for example `ralph review -b codex`, and the README recommends it.

Usage text gains the mode and an example:

```
  review         Audit shipped items against their specs, file findings as new plan items
```

## 9. Script changes

`cmd_loop` is already mode-parameterised. Review is a third case at each mode-specific site:

- **Dispatch** — `plan|build)` becomes `plan|build|review)`.
- **`require_init_artifacts`** — a `review)` arm requiring both artifacts.
- **Iteration default** — a `review)` arm using the plan cap, plus the no-shipped-items check.
- **State snapshot, convergence, and the metrics noop flag** — three sites currently test
  `[[ "$mode" == "plan" ]]`. Each must accept review. Use one predicate rather than repeating a
  `plan|review` test three times, so a fourth non-committing mode cannot be added to two sites and
  missed in the third.
- **Push** — the push block already tests `[[ "$mode" == "build" ]]` and needs no change.
- **`ARTIFACTS`** — add `PROMPT_review.md`, so `clean` and `archive` keep skipping it alongside the
  other prompt overrides.

`resolve_prompt` is already generic and needs no change: it resolves `PROMPT_review.md` in the
project, then `$CONFIG_DIR/prompts/review.md`.

## 10. Prompt and installation

- `prompts/review.md` — the review agent prompt, carrying the rules in sections 2 to 6 and
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

- **README** — a review section covering the phase, the `build → review → build` cycle, the severity
  scale, and the recommendation to review on a different backend.
- **CLAUDE.md and AGENTS.md** — the command table gains `review`; the loop-flow and plan-contract
  sections state that review is a non-committing mode that converges on `plan_state_hash`, that it
  may refine open items, and that `- [x]` and `- [~]` markers are immutable to it.

## 13. Testing

All tests use `--dry-run` or mock backends. No real backend CLI is required.

- `ralph review` is accepted, and `--help` lists the mode.
- Review resolves `PROMPT_review.md` over the installed `review.md`, and errors clearly when neither
  exists.
- Review requires both artifacts and names the missing one.
- Review exits 1 with a clear message when the plan holds no `- [x]` items.
- A `- [x]` example entry inside `## Entry Format` alone does not satisfy the precondition.
- Review defaults to 6 iterations, and `-n` overrides the cap.
- Review converges and exits early when a pass leaves `IMPLEMENTATION_PLAN.md` unchanged.
- The convergence exit still applies when `-n` is passed.
- Review never pushes, and `--skip-push` is accepted without error.
- Review records metrics with `mode: "review"` and `plan_items_completed: 0`.
- `clean` and `archive` skip `PROMPT_review.md`.
- `ralph init -p` scaffolds `PROMPT_review.md`; `ralph init` adds it to `.gitignore`.
- Existing plan and build tests continue to pass.

## 14. Out of scope

- Chaining modes: no `--then-review` flag and no `ralph cycle` command.
- A review ledger, verdict artifact or `REVIEW.md`.
- Per-mode default models, or enforcing a different backend for review.
- Findings that no spec or guardrail document anchors.
- Review editing `specs/`, source files, or any `- [x]` marker.
- Commits, pushes and pull request comments.
