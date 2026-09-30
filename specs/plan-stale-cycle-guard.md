# Plan Stale Cycle Guard

Follow-up to `specs/one-shot-review.md` §3. That spec made `.ralph/cycle-base` a cycle artifact that
`archive` and `clean` remove. This spec stops `plan` from starting a new cycle on top of a built one
that was never archived.

## 1. Problem

A cycle ends when its artifacts are archived or cleaned. `auto` always archives first, but the
manual flow does not enforce that step. An operator who runs `plan`, `build` and `review`, then
runs `ralph plan -g <next goal>` without `ralph archive`, starts the next feature inside the old
cycle:

- `write_cycle_base` writes the base only when it is absent, so the next `build` keeps the old base.
- The next `review` reads every change since the old base as the cycle's work. It re-reads work
  that an earlier review already audited, and can file findings against it.
- The old shipped items stay in `IMPLEMENTATION_PLAN.md`, and their `Spec:` fields stay in the
  anchor set.

Nothing fails. The review is silently wider than the cycle.

## 2. Rule

`plan` refuses to run when `.ralph/cycle-base` exists and `IMPLEMENTATION_PLAN.md` holds no `- [ ]`
item and no `- [~]` item.

That state means the cycle was built and never archived: build has written a base, and every item
has shipped. Ralph records nothing when a review runs, so the rule cannot tell a reviewed cycle
from an unreviewed one. It treats both as stale, and §6 accepts the cost.

Two states stay legal:

- **An open item.** The cycle is still in progress, for example after review has filed findings.
  Re-planning mid-cycle stays legal.
- **A `- [~]` item.** The next `plan` writes the replacement for a superseded or blocked item
  (`docs/plan-format.md`, `prompts/plan.md`), so a `[~]` item keeps the cycle open.

Items are counted in `plan_items_body`, so the exemplar entry under `## Entry Format` never counts
as open.

## 3. Behaviour

### `plan`

The check is a hard stop in `cmd_loop`'s plan branch, directly after the goal check. When both
fail, the missing goal is reported. It runs after `require_init_artifacts` and before
`resolve_backend`, so neither `-n` nor `--dry-run` bypasses it and a missing backend CLI does not
mask it. It leaves every file unchanged, prints to stderr and exits 1:

```
Error: .ralph/cycle-base is left from a cycle that was built but not archived.
Run 'ralph archive' (or 'ralph clean'), then 'ralph init', before running 'ralph plan'.
```

The second line names `init` because `archive` and `clean` remove `IMPLEMENTATION_PLAN.md`, and
`plan` requires it.

### `auto`

A plain `auto` run never meets the stale state: phase 1 archives the base before phase 3 plans.

`--resume` can. When `archive` fails or is interrupted before it moves anything, the state file
records phase 1, and resume raises that to `RESUME_FLOOR` (3). The old plan and base are still in
place, so the plan child would exit 1 on the new hard stop, and so would every later resume. That
breaks the rule that `auto` never starts a child that exits 1 on a gate.

`cmd_auto` therefore gets a phase 3 guard beside the existing phase guards. It uses the same
condition as §2 and the same predicates. It is a refusal, not a skip: planning cannot be skipped
over a stale cycle. Before it starts the plan child, it prints to stderr, prints the report, and
exits 1, leaving the state file unchanged:

```
Error: .ralph/cycle-base is left from a cycle that was built but not archived.
Re-run 'ralph auto -g <goal>' without --resume; phase 1 archives the old cycle.
```

## 4. Documentation

- `CLAUDE.md` and `AGENTS.md`: the paragraph on hard preconditions now covers `plan`, and the
  paragraph on `auto`'s phase guards names the phase 3 guard. The cycle-base check in `cmd_auto`
  is duplicated inline, so the paragraph lists it with the other checks kept in step by hand.
- `README.md` "Starting a new goal": the snippet runs `ralph init` between `ralph archive` and
  `ralph plan`, and says that `plan` enforces the step.
- `docs/plan-format.md`: the paragraph on preconditions states the `plan` rule.
- Code comments: the hard-stop comment in `cmd_loop` and the phase-guard comment in `cmd_auto`
  name the new check.

This spec narrows the risk `specs/one-shot-review.md` §18 lists as "Manual flows that never
archive". §6 lists what remains. The older spec is a record and stays unedited.

## 5. Testing

Every refusal test passes `-g`, so the goal check cannot be the stop that fires. Each asserts exit
1 and the error on stderr.

### Guard and ordering

- `plan` fails with the error above when the base exists and every item is `- [x]`.
- `plan --dry-run` and `plan -n 1` fail the same way.
- `plan` fails with the error when no backend CLI is on `PATH`, and leaves `IMPLEMENTATION_PLAN.md`
  unchanged.
- `plan` without `-g` reports the missing goal when the base is also stale.
- `plan` runs when the base exists and the plan holds a `- [ ]` item.
- `plan` runs when the base exists and the plan holds a `- [~]` item and no `- [ ]` item.
- `plan` runs when the plan holds no open items and no base exists.

### End to end

- After `archive` and then `init`, `plan` runs over what was a stale cycle.
- After `clean` and then `init`, `plan` runs the same way.

### `auto`

- A plain `auto` run with a stale base gets past phase 3, because phase 1 archives.
- `auto --resume` with a state file at phase 1 and the stale base still present refuses with the
  error above, starts no plan child, and leaves the state file unchanged.

## 6. Accepted risks

- **Re-planning before review.** `plan`, `build`, then `plan` again to add items before any review
  is refused. The operator either reviews first or archives, and archiving drops the first build's
  work from review.
- **A leftover `[~]` item.** A finished cycle that still holds a `[~]` item passes the guard, and
  its base carries over.
- **Open items from an abandoned cycle.** Review filed findings and the operator plans a new goal
  instead. The guard passes, and the old base and anchors carry over. Ralph cannot tell re-planning
  mid-cycle from a new goal with leftovers.
- **An old shipped plan with no base.** For example, a plan from before `one-shot-review`. The guard
  passes, and the old anchors remain.

## 7. Out of scope

- A flag to override the guard. `ralph archive` is the way to end a cycle.
- A marker that records a finished review. It would close the first risk in §6, at the cost of a
  new artifact.
- Changes to `build`, which keeps the first build's base by design.
